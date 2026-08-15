import Foundation
import GRDB

extension DurableQueue {
    /// Updates queued or blocked work without changing its ID or enqueue time.
    @discardableResult
    public func update<J: DurableJob>(
        _ id: JobID,
        with job: J,
        options: DispatchOptions = .defaults
    ) async throws -> JobSnapshot {
        let request = try JobRequest(job, options: options)
        let prepared = try prepareDispatch(request, now: configuration.now())
        let retryData = try JobPayloadCodec.encoder().encode(prepared.options.retryPolicy)
        try await database.value.write { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT state, idempotency_key FROM durable_queue_jobs WHERE id = ?",
                arguments: [id.description]
            ), let state = JobState(rawValue: row["state"]) else {
                throw DurableQueueError.jobNotFound(id)
            }
            guard state == .queued || state == .blocked else {
                throw DurableQueueError.invalidJobState(id, expected: .queued, actual: state)
            }
            let existingIdempotencyKey: String = row["idempotency_key"]
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET type_identifier = ?, payload = ?, payload_version = ?,
                        queue_name = ?, lane = ?, priority = ?, available_at = ?,
                        deadline_at = ?, timeout_seconds = ?, max_attempts = ?,
                        retry_policy = ?, requires_network = ?, requires_power = ?,
                        unique_key = ?, idempotency_key = ?, updated_at = ?
                    WHERE id = ? AND state IN ('blocked', 'queued')
                    """,
                arguments: [
                    prepared.typeIdentifier,
                    prepared.payload,
                    prepared.payloadVersion,
                    prepared.options.queue,
                    prepared.options.lane.rawValue,
                    prepared.options.priority,
                    prepared.options.availableAt.databaseMilliseconds,
                    prepared.options.deadline?.databaseMilliseconds,
                    prepared.options.timeout,
                    prepared.options.maxAttempts,
                    retryData,
                    prepared.options.requirements.contains(.networkConnectivity) ? 1 : 0,
                    prepared.options.requirements.contains(.externalPower) ? 1 : 0,
                    prepared.options.uniqueKey,
                    options.idempotencyKey == nil
                        ? existingIdempotencyKey
                        : prepared.options.idempotencyKey,
                    configuration.now().databaseMilliseconds,
                    id.description,
                ]
            )
            try db.execute(
                sql: "DELETE FROM durable_queue_job_tags WHERE job_id = ?",
                arguments: [id.description]
            )
            for tag in prepared.options.tags {
                try db.execute(
                    sql: "INSERT INTO durable_queue_job_tags (job_id, tag) VALUES (?, ?)",
                    arguments: [id.description, tag]
                )
            }
        }
        await emit(kind: .updated, jobID: id)
        guard let snapshot = try await status(id) else {
            throw DurableQueueError.jobNotFound(id)
        }
        return snapshot
    }

    public func attempts(for id: JobID) async throws -> [JobAttempt] {
        try await database.value.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT attempt, started_at, finished_at, outcome, message
                    FROM durable_queue_attempts WHERE job_id = ? ORDER BY id
                    """,
                arguments: [id.description]
            )
            return rows.map { row in
                JobAttempt(
                    number: row["attempt"],
                    startedAt: Date(databaseMilliseconds: row["started_at"]),
                    finishedAt: (row["finished_at"] as Int64?).map(Date.init(databaseMilliseconds:)),
                    outcome: row["outcome"],
                    message: row["message"]
                )
            }
        }
    }
}
