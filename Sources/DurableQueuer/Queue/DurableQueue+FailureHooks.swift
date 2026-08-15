import Foundation
import GRDB

extension DurableQueue {
    func runPendingFailureHooks(limit: Int) async throws {
        for _ in 0 ..< max(1, limit) {
            guard let claim = try await claimFailureHook() else { return }
            let record = claim.record

            guard let failure = record.lastFailure,
                  let registration = registry.job(for: record.typeIdentifier),
                  let failureHandler = registration.failureHandler else {
                try await completeFailureHook(claim)
                continue
            }

            do {
                let payload = try configuration.payloadProtection?.unprotect(record.payload)
                    ?? record.payload
                try await failureHandler(
                    payload,
                    record.payloadVersion,
                    failure,
                    makeFailureContext(for: record)
                )
                try await completeFailureHook(claim)
            } catch {
                try await releaseFailureHook(claim)
            }
        }
    }

    func claimFailureHook() async throws -> FailureHookClaim? {
        let now = configuration.now()
        let nowValue = now.databaseMilliseconds
        let token = UUID().uuidString
        let expiresAt = now.addingTimeInterval(configuration.failureHookLeaseDuration)
            .databaseMilliseconds

        return try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET failure_hook_token = NULL, failure_hook_expires_at = NULL,
                        failure_hook_available_at = MIN(failure_hook_available_at, ?)
                    WHERE state = 'failed' AND failure_hook_pending = 1
                      AND failure_hook_token IS NOT NULL
                      AND failure_hook_expires_at <= ?
                    """,
                arguments: [nowValue, nowValue]
            )

            guard let id = try String.fetchOne(
                db,
                sql: """
                    SELECT id FROM durable_queue_jobs
                    WHERE state = 'failed' AND failure_hook_pending = 1
                      AND failure_hook_token IS NULL
                      AND failure_hook_available_at <= ?
                    ORDER BY finished_at, id
                    LIMIT 1
                    """,
                arguments: [nowValue]
            ) else {
                return nil
            }

            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET failure_hook_token = ?, failure_hook_expires_at = ?,
                        failure_hook_attempt_count = failure_hook_attempt_count + 1
                    WHERE id = ? AND state = 'failed' AND failure_hook_pending = 1
                      AND failure_hook_token IS NULL
                      AND failure_hook_available_at <= ?
                    """,
                arguments: [token, expiresAt, id, nowValue]
            )
            guard db.changesCount == 1,
                  let row = try Row.fetchOne(
                    db,
                    sql: "SELECT * FROM durable_queue_jobs WHERE id = ?",
                    arguments: [id]
                  ) else {
                return nil
            }
            return FailureHookClaim(record: try JobRecord(row: row), token: token)
        }
    }

    func completeFailureHook(_ claim: FailureHookClaim) async throws {
        try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET failure_hook_pending = 0, failure_hook_token = NULL,
                        failure_hook_expires_at = NULL
                    WHERE id = ? AND state = 'failed'
                      AND failure_hook_token = ?
                    """,
                arguments: [claim.record.id.description, claim.token]
            )
            guard db.changesCount == 1 else {
                throw DurableQueueError.failureHookLeaseLost(claim.record.id)
            }
        }
    }

    func releaseFailureHook(_ claim: FailureHookClaim) async throws {
        if claim.record.failureHookAttempt >= configuration.maximumFailureHookAttempts {
            try await completeFailureHook(claim)
            return
        }
        let delay = configuration.failureHookRetryPolicy.delay(
            afterAttempt: claim.record.failureHookAttempt,
            randomUnit: configuration.randomUnit()
        )
        let now = configuration.now()
        let availableAt = delay.map { now.addingTimeInterval($0).databaseMilliseconds }

        try await database.value.write { db in
            if let availableAt {
                try db.execute(
                    sql: """
                        UPDATE durable_queue_jobs
                        SET failure_hook_token = NULL, failure_hook_expires_at = NULL,
                            failure_hook_available_at = ?
                        WHERE id = ? AND state = 'failed'
                          AND failure_hook_token = ?
                        """,
                    arguments: [availableAt, claim.record.id.description, claim.token]
                )
            } else {
                try db.execute(
                    sql: """
                        UPDATE durable_queue_jobs
                        SET failure_hook_pending = 0, failure_hook_token = NULL,
                            failure_hook_expires_at = NULL
                        WHERE id = ? AND state = 'failed'
                          AND failure_hook_token = ?
                        """,
                    arguments: [claim.record.id.description, claim.token]
                )
            }
            guard db.changesCount == 1 else {
                throw DurableQueueError.failureHookLeaseLost(claim.record.id)
            }
        }
    }

    func makeFailureContext(for record: JobRecord) -> JobContext {
        JobContext(
            id: record.id,
            attempt: record.attempt,
            maxAttempts: record.maxAttempts,
            queuedAt: record.createdAt,
            idempotencyKey: record.idempotencyKey,
            heartbeatAction: { throw DurableQueueError.leaseLost(record.id) },
            progressAction: { _ in throw DurableQueueError.leaseLost(record.id) },
            cancellationAction: { true },
            acquireLockAction: { _, _ in false },
            releaseLockAction: { _ in },
            rateLimitAction: { _, _, _ in nil },
            exceptionThrottleAction: { _, _, _, _ in nil }
        )
    }
}
