import GRDB

extension DurableQueue {
    nonisolated static func resolveDependents(
        of rootID: String,
        in db: Database,
        now: Int64
    ) throws {
        var completedPrerequisites = [rootID]
        while let prerequisiteID = completedPrerequisites.first {
            completedPrerequisites.removeFirst()
            let dependentIDs = try String.fetchAll(
                db,
                sql: """
                    SELECT job_id FROM durable_queue_dependencies
                    WHERE prerequisite_id = ?
                    """,
                arguments: [prerequisiteID]
            )
            for dependentID in dependentIDs {
                guard let state = try String.fetchOne(
                    db,
                    sql: "SELECT state FROM durable_queue_jobs WHERE id = ?",
                    arguments: [dependentID]
                ), state == JobState.blocked.rawValue else { continue }

                let rows = try Row.fetchAll(
                    db,
                    sql: """
                        SELECT p.state, d.behavior
                        FROM durable_queue_dependencies d
                        JOIN durable_queue_jobs p ON p.id = d.prerequisite_id
                        WHERE d.job_id = ?
                        """,
                    arguments: [dependentID]
                )
                let hasActive = rows.contains { row in
                    let state: String = row["state"]
                    return state == JobState.blocked.rawValue
                        || state == JobState.queued.rawValue
                        || state == JobState.running.rawValue
                }
                guard !hasActive else { continue }

                let blockingState: String? = rows.first { row in
                    let state: String = row["state"]
                    let behavior: String = row["behavior"]
                    return state != JobState.succeeded.rawValue
                        && behavior == ChainDependencyBehavior.onSuccess.rawValue
                }.map { $0["state"] }

                if let blockingState {
                    let reason: JobStopReason = blockingState == JobState.failed.rawValue
                        ? .dependencyFailed
                        : .dependencyCancelled
                    try db.execute(
                        sql: """
                            UPDATE durable_queue_jobs
                            SET state = 'cancelled', cancel_requested = 1,
                                stop_reason = ?, finished_at = ?, updated_at = ?
                            WHERE id = ? AND state = 'blocked'
                            """,
                        arguments: [reason.rawValue, now, now, dependentID]
                    )
                    if db.changesCount == 1 { completedPrerequisites.append(dependentID) }
                } else {
                    try db.execute(
                        sql: """
                            UPDATE durable_queue_jobs
                            SET state = 'queued', updated_at = ?
                            WHERE id = ? AND state = 'blocked'
                            """,
                        arguments: [now, dependentID]
                    )
                }
            }
        }
    }
}
