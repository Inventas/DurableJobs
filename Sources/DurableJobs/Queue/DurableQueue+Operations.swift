import Foundation
import GRDB

extension DurableQueue {
    public func jobs(matching query: JobQuery = JobQuery()) async throws -> [JobInfo] {
        try Self.validate(query)
        return try await database.value.read { db in
            try Self.fetchJobs(matching: query, in: db)
        }
    }

    public func retry(_ id: JobID, availableAt: Date? = nil) async throws {
        let now = configuration.now()
        guard availableAt?.timeIntervalSinceReferenceDate.isFinite ?? true else {
            throw DurableQueueError.invalidDispatchOptions("availableAt must be finite")
        }
        try await database.value.write { db in
            guard let rawState = try String.fetchOne(
                db,
                sql: "SELECT state FROM durable_queue_jobs WHERE id = ?",
                arguments: [id.description]
            ), let state = JobState(rawValue: rawState) else {
                throw DurableQueueError.jobNotFound(id)
            }
            guard state == .failed else {
                throw DurableQueueError.invalidJobState(id, expected: .failed, actual: state)
            }
            try Self.retry(ids: [id.description], availableAt: availableAt ?? now, now: now, in: db)
        }
        await emit(kind: .retried, jobID: id)
    }

    @discardableResult
    public func retry(matching query: JobQuery, availableAt: Date? = nil) async throws -> Int {
        try Self.validate(query)
        let now = configuration.now()
        guard availableAt?.timeIntervalSinceReferenceDate.isFinite ?? true else {
            throw DurableQueueError.invalidDispatchOptions("availableAt must be finite")
        }
        let ids = try await database.value.write { db in
            let ids = try Self.matchingJobIDs(query, states: [.failed], in: db)
            try Self.retry(ids: ids, availableAt: availableAt ?? now, now: now, in: db)
            return ids
        }
        for rawID in ids {
            if let uuid = UUID(uuidString: rawID) { await emit(kind: .retried, jobID: JobID(uuid)) }
        }
        return ids.count
    }

    @discardableResult
    public func cancel(matching query: JobQuery) async throws -> Int {
        try Self.validate(query)
        let now = configuration.now().databaseMilliseconds
        let rawIDs = try await database.value.write { db in
            let ids = try Self.matchingJobIDs(query, states: [.blocked, .queued, .running], in: db)
            for id in ids {
                try db.execute(
                    sql: """
                        UPDATE durable_queue_jobs
                        SET state = CASE WHEN state = 'running' THEN state ELSE 'cancelled' END,
                            cancel_requested = 1, stop_reason = ?, updated_at = ?,
                            finished_at = CASE WHEN state = 'running' THEN finished_at ELSE ? END
                        WHERE id = ? AND state IN ('blocked', 'queued', 'running')
                        """,
                    arguments: [JobStopReason.userCancelled.rawValue, now, now, id]
                )
                if let state = try String.fetchOne(
                    db,
                    sql: "SELECT state FROM durable_queue_jobs WHERE id = ?",
                    arguments: [id]
                ), state == JobState.cancelled.rawValue {
                    try Self.resolveDependents(of: id, in: db, now: now)
                }
            }
            return ids
        }
        for rawID in rawIDs {
            guard let uuid = UUID(uuidString: rawID) else { continue }
            let id = JobID(uuid)
            activeStopReasons[id] = .userCancelled
            if let operation = activeOperations[id] {
                operation.cancel()
            } else {
                await emit(kind: .cancelled, jobID: id)
            }
        }
        return rawIDs.count
    }

    @discardableResult
    public func cancel(tag: String) async throws -> Int {
        try await cancel(matching: JobQuery(tag: tag))
    }

    @discardableResult
    public func forget(_ id: JobID) async throws -> Bool {
        let deleted = try await database.value.write { db in
            guard let rawState = try String.fetchOne(
                db,
                sql: "SELECT state FROM durable_queue_jobs WHERE id = ?",
                arguments: [id.description]
            ), let state = JobState(rawValue: rawState) else { return false }
            guard state.isTerminal else {
                throw DurableQueueError.jobNotTerminal(id, actual: state)
            }
            try db.execute(sql: "DELETE FROM durable_queue_jobs WHERE id = ?", arguments: [id.description])
            return db.changesCount == 1
        }
        if deleted { await emit(kind: .forgotten, jobID: id) }
        return deleted
    }

    @discardableResult
    public func forget(matching query: JobQuery) async throws -> Int {
        try Self.validate(query)
        let rawIDs = try await database.value.write { db in
            let ids = try Self.matchingJobIDs(query, states: [.succeeded, .failed, .cancelled], in: db)
            for id in ids {
                try db.execute(sql: "DELETE FROM durable_queue_jobs WHERE id = ?", arguments: [id])
            }
            return ids
        }
        for rawID in rawIDs {
            if let uuid = UUID(uuidString: rawID) { await emit(kind: .forgotten, jobID: JobID(uuid)) }
        }
        return rawIDs.count
    }

    nonisolated static func fetchJobs(matching query: JobQuery, in db: Database) throws -> [JobInfo] {
        let selection = querySelection(query, includePagination: true)
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT j.* FROM durable_queue_jobs j \(selection.whereClause) "
                + "ORDER BY j.created_at DESC, j.id DESC LIMIT ? OFFSET ?",
            arguments: selection.arguments + [query.limit, query.cursor == nil ? query.offset : 0]
        )
        return try rows.map { row in
            let record = try JobRecord(row: row)
            let tags = try String.fetchAll(
                db,
                sql: "SELECT tag FROM durable_queue_job_tags WHERE job_id = ? ORDER BY tag",
                arguments: [record.id.description]
            )
            return JobInfo(snapshot: record.snapshot, tags: Set(tags))
        }
    }

    nonisolated private static func matchingJobIDs(
        _ query: JobQuery,
        states allowedStates: Set<JobState>,
        in db: Database
    ) throws -> [String] {
        var effective = query
        effective.states = effective.states.isEmpty
            ? allowedStates
            : effective.states.intersection(allowedStates)
        guard !effective.states.isEmpty else { return [] }
        let selection = querySelection(effective, includePagination: false)
        return try String.fetchAll(
            db,
            sql: "SELECT j.id FROM durable_queue_jobs j \(selection.whereClause) "
                + "ORDER BY j.created_at DESC, j.id DESC",
            arguments: selection.arguments
        )
    }

    nonisolated private static func retry(
        ids: [String], availableAt: Date, now: Date, in db: Database
    ) throws {
        for id in ids {
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'queued', available_at = ?, attempt_count = 0,
                        lease_token = NULL, lease_expires_at = NULL,
                        cancel_requested = 0, stop_reason = NULL, progress = 0, updated_at = ?,
                        finished_at = NULL, last_failure_kind = NULL,
                        last_failure_message = NULL, last_failure_at = NULL,
                        failure_hook_pending = 0, failure_hook_token = NULL,
                        failure_hook_expires_at = NULL, failure_hook_attempt_count = 0,
                        failure_hook_available_at = 0
                    WHERE id = ? AND state = 'failed'
                    """,
                arguments: [availableAt.databaseMilliseconds, now.databaseMilliseconds, id]
            )
        }
    }

    nonisolated private static func querySelection(
        _ query: JobQuery,
        includePagination: Bool
    ) -> (whereClause: String, arguments: StatementArguments) {
        var conditions: [String] = []
        var values: [(any DatabaseValueConvertible)?] = []

        func addSet<T: DatabaseValueConvertible>(_ column: String, values set: [T]) {
            guard !set.isEmpty else { return }
            conditions.append("\(column) IN (\(Array(repeating: "?", count: set.count).joined(separator: ", ")))")
            values.append(contentsOf: set.map { $0 })
        }

        addSet("j.state", values: query.states.map(\.rawValue).sorted())
        addSet("j.queue_name", values: query.queues.sorted())
        addSet("j.type_identifier", values: query.typeIdentifiers.sorted())
        if !query.tags.isEmpty {
            let sortedTags = query.tags.sorted()
            conditions.append(
                "EXISTS (SELECT 1 FROM durable_queue_job_tags t WHERE t.job_id = j.id "
                    + "AND t.tag IN (\(Array(repeating: "?", count: sortedTags.count).joined(separator: ", "))))"
            )
            values.append(contentsOf: sortedTags)
        }
        if includePagination, let cursor = query.cursor {
            conditions.append("(j.created_at < ? OR (j.created_at = ? AND j.id < ?))")
            values.append(cursor.createdAt.databaseMilliseconds)
            values.append(cursor.createdAt.databaseMilliseconds)
            values.append(cursor.id.description)
        }
        return (
            conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND "),
            StatementArguments(values)
        )
    }

    nonisolated private static func validate(_ query: JobQuery) throws {
        guard query.cursor?.createdAt.timeIntervalSinceReferenceDate.isFinite ?? true else {
            throw DurableQueueError.invalidDispatchOptions("query cursor date must be finite")
        }
        let strings = query.queues.union(query.typeIdentifiers).union(query.tags)
        guard strings.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw DurableQueueError.invalidDispatchOptions("query values must not be empty")
        }
    }
}
