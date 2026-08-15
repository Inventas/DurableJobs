import Foundation
import GRDB

extension DurableQueue {
    func consumeRateLimit(
        key: String,
        maximum: Int,
        window: TimeInterval
    ) async throws -> TimeInterval? {
        let now = configuration.now()
        let nowValue = now.databaseMilliseconds
        let windowMilliseconds = Int64(window * 1_000)
        return try await database.value.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT window_started_at, hit_count FROM durable_queue_rate_limits WHERE rate_key = ?",
                arguments: [key]
            ) else {
                try db.execute(
                    sql: """
                        INSERT INTO durable_queue_rate_limits
                        (rate_key, window_started_at, hit_count, updated_at) VALUES (?, ?, 1, ?)
                        """,
                    arguments: [key, nowValue, nowValue]
                )
                return nil
            }
            let startedAt: Int64 = row["window_started_at"]
            let hits: Int = row["hit_count"]
            if nowValue - startedAt >= windowMilliseconds {
                try db.execute(
                    sql: """
                        UPDATE durable_queue_rate_limits
                        SET window_started_at = ?, hit_count = 1, updated_at = ? WHERE rate_key = ?
                        """,
                    arguments: [nowValue, nowValue, key]
                )
                return nil
            }
            guard hits < maximum else {
                return max(0, Double(startedAt + windowMilliseconds - nowValue) / 1_000)
            }
            try db.execute(
                sql: """
                    UPDATE durable_queue_rate_limits
                    SET hit_count = hit_count + 1, updated_at = ? WHERE rate_key = ?
                    """,
                arguments: [nowValue, key]
            )
            return nil
        }
    }

    func recordThrottledException(
        key: String,
        maximum: Int,
        decay: TimeInterval,
        retryAfter: TimeInterval
    ) async throws -> TimeInterval? {
        let now = configuration.now().databaseMilliseconds
        let decayMilliseconds = Int64(decay * 1_000)
        return try await database.value.write { db in
            let row = try Row.fetchOne(
                db,
                sql: "SELECT exception_count, last_exception_at FROM durable_queue_exception_throttles WHERE throttle_key = ?",
                arguments: [key]
            )
            let previousCount: Int = row?["exception_count"] ?? 0
            let lastException: Int64 = row?["last_exception_at"] ?? 0
            let count = now - lastException >= decayMilliseconds ? 1 : previousCount + 1
            try db.execute(
                sql: """
                    INSERT INTO durable_queue_exception_throttles
                    (throttle_key, exception_count, last_exception_at, updated_at)
                    VALUES (?, ?, ?, ?)
                    ON CONFLICT(throttle_key) DO UPDATE SET
                        exception_count = excluded.exception_count,
                        last_exception_at = excluded.last_exception_at,
                        updated_at = excluded.updated_at
                    """,
                arguments: [key, count, now, now]
            )
            return count >= maximum ? retryAfter : nil
        }
    }
}
