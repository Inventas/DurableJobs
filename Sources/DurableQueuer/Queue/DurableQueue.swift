import Foundation
import GRDB
import Queuer

public actor DurableQueue {
    let database: DatabaseWriterBox
    let registry: JobRegistry
    let configuration: DurableQueueConfiguration
    let executor: Queuer
    var activeOperations: [JobID: AsyncConcurrentOperation] = [:]
    var eventContinuations: [UUID: AsyncStream<JobEvent>.Continuation] = [:]
    var lastProgressWrites: [JobID: Date] = [:]
    var activeStopReasons: [JobID: JobStopReason] = [:]
    var drainIsActive = false
    var drainWaiters: [CheckedContinuation<Void, Never>] = []
    weak var schedulingCoordinator: (any QueueSchedulingCoordinator)?

    public init(
        database: any DatabaseWriter,
        registry: JobRegistry,
        configuration: DurableQueueConfiguration = .default
    ) throws {
        try configuration.validate()
        let box = DatabaseWriterBox(database)
        try DurableQueueSchema.migrator().migrate(box.value)
        self.database = box
        self.registry = registry
        self.configuration = configuration
        self.executor = Queuer(
            name: "DurableQueuer",
            maxConcurrentOperationCount: configuration.maximumConcurrentJobs,
            qualityOfService: .utility
        )
    }

    public func cancel(_ id: JobID) async throws {
        let now = configuration.now().databaseMilliseconds
        let state = try await database.value.write { db -> JobState? in
            guard let value = try String.fetchOne(
                db,
                sql: "SELECT state FROM durable_queue_jobs WHERE id = ?",
                arguments: [id.description]
            ), let current = JobState(rawValue: value) else {
                return nil
            }

            switch current {
            case .blocked, .queued:
                try db.execute(
                    sql: """
                        UPDATE durable_queue_jobs
                        SET state = 'cancelled', cancel_requested = 1,
                            stop_reason = ?, finished_at = ?, updated_at = ?
                        WHERE id = ? AND state IN ('blocked', 'queued')
                        """,
                    arguments: [JobStopReason.userCancelled.rawValue, now, now, id.description]
                )
                try Self.resolveDependents(of: id.description, in: db, now: now)
                return .cancelled
            case .running:
                try db.execute(
                    sql: """
                        UPDATE durable_queue_jobs
                        SET cancel_requested = 1, stop_reason = ?, updated_at = ?
                        WHERE id = ? AND state = 'running'
                        """,
                    arguments: [JobStopReason.userCancelled.rawValue, now, id.description]
                )
                return .running
            case .succeeded, .failed, .cancelled:
                return current
            }
        }

        if state == .running {
            activeStopReasons[id] = .userCancelled
            activeOperations[id]?.cancel()
        } else if state == .cancelled {
            await emit(kind: .cancelled, jobID: id)
        }
    }

    public func attachSchedulingCoordinator(_ coordinator: any QueueSchedulingCoordinator) async {
        schedulingCoordinator = coordinator
        await coordinator.reconcile()
    }

    public func cancelActiveJobs() {
        for (id, operation) in activeOperations {
            activeStopReasons[id] = .backgroundTaskExpired
            operation.cancel()
        }
    }

    public func cancelActiveJobs(lane: JobExecutionLane) async {
        let activeIDs = (try? await database.value.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT id FROM durable_queue_jobs
                    WHERE state = 'running' AND lane = ?
                    """,
                arguments: [lane.rawValue]
            )
        }) ?? []

        for rawID in activeIDs {
            guard let uuid = UUID(uuidString: rawID) else { continue }
            let id = JobID(uuid)
            activeStopReasons[id] = .backgroundTaskExpired
            activeOperations[id]?.cancel()
        }
    }

    public func cancelActiveJob(_ id: JobID) {
        activeStopReasons[id] = .backgroundTaskExpired
        activeOperations[id]?.cancel()
    }

    public func pause(queue: String = "default") async throws {
        try validate(queue: queue)
        let now = configuration.now().databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    INSERT INTO durable_queue_controls (queue_name, is_paused, updated_at)
                    VALUES (?, 1, ?)
                    ON CONFLICT(queue_name) DO UPDATE
                    SET is_paused = 1, updated_at = excluded.updated_at
                    """,
                arguments: [queue, now]
            )
        }
        await schedulingCoordinator?.reconcile()
    }

    public func resume(queue: String = "default") async throws {
        try validate(queue: queue)
        let now = configuration.now().databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    INSERT INTO durable_queue_controls (queue_name, is_paused, updated_at)
                    VALUES (?, 0, ?)
                    ON CONFLICT(queue_name) DO UPDATE
                    SET is_paused = 0, updated_at = excluded.updated_at
                    """,
                arguments: [queue, now]
            )
        }
        await schedulingCoordinator?.reconcile()
    }

    public func setMaximumConcurrentJobs(_ limit: Int?, for queue: String = "default") async throws {
        try validate(queue: queue)
        if let limit, limit <= 0 {
            throw DurableQueueError.invalidConfiguration("queue concurrency must be positive")
        }
        let now = configuration.now().databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    INSERT INTO durable_queue_controls
                    (queue_name, is_paused, maximum_concurrency, updated_at)
                    VALUES (?, 0, ?, ?)
                    ON CONFLICT(queue_name) DO UPDATE SET
                        maximum_concurrency = excluded.maximum_concurrency,
                        updated_at = excluded.updated_at
                    """,
                arguments: [queue, limit, now]
            )
        }
    }

    public func status(_ id: JobID) async throws -> JobSnapshot? {
        try await database.value.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: "SELECT * FROM durable_queue_jobs WHERE id = ?",
                arguments: [id.description]
            ) else {
                return nil
            }
            return try JobRecord(row: row).snapshot
        }
    }

    public func events() -> AsyncStream<JobEvent> {
        let streamID = UUID()
        return AsyncStream(bufferingPolicy: .bufferingNewest(configuration.eventBufferLimit)) { continuation in
            eventContinuations[streamID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeEventContinuation(streamID) }
            }
        }
    }

    public func nextEligibleDate(lane: JobExecutionLane) async throws -> Date? {
        let value = try await database.value.read { db in
            try Int64.fetchOne(
                db,
                sql: """
                    SELECT MIN(candidate) FROM (
                        SELECT j.available_at AS candidate
                        FROM durable_queue_jobs j
                        LEFT JOIN durable_queue_controls c ON c.queue_name = j.queue_name
                        WHERE j.state = 'queued' AND j.lane = ?
                          AND COALESCE(c.is_paused, 0) = 0
                        UNION ALL
                        SELECT next_run_at - CAST(flex_seconds * 1000 AS INTEGER) AS candidate
                        FROM durable_queue_recurring
                        WHERE is_paused = 0 AND lane = ?
                    )
                    """,
                arguments: [lane.rawValue, lane.rawValue]
            )
        }
        return value.map(Date.init(databaseMilliseconds:))
    }

    public func runDueJobs() async throws {
        await acquireDrainPermit()
        do {
            try await drainDueJobs(lane: nil)
            releaseDrainPermit()
        } catch {
            releaseDrainPermit()
            throw error
        }
    }

    public func runDueJobs(lane: JobExecutionLane) async throws {
        await acquireDrainPermit()
        do {
            try await drainDueJobs(lane: lane)
            releaseDrainPermit()
        } catch {
            releaseDrainPermit()
            throw error
        }
    }

    @discardableResult
    public func runDueJob(_ id: JobID) async throws -> JobSnapshot? {
        await acquireDrainPermit()
        do {
            try Task.checkCancellation()
            try await materializeDueRecurringWork()
            try await recoverExpiredWork()
            try await runPendingFailureHooks(limit: configuration.maximumConcurrentJobs)
            try await pruneExpiredHistory()

            if let claim = try await claimJob(id: id) {
                try await enqueueAndWait(claim)
            }
            let snapshot = try await status(id)
            releaseDrainPermit()
            return snapshot
        } catch {
            releaseDrainPermit()
            throw error
        }
    }

    /// Runs at most one eligible job and returns its final or rescheduled state.
    @discardableResult
    public func runNext() async throws -> JobSnapshot? {
        await acquireDrainPermit()
        do {
            try await recoverExpiredWork()
            try await materializeDueRecurringWork()
            try await runPendingFailureHooks(limit: 1)
            guard let claim = try await claimNextJob() else {
                releaseDrainPermit()
                return nil
            }
            try await enqueueAndWait(claim)
            let snapshot = try await status(claim.id)
            releaseDrainPermit()
            return snapshot
        } catch {
            releaseDrainPermit()
            throw error
        }
    }

    private func drainDueJobs(lane: JobExecutionLane?) async throws {
        try Task.checkCancellation()
        try await materializeDueRecurringWork()
        try await recoverExpiredWork()
        try await runPendingFailureHooks(limit: configuration.maximumConcurrentJobs)
        try await pruneExpiredHistory()

        while !Task.isCancelled {
            var claims: [JobRecord] = []
            for _ in 0 ..< configuration.maximumConcurrentJobs {
                guard let claim = try await claimNextJob(lane: lane) else { break }
                claims.append(claim)
            }
            guard !claims.isEmpty else { break }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for claim in claims {
                    group.addTask { try await self.enqueueAndWait(claim) }
                }
                try await group.waitForAll()
            }
        }
        try Task.checkCancellation()
    }

    public func pruneCompleted(before date: Date) async throws {
        guard date.timeIntervalSinceReferenceDate.isFinite else {
            throw DurableQueueError.invalidDispatchOptions("prune date must be finite")
        }
        let cutoff = date.databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    DELETE FROM durable_queue_jobs
                    WHERE state IN ('succeeded', 'failed', 'cancelled')
                      AND finished_at IS NOT NULL AND finished_at < ?
                    """,
                arguments: [cutoff]
            )
        }
    }

    public func pruneExpiredHistory() async throws {
        let now = configuration.now()
        let succeededCutoff = now.addingTimeInterval(-configuration.succeededRetention)
            .databaseMilliseconds
        let cancelledCutoff = now.addingTimeInterval(-configuration.cancelledRetention)
            .databaseMilliseconds
        let failedCutoff = now.addingTimeInterval(-configuration.failedRetention)
            .databaseMilliseconds
        try await database.value.write { db in
            try db.execute(
                sql: """
                    DELETE FROM durable_queue_jobs
                    WHERE (state = 'succeeded' AND finished_at < ?)
                       OR (state = 'cancelled' AND finished_at < ?)
                       OR (state = 'failed' AND finished_at < ? AND failure_hook_pending = 0)
                    """,
                arguments: [succeededCutoff, cancelledCutoff, failedCutoff]
            )
        }
    }

    private func acquireDrainPermit() async {
        if !drainIsActive {
            drainIsActive = true
            return
        }
        await withCheckedContinuation { continuation in
            drainWaiters.append(continuation)
        }
    }

    private func releaseDrainPermit() {
        guard !drainWaiters.isEmpty else {
            drainIsActive = false
            return
        }
        drainWaiters.removeFirst().resume()
    }
}
