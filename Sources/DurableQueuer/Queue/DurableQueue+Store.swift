import Foundation
import GRDB

extension DurableQueue {
    nonisolated func effectiveOptions(
        defaults: JobDefaults,
        options: DispatchOptions,
        id: JobID,
        now: Date
    ) throws -> EffectiveJobOptions {
        let queue = (options.queue ?? defaults.queue).trimmingCharacters(in: .whitespacesAndNewlines)
        try validate(queue: queue)
        let delay = options.delay ?? 0
        guard delay.isFinite, delay >= 0 else {
            throw DurableQueueError.invalidDispatchOptions("delay must be finite and nonnegative")
        }
        guard options.availableAt?.timeIntervalSinceReferenceDate.isFinite ?? true,
              options.deadline?.timeIntervalSinceReferenceDate.isFinite ?? true else {
            throw DurableQueueError.invalidDispatchOptions("dates must be finite")
        }
        let maxAttempts = options.maxAttempts ?? defaults.maxAttempts
        guard maxAttempts > 0 else {
            throw DurableQueueError.invalidDispatchOptions("maxAttempts must be positive")
        }
        let retryPolicy = options.retryPolicy ?? defaults.retryPolicy
        if let issue = retryPolicy.validationIssue {
            throw DurableQueueError.invalidDispatchOptions("retryPolicy: \(issue)")
        }
        let timeout = options.timeout ?? defaults.timeout
        if let timeout, (!timeout.isFinite || timeout <= 0) {
            throw DurableQueueError.invalidDispatchOptions("timeout must be finite and positive")
        }
        let requirements = options.requirements ?? defaults.requirements
        let lane: JobExecutionLane
        if requirements.contains(.networkConnectivity) && requirements.contains(.externalPower) {
            lane = .processingNetworkAndPower
        } else if requirements.contains(.networkConnectivity) {
            lane = .processingNetwork
        } else if requirements.contains(.externalPower) {
            lane = .processingPower
        } else {
            lane = options.lane ?? defaults.lane
        }
        let availableAt = options.availableAt
            ?? now.addingTimeInterval(delay)
        let tags = try Set(options.tags.map { tag in
            let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else {
                throw DurableQueueError.invalidTag
            }
            return normalized
        })

        return EffectiveJobOptions(
            queue: queue,
            priority: options.priority ?? defaults.priority,
            availableAt: availableAt,
            deadline: options.deadline,
            timeout: timeout,
            maxAttempts: maxAttempts,
            retryPolicy: retryPolicy,
            requirements: requirements,
            lane: lane,
            uniqueKey: try normalizedOptional(options.uniqueKey, name: "uniqueKey"),
            uniquePolicy: options.uniquePolicy,
            idempotencyKey: try normalizedOptional(options.idempotencyKey, name: "idempotencyKey")
                ?? id.description,
            tags: tags
        )
    }

    nonisolated private func normalizedOptional(_ value: String?, name: String) throws -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            throw DurableQueueError.invalidDispatchOptions("\(name) must not be empty")
        }
        return normalized
    }

    nonisolated func validate(queue: String) throws {
        guard !queue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DurableQueueError.invalidQueueName
        }
    }

    func claimNextJob(lane: JobExecutionLane? = nil) async throws -> JobRecord? {
        try await claimJob(id: nil, lane: lane)
    }

    func claimJob(id: JobID) async throws -> JobRecord? {
        try await claimJob(id: id, lane: nil)
    }

    private func claimJob(
        id: JobID?,
        lane: JobExecutionLane?
    ) async throws -> JobRecord? {
        let now = configuration.now()
        let nowValue = now.databaseMilliseconds
        let leaseToken = UUID().uuidString
        let leaseExpiry = now.addingTimeInterval(configuration.leaseDuration)
            .databaseMilliseconds

        return try await database.value.write { db in
            while true {
                guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT j.*
                    FROM durable_queue_jobs j
                    LEFT JOIN durable_queue_controls c ON c.queue_name = j.queue_name
                    WHERE j.state = 'queued'
                      AND j.available_at <= ?
                      AND (j.deadline_at IS NULL OR j.deadline_at > ?)
                      AND (? IS NULL OR j.id = ?)
                      AND (? IS NULL OR j.lane = ?)
                      AND COALESCE(c.is_paused, 0) = 0
                      AND (
                        c.maximum_concurrency IS NULL OR (
                            SELECT COUNT(*) FROM durable_queue_jobs active
                            WHERE active.queue_name = j.queue_name AND active.state = 'running'
                        ) < c.maximum_concurrency
                      )
                    ORDER BY j.priority DESC, j.available_at, j.created_at, j.id
                    LIMIT 1
                    """,
                arguments: [
                    nowValue,
                    nowValue,
                    id?.description,
                    id?.description,
                    lane?.rawValue,
                    lane?.rawValue,
                ]
                ) else {
                    return nil
                }
                let rawID: String = row["id"]
                do {
                    _ = try JobRecord(row: row)
                } catch {
                    try Self.quarantineCorruptMetadata(
                        db: db,
                        rawID: rawID,
                        message: String(describing: error),
                        now: nowValue
                    )
                    continue
                }
                try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'running', lease_token = ?, lease_expires_at = ?,
                        attempt_count = attempt_count + 1, updated_at = ?
                    WHERE id = ? AND state = 'queued' AND available_at <= ?
                    """,
                    arguments: [leaseToken, leaseExpiry, nowValue, rawID, nowValue]
                )
                guard db.changesCount == 1,
                      let claimed = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM durable_queue_jobs WHERE id = ?",
                    arguments: [rawID]
                      ) else {
                    continue
                }
                try db.execute(
                    sql: """
                        INSERT INTO durable_queue_attempts (job_id, attempt, started_at)
                        VALUES (?, ?, ?)
                        """,
                    arguments: [rawID, (claimed["attempt_count"] as Int), nowValue]
                )
                return try JobRecord(row: claimed)
            }
        }
    }

    func recoverExpiredWork() async throws {
        let now = configuration.now()
        let nowValue = now.databaseMilliseconds
        let interruptionRetryDelay = configuration.interruptionRetryDelay

        let transitions = try await database.value.write { db -> ([JobID], [JobID], [JobID]) in
            var recovered: [JobID] = []
            var cancelled: [JobID] = []
            var failed: [JobID] = []
            let expired = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM durable_queue_jobs
                    WHERE state = 'running' AND lease_expires_at <= ?
                    """,
                arguments: [nowValue]
            )
            for row in expired {
                let rawID: String = row["id"]
                let record: JobRecord
                do {
                    record = try JobRecord(row: row)
                } catch {
                    try Self.quarantineCorruptMetadata(
                        db: db,
                        rawID: rawID,
                        message: String(describing: error),
                        now: nowValue
                    )
                    if let uuid = UUID(uuidString: rawID) { failed.append(JobID(uuid)) }
                    continue
                }
                if record.cancelRequested {
                    try db.execute(
                        sql: """
                            UPDATE durable_queue_jobs
                            SET state = 'cancelled', lease_token = NULL,
                                lease_expires_at = NULL, finished_at = ?, updated_at = ?
                            WHERE id = ? AND state = 'running'
                            """,
                        arguments: [nowValue, nowValue, record.id.description]
                    )
                    try Self.finishAttempt(
                        db: db,
                        record: record,
                        outcome: JobState.cancelled.rawValue,
                        message: record.stopReason?.rawValue,
                        now: nowValue
                    )
                    try Self.resolveDependents(
                        of: record.id.description,
                        in: db,
                        now: nowValue
                    )
                    cancelled.append(record.id)
                } else if record.attempt >= record.maxAttempts {
                    try Self.setFailed(
                        db: db,
                        record: record,
                        failure: JobFailure(
                            kind: .leaseExpired,
                            message: "The process stopped before the lease completed.",
                            occurredAt: now
                        ),
                        now: nowValue
                    )
                    failed.append(record.id)
                } else {
                    try db.execute(
                        sql: """
                            UPDATE durable_queue_jobs
                            SET state = 'queued', available_at = ?, lease_token = NULL,
                                lease_expires_at = NULL, updated_at = ?,
                                last_failure_kind = ?, last_failure_message = ?,
                                last_failure_at = ?
                            WHERE id = ? AND state = 'running'
                            """,
                        arguments: [
                            now.addingTimeInterval(interruptionRetryDelay)
                                .databaseMilliseconds,
                            nowValue,
                            JobFailureKind.leaseExpired.rawValue,
                            "The process stopped before the lease completed.",
                            nowValue,
                            record.id.description,
                        ]
                    )
                    try Self.finishAttempt(
                        db: db,
                        record: record,
                        outcome: "interrupted",
                        message: "The process stopped before the lease completed.",
                        now: nowValue
                    )
                    recovered.append(record.id)
                }
            }

            let deadlineIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM durable_queue_jobs
                    WHERE state = 'queued' AND deadline_at IS NOT NULL AND deadline_at <= ?
                    """,
                arguments: [nowValue]
            )
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'failed', finished_at = ?, updated_at = ?,
                        last_failure_kind = ?,
                        last_failure_message = 'The job deadline passed before execution.',
                        last_failure_at = ?, failure_hook_pending = 1
                    WHERE state = 'queued' AND deadline_at IS NOT NULL AND deadline_at <= ?
                    """,
                arguments: [
                    nowValue,
                    nowValue,
                    JobFailureKind.deadlineExceeded.rawValue,
                    nowValue,
                    nowValue,
                ]
            )
            for id in deadlineIDs {
                try Self.resolveDependents(of: id, in: db, now: nowValue)
            }
            try db.execute(
                sql: "DELETE FROM durable_queue_locks WHERE expires_at <= ?",
                arguments: [nowValue]
            )
            failed.append(contentsOf: deadlineIDs.compactMap(UUID.init(uuidString:)).map(JobID.init))
            return (recovered, cancelled, failed)
        }
        for id in transitions.0 { await emit(kind: .recovered, jobID: id) }
        for id in transitions.1 { await emit(kind: .cancelled, jobID: id) }
        for id in transitions.2 { await emit(kind: .failed, jobID: id) }
    }

    nonisolated static func setFailed(
        db: Database,
        record: JobRecord,
        failure: JobFailure,
        now: Int64
    ) throws {
        let safeRetryPolicy = try JobPayloadCodec.encoder().encode(RetryPolicy.none)
        try db.execute(
            sql: """
                UPDATE durable_queue_jobs
                SET state = 'failed', lease_token = NULL, lease_expires_at = NULL,
                    lane = 'processing', payload_version = MAX(1, payload_version),
                    max_attempts = MAX(1, max_attempts), retry_policy = ?, stop_reason = NULL,
                    finished_at = ?, updated_at = ?, last_failure_kind = ?,
                    last_failure_message = ?, last_failure_at = ?,
                    failure_hook_pending = 1, failure_hook_available_at = 0,
                    failure_hook_token = NULL, failure_hook_expires_at = NULL
                WHERE id = ? AND state = 'running' AND lease_token IS ?
                """,
            arguments: [
                safeRetryPolicy,
                now,
                now,
                failure.kind.rawValue,
                failure.message,
                failure.occurredAt.databaseMilliseconds,
                record.id.description,
                record.leaseToken,
            ]
        )
        guard db.changesCount == 1 else {
            throw DurableQueueError.leaseLost(record.id)
        }
        try finishAttempt(
            db: db,
            record: record,
            outcome: JobState.failed.rawValue,
            message: failure.message,
            now: now
        )
        try resolveDependents(of: record.id.description, in: db, now: now)
    }

    nonisolated static func quarantineCorruptMetadata(
        db: Database,
        rawID: String,
        message: String,
        now: Int64
    ) throws {
        let safeRetryPolicy = try JobPayloadCodec.encoder().encode(RetryPolicy.none)
        try db.execute(
            sql: """
                UPDATE durable_queue_jobs
                SET state = 'failed', lease_token = NULL, lease_expires_at = NULL,
                    lane = 'processing', payload_version = MAX(1, payload_version),
                    max_attempts = MAX(1, max_attempts), retry_policy = ?, stop_reason = NULL,
                    finished_at = ?, updated_at = ?, last_failure_kind = ?,
                    last_failure_message = ?, last_failure_at = ?,
                    failure_hook_pending = 0, failure_hook_token = NULL,
                    failure_hook_expires_at = NULL
                WHERE id = ? AND state IN ('blocked', 'queued', 'running')
                """,
            arguments: [
                safeRetryPolicy,
                now,
                now,
                JobFailureKind.corruptMetadata.rawValue,
                "Corrupt durable metadata: \(message)",
                now,
                rawID,
            ]
        )
    }
}
