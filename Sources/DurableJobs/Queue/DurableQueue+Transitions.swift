import Foundation
import GRDB

extension DurableQueue {
    func markSucceeded(_ record: JobRecord) async throws {
        let now = configuration.now().databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'succeeded', progress = 1, lease_token = NULL,
                        lease_expires_at = NULL, finished_at = ?, updated_at = ?
                    WHERE id = ? AND state = 'running' AND lease_token = ?
                    """,
                arguments: [now, now, record.id.description, record.leaseToken]
            )
            guard db.changesCount == 1 else {
                throw DurableQueueError.leaseLost(record.id)
            }
            try Self.finishAttempt(
                db: db,
                record: record,
                outcome: JobState.succeeded.rawValue,
                message: nil,
                now: now
            )
            try Self.resolveDependents(of: record.id.description, in: db, now: now)
        }
        await emit(kind: .succeeded, jobID: record.id)
    }

    func markCancelled(_ record: JobRecord) async throws {
        let now = configuration.now().databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'cancelled', lease_token = NULL, lease_expires_at = NULL,
                        stop_reason = COALESCE(stop_reason, ?), finished_at = ?, updated_at = ?
                    WHERE id = ? AND state = 'running' AND lease_token = ?
                    """,
                    arguments: [
                        JobStopReason.userCancelled.rawValue,
                        now,
                        now,
                        record.id.description,
                        record.leaseToken,
                    ]
                )
            guard db.changesCount == 1 else {
                throw DurableQueueError.leaseLost(record.id)
            }
            try Self.finishAttempt(
                db: db,
                record: record,
                outcome: JobState.cancelled.rawValue,
                message: record.stopReason?.rawValue,
                now: now
            )
            try Self.resolveDependents(of: record.id.description, in: db, now: now)
        }
        await emit(kind: .cancelled, jobID: record.id)
    }

    func handleFailure(
        _ failure: JobFailure,
        for record: JobRecord,
        forcePermanent: Bool = false
    ) async throws {
        let now = configuration.now()
        if forcePermanent || record.attempt >= record.maxAttempts {
            try await database.value.write { db in
                try Self.setFailed(
                    db: db,
                    record: record,
                    failure: failure,
                    now: now.databaseMilliseconds
                )
            }
            await emit(kind: .failed, jobID: record.id)
            try await runPendingFailureHooks(limit: 1)
            return
        }

        guard let delay = record.retryPolicy.delay(
            afterAttempt: record.attempt,
            randomUnit: configuration.randomUnit()
        ) else {
            try await handleFailure(failure, for: record, forcePermanent: true)
            return
        }
        try await release(
            record,
            delay: delay,
            consumesAttempt: true,
            failure: failure
        )
    }

    func release(
        _ record: JobRecord,
        delay: TimeInterval,
        consumesAttempt: Bool,
        failure: JobFailure? = nil
    ) async throws {
        let now = configuration.now()
        let availableAt = now.addingTimeInterval(max(0, delay)).databaseMilliseconds
        let nowValue = now.databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'queued', available_at = ?, lease_token = NULL,
                        lease_expires_at = NULL, updated_at = ?,
                        attempt_count = MAX(0, attempt_count - ?),
                        last_failure_kind = COALESCE(?, last_failure_kind),
                        last_failure_message = COALESCE(?, last_failure_message),
                        last_failure_at = COALESCE(?, last_failure_at)
                    WHERE id = ? AND state = 'running' AND lease_token = ?
                    """,
                arguments: [
                    availableAt,
                    nowValue,
                    consumesAttempt ? 0 : 1,
                    failure?.kind.rawValue,
                    failure?.message,
                    failure.map { $0.occurredAt.databaseMilliseconds },
                    record.id.description,
                    record.leaseToken,
                ]
            )
            guard db.changesCount == 1 else {
                throw DurableQueueError.leaseLost(record.id)
            }
            try Self.finishAttempt(
                db: db,
                record: record,
                outcome: "released",
                message: failure?.message,
                now: nowValue
            )
        }
        await emit(kind: .retryScheduled, jobID: record.id)
    }

    func heartbeat(id: JobID, leaseToken: String) async throws {
        let now = configuration.now()
        let leaseExpiry = now.addingTimeInterval(configuration.leaseDuration)
            .databaseMilliseconds
        let cancellationRequested = try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET lease_expires_at = ?, updated_at = ?
                    WHERE id = ? AND state = 'running' AND lease_token = ?
                    """,
                arguments: [
                    leaseExpiry,
                    now.databaseMilliseconds,
                    id.description,
                    leaseToken,
                ]
            )
            guard db.changesCount == 1 else {
                throw DurableQueueError.leaseLost(id)
            }
            let cancellationRequested = try Bool.fetchOne(
                db,
                sql: "SELECT cancel_requested FROM durable_queue_jobs WHERE id = ?",
                arguments: [id.description]
            ) ?? true
            try db.execute(
                sql: """
                    UPDATE durable_queue_locks
                    SET expires_at = ? + duration_milliseconds, updated_at = ?
                    WHERE owner_token = ?
                    """,
                arguments: [now.databaseMilliseconds, now.databaseMilliseconds, leaseToken]
            )
            return cancellationRequested
        }
        if cancellationRequested {
            throw DurableCancellationRequested()
        }
    }

    func reportProgress(id: JobID, leaseToken: String, fraction: Double) async throws {
        let now = configuration.now()
        if fraction < 1,
           let previous = lastProgressWrites[id],
           now.timeIntervalSince(previous) < configuration.progressWriteInterval {
            return
        }
        try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET progress = MAX(progress, ?), updated_at = ?
                    WHERE id = ? AND state = 'running' AND lease_token = ?
                    """,
                arguments: [
                    fraction,
                    now.databaseMilliseconds,
                    id.description,
                    leaseToken,
                ]
            )
            guard db.changesCount == 1 else {
                throw DurableQueueError.leaseLost(id)
            }
        }
        lastProgressWrites[id] = now
        await emit(kind: .progress, jobID: id)
    }

    func cancellationRequested(id: JobID) async -> Bool {
        (try? await durableCancellationRequested(id: id)) ?? true
    }

    func durableCancellationRequested(id: JobID) async throws -> Bool {
        if Task.isCancelled { return true }
        return try await database.value.read { db in
            try Bool.fetchOne(
                db,
                sql: "SELECT cancel_requested FROM durable_queue_jobs WHERE id = ?",
                arguments: [id.description]
            ) ?? true
        }
    }

    func acquireLock(
        key: String,
        ownerToken: String,
        expiresAfter: TimeInterval
    ) async throws -> Bool {
        guard expiresAfter.isFinite, expiresAfter > 0 else {
            throw DurableQueueError.invalidConfiguration("lock duration must be finite and positive")
        }
        let now = configuration.now()
        let nowValue = now.databaseMilliseconds
        let effectiveDuration = max(expiresAfter, configuration.leaseDuration)
        let durationMilliseconds = Int64(effectiveDuration * 1_000)
        let expiry = now.databaseMilliseconds + durationMilliseconds
        return try await database.value.write { db in
            try db.execute(
                sql: "DELETE FROM durable_queue_locks WHERE lock_key = ? AND expires_at <= ?",
                arguments: [key, nowValue]
            )
            try db.execute(
                sql: """
                    INSERT OR IGNORE INTO durable_queue_locks
                    (lock_key, owner_token, expires_at, duration_milliseconds, updated_at)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [key, ownerToken, expiry, durationMilliseconds, nowValue]
            )
            return db.changesCount == 1
        }
    }

    func releaseLock(key: String, ownerToken: String) async {
        try? await database.value.write { db in
            try db.execute(
                sql: "DELETE FROM durable_queue_locks WHERE lock_key = ? AND owner_token = ?",
                arguments: [key, ownerToken]
            )
        }
    }

    func releaseForBackgroundExpiration(_ record: JobRecord) async throws {
        let now = configuration.now()
        let availableAt = now.addingTimeInterval(configuration.interruptionRetryDelay)
        try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'queued', available_at = ?, lease_token = NULL,
                        lease_expires_at = NULL, stop_reason = ?, updated_at = ?,
                        last_failure_kind = ?, last_failure_message = ?, last_failure_at = ?
                    WHERE id = ? AND state = 'running' AND lease_token = ?
                    """,
                arguments: [
                    availableAt.databaseMilliseconds,
                    JobStopReason.backgroundTaskExpired.rawValue,
                    now.databaseMilliseconds,
                    JobFailureKind.leaseExpired.rawValue,
                    "The BackgroundTasks execution window expired.",
                    now.databaseMilliseconds,
                    record.id.description,
                    record.leaseToken,
                ]
            )
            guard db.changesCount == 1 else {
                throw DurableQueueError.leaseLost(record.id)
            }
            try Self.finishAttempt(
                db: db,
                record: record,
                outcome: "backgroundTaskExpired",
                message: nil,
                now: now.databaseMilliseconds
            )
        }
        await emit(kind: .retryScheduled, jobID: record.id)
    }

    func expectedCancellationAfterLeaseLoss(id: JobID) async throws -> Bool {
        try await database.value.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT state, stop_reason FROM durable_queue_jobs WHERE id = ?",
                arguments: [id.description]
            ) else {
                return false
            }
            let state: String = row["state"]
            let reason: String? = row["stop_reason"]
            return state == JobState.cancelled.rawValue
                && (reason == JobStopReason.replaced.rawValue
                    || reason == JobStopReason.userCancelled.rawValue)
        }
    }

    nonisolated static func finishAttempt(
        db: Database,
        record: JobRecord,
        outcome: String,
        message: String?,
        now: Int64
    ) throws {
        try db.execute(
            sql: """
                UPDATE durable_queue_attempts
                SET finished_at = ?, outcome = ?, message = ?
                WHERE id = (
                    SELECT id FROM durable_queue_attempts
                    WHERE job_id = ? AND attempt = ? AND finished_at IS NULL
                    ORDER BY id DESC LIMIT 1
                )
                """,
            arguments: [now, outcome, message, record.id.description, record.attempt]
        )
    }
}
