import Foundation
import GRDB

extension DurableQueue {
    public func dispatchBatch(
        _ requests: [JobRequest],
        completion: JobRequest? = nil
    ) async throws -> BatchReceipt {
        guard !requests.isEmpty else {
            throw DurableQueueError.invalidDispatchOptions("a batch must contain at least one job")
        }
        let now = configuration.now()
        let preparedJobs = try requests.map { try prepareDispatch($0, now: now) }
        let preparedCompletion = try completion.map { try prepareDispatch($0, now: now) }
        let batchID = JobBatchID()
        let result = try await database.value.write { db -> ([DispatchReceipt], DispatchReceipt?) in
            var receipts: [DispatchReceipt] = []
            for dispatch in preparedJobs {
                let receipt = try dispatch.insert(in: db)
                guard receipt.result != .existing else {
                    throw DurableQueueError.invalidDispatchOptions(
                        "batch jobs must insert new jobs; active unique work already exists"
                    )
                }
                try db.execute(
                    sql: "UPDATE durable_queue_jobs SET batch_id = ? WHERE id = ?",
                    arguments: [batchID.rawValue.uuidString, receipt.id.description]
                )
                receipts.append(receipt)
            }

            var completionReceipt: DispatchReceipt?
            if let preparedCompletion {
                let receipt = try preparedCompletion.insert(in: db)
                guard receipt.result != .existing else {
                    throw DurableQueueError.invalidDispatchOptions(
                        "the batch completion job must be a new job"
                    )
                }
                try db.execute(
                    sql: """
                        UPDATE durable_queue_jobs
                        SET batch_id = ?, state = 'blocked' WHERE id = ?
                        """,
                    arguments: [batchID.rawValue.uuidString, receipt.id.description]
                )
                for jobReceipt in receipts {
                    try db.execute(
                        sql: """
                            INSERT INTO durable_queue_dependencies
                            (job_id, prerequisite_id, behavior)
                            VALUES (?, ?, 'runRegardless')
                            """,
                        arguments: [receipt.id.description, jobReceipt.id.description]
                    )
                }
                completionReceipt = receipt
            }
            try db.execute(
                sql: """
                    INSERT INTO durable_queue_batches
                    (id, completion_job_id, created_at, updated_at) VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    batchID.rawValue.uuidString,
                    completionReceipt?.id.description,
                    now.databaseMilliseconds,
                    now.databaseMilliseconds,
                ]
            )
            return (receipts, completionReceipt)
        }
        for receipt in result.0 { await emit(kind: .dispatched, jobID: receipt.id) }
        if let completion = result.1 { await emit(kind: .dispatched, jobID: completion.id) }
        return BatchReceipt(id: batchID, jobs: result.0, completionJob: result.1)
    }

    public func batch(_ id: JobBatchID) async throws -> BatchSnapshot? {
        try await database.value.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT completion_job_id FROM durable_queue_batches WHERE id = ?",
                arguments: [id.rawValue.uuidString]
            ) else { return nil }
            let stateRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT state, COUNT(*) AS count
                    FROM durable_queue_jobs
                    WHERE batch_id = ? AND id IS NOT ?
                    GROUP BY state
                    """,
                arguments: [id.rawValue.uuidString, row["completion_job_id"] as String?]
            )
            var counts: [JobState: Int] = [:]
            for stateRow in stateRows {
                if let state = JobState(rawValue: stateRow["state"]) {
                    counts[state] = stateRow["count"]
                }
            }
            let progress = try Double.fetchOne(
                db,
                sql: """
                    SELECT AVG(CASE WHEN state IN ('succeeded', 'failed', 'cancelled')
                                    THEN 1.0 ELSE progress END)
                    FROM durable_queue_jobs
                    WHERE batch_id = ? AND id IS NOT ?
                    """,
                arguments: [id.rawValue.uuidString, row["completion_job_id"] as String?]
            ) ?? 0
            let completionRaw: String? = row["completion_job_id"]
            return BatchSnapshot(
                id: id,
                stateCounts: JobStateCounts(
                    blocked: counts[.blocked, default: 0],
                    queued: counts[.queued, default: 0],
                    running: counts[.running, default: 0],
                    succeeded: counts[.succeeded, default: 0],
                    failed: counts[.failed, default: 0],
                    cancelled: counts[.cancelled, default: 0]
                ),
                progress: progress,
                completionJobID: completionRaw.flatMap(UUID.init(uuidString:)).map(JobID.init)
            )
        }
    }

    @discardableResult
    public func cancelBatch(_ id: JobBatchID) async throws -> Int {
        let now = configuration.now().databaseMilliseconds
        let rawIDs = try await database.value.write { db -> [String] in
            let ids = try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM durable_queue_jobs
                    WHERE batch_id = ? AND state IN ('blocked', 'queued', 'running')
                    """,
                arguments: [id.rawValue.uuidString]
            )
            for jobID in ids {
                try db.execute(
                    sql: """
                        UPDATE durable_queue_jobs
                        SET state = CASE WHEN state = 'running' THEN state ELSE 'cancelled' END,
                            cancel_requested = 1, stop_reason = ?, updated_at = ?,
                            finished_at = CASE WHEN state = 'running' THEN finished_at ELSE ? END
                        WHERE id = ?
                        """,
                    arguments: [JobStopReason.batchCancelled.rawValue, now, now, jobID]
                )
                if let state = try String.fetchOne(
                    db,
                    sql: "SELECT state FROM durable_queue_jobs WHERE id = ?",
                    arguments: [jobID]
                ), state == JobState.cancelled.rawValue {
                    try Self.resolveDependents(of: jobID, in: db, now: now)
                }
            }
            return ids
        }
        for rawID in rawIDs {
            guard let uuid = UUID(uuidString: rawID) else { continue }
            let jobID = JobID(uuid)
            activeStopReasons[jobID] = .batchCancelled
            activeOperations[jobID]?.cancel()
            await emit(kind: .cancelled, jobID: jobID)
        }
        return rawIDs.count
    }
}
