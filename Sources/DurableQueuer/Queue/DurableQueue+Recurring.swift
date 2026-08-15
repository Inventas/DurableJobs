import Foundation
import GRDB

extension DurableQueue {
    @discardableResult
    public func scheduleRecurring<J: DurableJob>(
        _ id: RecurringScheduleID,
        job: J,
        schedule: RecurringSchedule,
        options: DispatchOptions = .defaults,
        conflictPolicy: RecurringConflictPolicy = .keep
    ) async throws -> RecurringScheduleSnapshot {
        let normalizedID = id.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else {
            throw DurableQueueError.invalidDispatchOptions("recurring schedule ID must not be empty")
        }
        try Self.validate(schedule)
        let request = try JobRequest(job, options: options)
        guard registry.job(for: J.typeIdentifier) != nil else {
            throw DurableQueueError.jobTypeNotRegistered(J.typeIdentifier)
        }
        let now = configuration.now()
        let nextRun = schedule.firstRunAt ?? now.addingTimeInterval(schedule.interval)
        let encodedRequest = try JobPayloadCodec.encoder().encode(request)
        let effectiveLane = try prepareDispatch(request, now: now).options.lane
        let policy = schedule.missedRunPolicy.databaseValues

        let snapshot = try await database.value.write { db -> RecurringScheduleSnapshot in
            if conflictPolicy == .keep,
               let existing = try Row.fetchOne(
                db,
                sql: "SELECT * FROM durable_queue_recurring WHERE id = ?",
                arguments: [normalizedID]
               ) {
                return try Self.recurringSnapshot(row: existing)
            }
            try db.execute(
                sql: """
                    INSERT INTO durable_queue_recurring (
                        id, request, lane, interval_seconds, flex_seconds,
                        missed_run_policy, maximum_catch_up, next_run_at,
                        is_paused, created_at, updated_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
                    ON CONFLICT(id) DO UPDATE SET
                        request = excluded.request,
                        lane = excluded.lane,
                        interval_seconds = excluded.interval_seconds,
                        flex_seconds = excluded.flex_seconds,
                        missed_run_policy = excluded.missed_run_policy,
                        maximum_catch_up = excluded.maximum_catch_up,
                        next_run_at = excluded.next_run_at,
                        updated_at = excluded.updated_at
                    """,
                arguments: [
                    normalizedID, encodedRequest, effectiveLane.rawValue,
                    schedule.interval, schedule.flex,
                    policy.name, policy.maximumCatchUp, nextRun.databaseMilliseconds,
                    now.databaseMilliseconds, now.databaseMilliseconds,
                ]
            )
            let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM durable_queue_recurring WHERE id = ?",
                arguments: [normalizedID]
            )!
            return try Self.recurringSnapshot(row: row)
        }
        await schedulingCoordinator?.reconcile()
        return snapshot
    }

    public func recurringSchedule(_ id: RecurringScheduleID) async throws -> RecurringScheduleSnapshot? {
        try await database.value.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM durable_queue_recurring WHERE id = ?",
                arguments: [id.rawValue]
            ) else { return nil }
            return try Self.recurringSnapshot(row: row)
        }
    }

    public func pauseRecurring(_ id: RecurringScheduleID) async throws {
        try await setRecurringPaused(true, id: id)
    }

    public func resumeRecurring(_ id: RecurringScheduleID) async throws {
        try await setRecurringPaused(false, id: id)
    }

    @discardableResult
    public func cancelRecurring(_ id: RecurringScheduleID) async throws -> Bool {
        let deleted = try await database.value.write { db in
            try db.execute(
                sql: "DELETE FROM durable_queue_recurring WHERE id = ?",
                arguments: [id.rawValue]
            )
            return db.changesCount == 1
        }
        await schedulingCoordinator?.reconcile()
        return deleted
    }

    func materializeDueRecurringWork() async throws {
        let now = configuration.now()
        let insertedIDs = try await database.value.write { db -> [JobID] in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT * FROM durable_queue_recurring
                    WHERE is_paused = 0
                      AND next_run_at - CAST(flex_seconds * 1000 AS INTEGER) <= ?
                    ORDER BY next_run_at, id
                    """,
                arguments: [now.databaseMilliseconds]
            )
            var inserted: [JobID] = []
            for row in rows {
                let scheduleID: String = row["id"]
                let request = try JobPayloadCodec.decoder().decode(
                    JobRequest.self,
                    from: row["request"]
                )
                let interval: TimeInterval = row["interval_seconds"]
                let flex: TimeInterval = row["flex_seconds"]
                let next = Date(databaseMilliseconds: row["next_run_at"])
                let dueCount = max(
                    1,
                    Int(floor(now.timeIntervalSince(next.addingTimeInterval(-flex)) / interval)) + 1
                )
                let policy: String = row["missed_run_policy"]
                let maximumCatchUp: Int = row["maximum_catch_up"]
                let indices: Range<Int>
                if policy == "latest" {
                    indices = (dueCount - 1) ..< dueCount
                } else {
                    indices = max(0, dueCount - maximumCatchUp) ..< dueCount
                }

                for index in indices {
                    let occurrence = next.addingTimeInterval(Double(index) * interval)
                    var occurrenceOptions = request.options
                    occurrenceOptions.availableAt = occurrence.addingTimeInterval(-flex)
                    occurrenceOptions.delay = nil
                    occurrenceOptions.uniqueKey = nil
                    let occurrenceRequest = JobRequest(
                        typeIdentifier: request.typeIdentifier,
                        payload: request.payload,
                        payloadVersion: request.payloadVersion,
                        defaults: request.defaults,
                        options: occurrenceOptions
                    )
                    let prepared = try prepareDispatch(occurrenceRequest, now: now)
                    let receipt = try prepared.insert(in: db)
                    if receipt.result != .existing {
                        try db.execute(
                            sql: """
                                UPDATE durable_queue_jobs
                                SET recurring_id = ?, recurring_occurrence_at = ?
                                WHERE id = ?
                                """,
                            arguments: [
                                scheduleID,
                                occurrence.databaseMilliseconds,
                                receipt.id.description,
                            ]
                        )
                        inserted.append(receipt.id)
                    }
                }
                let following = next.addingTimeInterval(Double(dueCount) * interval)
                try db.execute(
                    sql: """
                        UPDATE durable_queue_recurring
                        SET next_run_at = ?, updated_at = ? WHERE id = ?
                        """,
                    arguments: [following.databaseMilliseconds, now.databaseMilliseconds, scheduleID]
                )
            }
            return inserted
        }
        for id in insertedIDs { await emit(kind: .dispatched, jobID: id) }
    }

    private func setRecurringPaused(_ paused: Bool, id: RecurringScheduleID) async throws {
        let now = configuration.now().databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_recurring
                    SET is_paused = ?, updated_at = ? WHERE id = ?
                    """,
                arguments: [paused ? 1 : 0, now, id.rawValue]
            )
            guard db.changesCount == 1 else {
                throw DurableQueueError.invalidDispatchOptions("recurring schedule was not found")
            }
        }
        await schedulingCoordinator?.reconcile()
    }

    nonisolated private static func validate(_ schedule: RecurringSchedule) throws {
        guard schedule.interval.isFinite, schedule.interval > 0 else {
            throw DurableQueueError.invalidDispatchOptions("recurring interval must be finite and positive")
        }
        guard schedule.flex.isFinite, schedule.flex >= 0, schedule.flex < schedule.interval else {
            throw DurableQueueError.invalidDispatchOptions("recurring flex must be nonnegative and shorter than the interval")
        }
        guard schedule.firstRunAt?.timeIntervalSinceReferenceDate.isFinite ?? true else {
            throw DurableQueueError.invalidDispatchOptions("recurring firstRunAt must be finite")
        }
        if case let .all(maximumCatchUp) = schedule.missedRunPolicy,
           maximumCatchUp <= 0 {
            throw DurableQueueError.invalidDispatchOptions("maximumCatchUp must be positive")
        }
    }

    nonisolated private static func recurringSnapshot(row: Row) throws -> RecurringScheduleSnapshot {
        let policy: RecurringMissedRunPolicy
        if (row["missed_run_policy"] as String) == "all" {
            policy = .all(maximumCatchUp: row["maximum_catch_up"])
        } else {
            policy = .latest
        }
        return RecurringScheduleSnapshot(
            id: RecurringScheduleID(rawValue: row["id"]),
            interval: row["interval_seconds"],
            flex: row["flex_seconds"],
            missedRunPolicy: policy,
            nextRunAt: Date(databaseMilliseconds: row["next_run_at"]),
            isPaused: (row["is_paused"] as Int) != 0
        )
    }
}

private extension RecurringMissedRunPolicy {
    var databaseValues: (name: String, maximumCatchUp: Int) {
        switch self {
        case .latest:
            ("latest", 1)
        case let .all(maximumCatchUp):
            ("all", maximumCatchUp)
        }
    }
}
