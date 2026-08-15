import Foundation
import GRDB

extension DurableQueue {
    public func metrics(
        since startDate: Date,
        bucketDuration: TimeInterval
    ) async throws -> QueueMetricsSnapshot {
        guard startDate.timeIntervalSinceReferenceDate.isFinite,
              bucketDuration.isFinite,
              bucketDuration > 0 else {
            throw DurableQueueError.invalidDispatchOptions(
                "metric dates and bucket duration must be finite and the duration must be positive"
            )
        }
        let capturedAt = configuration.now()
        let capturedAtValue = capturedAt.databaseMilliseconds
        let requestedStartValue = min(
            startDate.databaseMilliseconds,
            capturedAtValue
        )
        let bucketMilliseconds = Int64(max(1, bucketDuration) * 1_000)
        let maximumBucketCount = 1_000
        let earliestSupportedValue = capturedAtValue
            - bucketMilliseconds * Int64(maximumBucketCount)
        let activitySinceValue = max(requestedStartValue, earliestSupportedValue)
        let elapsed = max(0, capturedAtValue - activitySinceValue)
        let bucketCount = max(
            1,
            min(
                maximumBucketCount,
                Int((elapsed + bucketMilliseconds - 1) / bucketMilliseconds)
            )
        )

        return try await database.value.read { db in
            let stateRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT state, COUNT(*) AS job_count
                    FROM durable_queue_jobs
                    GROUP BY state
                    """
            )
            var countsByState: [JobState: Int] = [:]
            for row in stateRows {
                guard let state = JobState(rawValue: row["state"]) else { continue }
                countsByState[state] = row["job_count"]
            }
            let stateCounts = JobStateCounts(
                blocked: countsByState[.blocked, default: 0],
                queued: countsByState[.queued, default: 0],
                running: countsByState[.running, default: 0],
                succeeded: countsByState[.succeeded, default: 0],
                failed: countsByState[.failed, default: 0],
                cancelled: countsByState[.cancelled, default: 0]
            )

            let queueRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT q.queue_name,
                           COALESCE(c.is_paused, 0) AS is_paused,
                           SUM(CASE WHEN j.state = 'blocked' THEN 1 ELSE 0 END) AS blocked_count,
                           SUM(CASE WHEN j.state = 'queued' THEN 1 ELSE 0 END) AS queued_count,
                           SUM(CASE WHEN j.state = 'running' THEN 1 ELSE 0 END) AS running_count,
                           SUM(CASE WHEN j.state = 'succeeded' THEN 1 ELSE 0 END) AS succeeded_count,
                           SUM(CASE WHEN j.state = 'failed' THEN 1 ELSE 0 END) AS failed_count,
                           SUM(CASE WHEN j.state = 'cancelled' THEN 1 ELSE 0 END) AS cancelled_count
                    FROM (
                        SELECT queue_name FROM durable_queue_jobs
                        UNION
                        SELECT queue_name FROM durable_queue_controls
                    ) q
                    LEFT JOIN durable_queue_jobs j ON j.queue_name = q.queue_name
                    LEFT JOIN durable_queue_controls c ON c.queue_name = q.queue_name
                    GROUP BY q.queue_name, c.is_paused
                    ORDER BY q.queue_name COLLATE NOCASE, q.queue_name
                    """
            )
            let queues = queueRows.map { row in
                QueueMetrics(
                    queue: row["queue_name"],
                    isPaused: (row["is_paused"] as Int) != 0,
                    stateCounts: JobStateCounts(
                        blocked: row["blocked_count"],
                        queued: row["queued_count"],
                        running: row["running_count"],
                        succeeded: row["succeeded_count"],
                        failed: row["failed_count"],
                        cancelled: row["cancelled_count"]
                    )
                )
            }

            let activityRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT MIN(?, CAST((finished_at - ?) / ? AS INTEGER)) AS bucket_index,
                           state,
                           COUNT(*) AS job_count
                    FROM durable_queue_jobs
                    WHERE state IN ('succeeded', 'failed')
                      AND finished_at >= ?
                      AND finished_at <= ?
                    GROUP BY bucket_index, state
                    ORDER BY bucket_index, state
                    """,
                arguments: [
                    bucketCount - 1,
                    activitySinceValue,
                    bucketMilliseconds,
                    activitySinceValue,
                    capturedAtValue,
                ]
            )
            var activityCounts: [Int: [JobState: Int]] = [:]
            for row in activityRows {
                let bucketIndex: Int = row["bucket_index"]
                guard let state = JobState(rawValue: row["state"]) else { continue }
                activityCounts[bucketIndex, default: [:]][state] = row["job_count"]
            }
            let activity = (0 ..< bucketCount).map { index in
                let startValue = activitySinceValue
                    + Int64(index) * bucketMilliseconds
                let endValue = min(
                    capturedAtValue,
                    startValue + bucketMilliseconds
                )
                return QueueActivityBucket(
                    start: Date(databaseMilliseconds: startValue),
                    end: Date(databaseMilliseconds: endValue),
                    succeeded: activityCounts[index]?[.succeeded] ?? 0,
                    failed: activityCounts[index]?[.failed] ?? 0
                )
            }

            return QueueMetricsSnapshot(
                capturedAt: capturedAt,
                activitySince: Date(databaseMilliseconds: activitySinceValue),
                bucketDuration: Double(bucketMilliseconds) / 1_000,
                stateCounts: stateCounts,
                queues: queues,
                activity: activity
            )
        }
    }

    public func encodedPayload(for id: JobID) async throws -> EncodedJobPayload? {
        try await database.value.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT type_identifier, payload_version, payload
                    FROM durable_queue_jobs
                    WHERE id = ?
                    """,
                arguments: [id.description]
            ) else {
                return nil
            }

            return EncodedJobPayload(
                typeIdentifier: row["type_identifier"],
                version: row["payload_version"],
                data: row["payload"]
            )
        }
    }

    public func health() async throws -> QueueHealth {
        let capturedAt = configuration.now()
        let metrics = try await metrics(since: capturedAt, bucketDuration: 60)
        return try await database.value.read { db in
            let oldest = try Int64.fetchOne(
                db,
                sql: """
                    SELECT MIN(available_at) FROM durable_queue_jobs
                    WHERE state = 'queued' AND available_at <= ?
                    """,
                arguments: [capturedAt.databaseMilliseconds]
            ).map(Date.init(databaseMilliseconds:))
            let leases = try Int.fetchOne(
                db,
                sql: """
                    SELECT COUNT(*) FROM durable_queue_jobs
                    WHERE state = 'running' AND lease_expires_at > ?
                    """,
                arguments: [capturedAt.databaseMilliseconds]
            ) ?? 0
            let hooks = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM durable_queue_jobs WHERE failure_hook_pending = 1"
            ) ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT lane, MIN(available_at) AS next_at
                    FROM durable_queue_jobs WHERE state = 'queued'
                    GROUP BY lane
                    """
            )
            var nextDates: [JobExecutionLane: Date] = [:]
            for row in rows {
                guard let lane = JobExecutionLane(rawValue: row["lane"]) else { continue }
                nextDates[lane] = Date(databaseMilliseconds: row["next_at"])
            }
            return QueueHealth(
                capturedAt: capturedAt,
                stateCounts: metrics.stateCounts,
                queues: metrics.queues,
                oldestEligibleJobAt: oldest,
                activeLeaseCount: leases,
                pendingFailureHookCount: hooks,
                nextEligibleDates: nextDates
            )
        }
    }
}
