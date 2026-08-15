import Foundation
import GRDB

extension DurableQueue {
    public func dispatch<J: DurableJob>(
        _ job: J,
        options: DispatchOptions = .defaults
    ) async throws -> DispatchReceipt {
        let prepared = try prepareDispatch(job, options: options)
        let receipt = try await database.value.write { db in
            try prepared.insert(in: db)
        }

        for replacedJobID in receipt.replacedJobIDs {
            activeStopReasons[replacedJobID] = .replaced
            activeOperations[replacedJobID]?.cancel()
            await emit(kind: .cancelled, jobID: replacedJobID)
        }
        if receipt.result == .inserted || receipt.result == .replaced {
            await emit(kind: .dispatched, jobID: receipt.id)
        }
        return receipt
    }

    /// Inserts independent jobs in one SQLite transaction.
    public func dispatchAll(_ requests: [JobRequest]) async throws -> [DispatchReceipt] {
        guard !requests.isEmpty else { return [] }
        let now = configuration.now()
        let prepared = try requests.map { try prepareDispatch($0, now: now) }
        let receipts = try await database.value.write { db in
            try prepared.map { try $0.insert(in: db) }
        }
        for receipt in receipts {
            for replacedID in receipt.replacedJobIDs {
                activeStopReasons[replacedID] = .replaced
                activeOperations[replacedID]?.cancel()
                await emit(kind: .cancelled, jobID: replacedID)
            }
            if receipt.result != .existing {
                await emit(kind: .dispatched, jobID: receipt.id)
            }
        }
        return receipts
    }

    public func dispatchDebounced<J: DurableJob>(
        _ job: J,
        key: String,
        delay: TimeInterval,
        options: DispatchOptions = .defaults
    ) async throws -> DispatchReceipt {
        var options = options
        options.uniqueKey = key
        options.uniquePolicy = .replace
        options.delay = delay
        return try await dispatch(job, options: options)
    }

    /// Inserts a job with the caller's existing GRDB transaction.
    ///
    /// Call this overload only from a `DatabaseWriter.write` closure. The job
    /// insert then commits or rolls back with the application's other writes.
    /// Transactional dispatch does not emit the process-local `dispatched`
    /// event because the transaction can still roll back after this method
    /// returns. Durable status and later events remain authoritative.
    public nonisolated func dispatch<J: DurableJob>(
        _ job: J,
        options: DispatchOptions = .defaults,
        in database: Database
    ) throws -> DispatchReceipt {
        let prepared = try prepareDispatch(job, options: options)
        return try prepared.insert(in: database)
    }

    nonisolated func prepareDispatch<J: DurableJob>(
        _ job: J,
        options: DispatchOptions
    ) throws -> PreparedJobDispatch {
        guard registry.job(for: J.typeIdentifier) != nil else {
            throw DurableQueueError.jobTypeNotRegistered(J.typeIdentifier)
        }
        guard J.payloadVersion > 0 else {
            throw DurableQueueError.invalidPayloadVersion(
                type: J.typeIdentifier,
                version: J.payloadVersion
            )
        }

        let now = configuration.now()
        let id = JobID()
        let encoded = try JobPayloadCodec.encoder().encode(job)
        let payload = try configuration.payloadProtection?.protect(encoded) ?? encoded
        try validatePayloadSize(payload)
        return PreparedJobDispatch(
            id: id,
            typeIdentifier: J.typeIdentifier,
            payload: payload,
            payloadVersion: J.payloadVersion,
            options: try effectiveOptions(
                defaults: J.defaults,
                options: options,
                id: id,
                now: now
            ),
            createdAt: now
        )
    }

    nonisolated func prepareDispatch(_ request: JobRequest, now: Date) throws -> PreparedJobDispatch {
        guard registry.job(for: request.typeIdentifier) != nil else {
            throw DurableQueueError.jobTypeNotRegistered(request.typeIdentifier)
        }
        guard request.payloadVersion > 0 else {
            throw DurableQueueError.invalidPayloadVersion(
                type: request.typeIdentifier,
                version: request.payloadVersion
            )
        }
        let id = JobID()
        let payload = try configuration.payloadProtection?.protect(request.payload)
            ?? request.payload
        try validatePayloadSize(payload)
        return PreparedJobDispatch(
            id: id,
            typeIdentifier: request.typeIdentifier,
            payload: payload,
            payloadVersion: request.payloadVersion,
            options: try effectiveOptions(
                defaults: request.defaults,
                options: request.options,
                id: id,
                now: now
            ),
            createdAt: now
        )
    }

    nonisolated private func validatePayloadSize(_ payload: Data) throws {
        if let maximum = configuration.maximumPayloadBytes, payload.count > maximum {
            throw DurableQueueError.invalidDispatchOptions(
                "payload is \(payload.count) bytes; the configured maximum is \(maximum) bytes"
            )
        }
    }
}

struct PreparedJobDispatch: Sendable {
    let id: JobID
    let typeIdentifier: String
    let payload: Data
    let payloadVersion: Int
    let options: EffectiveJobOptions
    let createdAt: Date

    func insert(in database: Database) throws -> DispatchReceipt {
        let retryData = try JobPayloadCodec.encoder().encode(options.retryPolicy)
        let nowValue = createdAt.databaseMilliseconds
        let activeRows: [Row]
        if let uniqueKey = options.uniqueKey {
            activeRows = try Row.fetchAll(
            database,
            sql: """
                SELECT id, chain_id FROM durable_queue_jobs
                WHERE queue_name = ? AND unique_key = ?
                  AND state IN ('blocked', 'queued', 'running')
                ORDER BY created_at, id
                """,
            arguments: [options.queue, uniqueKey]
            )
        } else {
            activeRows = []
        }
        if options.uniquePolicy == .keep,
           let rawID: String = activeRows.last?["id"],
           let uuid = UUID(uuidString: rawID) {
            return DispatchReceipt(id: JobID(uuid), result: .existing)
        }

        var replacedJobIDs: [JobID] = []
        if options.uniquePolicy == .replace, !activeRows.isEmpty {
            replacedJobIDs = activeRows.compactMap { row in
                let rawID: String = row["id"]
                return UUID(uuidString: rawID).map(JobID.init)
            }
            try database.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'cancelled', cancel_requested = 1,
                        stop_reason = ?,
                        lease_token = NULL, lease_expires_at = NULL,
                        finished_at = ?, updated_at = ?,
                        failure_hook_pending = 0, failure_hook_token = NULL,
                        failure_hook_expires_at = NULL
                    WHERE queue_name = ? AND unique_key = ?
                      AND state IN ('blocked', 'queued', 'running')
                    """,
                arguments: [
                    JobStopReason.replaced.rawValue,
                    nowValue,
                    nowValue,
                    options.queue,
                    options.uniqueKey,
                ]
            )
            for jobID in replacedJobIDs {
                try database.execute(
                    sql: """
                        UPDATE durable_queue_attempts
                        SET finished_at = ?, outcome = 'cancelled', message = 'replaced'
                        WHERE job_id = ? AND finished_at IS NULL
                        """,
                    arguments: [nowValue, jobID.description]
                )
                try DurableQueue.resolveDependents(
                    of: jobID.description,
                    in: database,
                    now: nowValue
                )
            }
        }

        let shouldAppend = (options.uniquePolicy == .append
            || options.uniquePolicy == .appendOrReplace) && !activeRows.isEmpty
        let state = shouldAppend ? JobState.blocked : JobState.queued
        let tailID: String? = shouldAppend ? activeRows.last?["id"] : nil
        let existingChainID: String? = shouldAppend ? activeRows.last?["chain_id"] : nil
        let chainID = shouldAppend ? (existingChainID ?? UUID().uuidString) : nil

        try database.execute(
            sql: """
                INSERT INTO durable_queue_jobs (
                    id, type_identifier, payload, payload_version, queue_name,
                    state, lane, priority, available_at, deadline_at,
                    timeout_seconds, attempt_count, max_attempts, retry_policy,
                    requires_network, requires_power, unique_key, idempotency_key,
                    cancel_requested, progress, chain_id, created_at, updated_at,
                    failure_hook_pending
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?, ?, 0)
                """,
            arguments: [
                id.description,
                typeIdentifier,
                payload,
                payloadVersion,
                options.queue,
                state.rawValue,
                options.lane.rawValue,
                options.priority,
                options.availableAt.databaseMilliseconds,
                options.deadline.map { $0.databaseMilliseconds },
                options.timeout,
                options.maxAttempts,
                retryData,
                options.requirements.contains(.networkConnectivity) ? 1 : 0,
                options.requirements.contains(.externalPower) ? 1 : 0,
                options.uniqueKey,
                options.idempotencyKey,
                chainID,
                nowValue,
                nowValue,
            ]
        )

        for tag in options.tags {
            try database.execute(
                sql: "INSERT INTO durable_queue_job_tags (job_id, tag) VALUES (?, ?)",
                arguments: [id.description, tag]
            )
        }
        if let tailID {
            try database.execute(
                sql: """
                    UPDATE durable_queue_jobs SET chain_id = ?
                    WHERE id = ? AND chain_id IS NULL
                    """,
                arguments: [chainID, tailID]
            )
            try database.execute(
                sql: """
                    INSERT INTO durable_queue_dependencies
                    (job_id, prerequisite_id, behavior) VALUES (?, ?, 'onSuccess')
                    """,
                arguments: [id.description, tailID]
            )
        }
        return DispatchReceipt(
            id: id,
            result: shouldAppend ? .appended : (replacedJobIDs.isEmpty ? .inserted : .replaced),
            replacedJobID: replacedJobIDs.first,
            replacedJobIDs: replacedJobIDs
        )
    }
}
