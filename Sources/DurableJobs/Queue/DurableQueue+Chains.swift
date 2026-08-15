import Foundation
import GRDB

extension DurableQueue {
    public func dispatchChain(_ steps: [ChainStep]) async throws -> ChainReceipt {
        guard !steps.isEmpty else {
            throw DurableQueueError.invalidDispatchOptions("a chain must contain at least one job")
        }
        let now = configuration.now()
        let prepared = try steps.map { try prepareDispatch($0.request, now: now) }
        let chainID = JobChainID()
        let receipts = try await database.value.write { db -> [DispatchReceipt] in
            var receipts: [DispatchReceipt] = []
            for (index, dispatch) in prepared.enumerated() {
                let receipt = try dispatch.insert(in: db)
                guard receipt.result != .existing else {
                    throw DurableQueueError.invalidDispatchOptions(
                        "chain steps must insert new jobs; active unique work already exists"
                    )
                }
                try db.execute(
                    sql: """
                        UPDATE durable_queue_jobs
                        SET chain_id = ?, state = ? WHERE id = ?
                        """,
                    arguments: [
                        chainID.rawValue.uuidString,
                        index == 0 ? JobState.queued.rawValue : JobState.blocked.rawValue,
                        receipt.id.description,
                    ]
                )
                if index > 0 {
                    try db.execute(
                        sql: """
                            INSERT INTO durable_queue_dependencies
                            (job_id, prerequisite_id, behavior) VALUES (?, ?, ?)
                            """,
                        arguments: [
                            receipt.id.description,
                            receipts[index - 1].id.description,
                            steps[index].behavior.rawValue,
                        ]
                    )
                }
                receipts.append(receipt)
            }
            return receipts
        }
        for receipt in receipts { await emit(kind: .dispatched, jobID: receipt.id) }
        return ChainReceipt(id: chainID, jobs: receipts)
    }
}
