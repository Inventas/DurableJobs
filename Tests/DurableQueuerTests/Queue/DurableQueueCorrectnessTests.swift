import DurableQueuer
import DurableQueuerTestSupport
import Foundation
import GRDB
import Testing

@Suite("Durable queue correctness")
struct DurableQueueCorrectnessTests {
    @Test("A storage failure reaches the drain caller")
    func drainReportsStorageFailure() async throws {
        let database = try TestDatabaseFactory.inMemory()
        let queue = try DurableQueue(database: database, registry: JobRegistry())
        try database.close()

        await #expect(throws: (any Error).self) {
            try await queue.runDueJobs()
        }
    }

    @Test("Claiming and starting an attempt is one durable transition")
    func claimConsumesAttemptBeforeHandlerRuns() async throws {
        let gate = JobGate()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in
            await gate.markStarted()
            try await withTaskCancellationHandler {
                await gate.waitUntilCancelled()
                try Task.checkCancellation()
            } onCancel: {
                Task { await gate.markCancelled() }
            }
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(TestJob(value: "claimed"))

        let drain = Task { try await queue.runDueJobs() }
        await gate.waitUntilStarted()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .running)
        #expect(snapshot.attempt == 1)

        try await queue.cancel(receipt.id)
        try await drain.value
        #expect(try await queue.status(receipt.id)?.state == .cancelled)
    }

    @Test("Lease loss cancels stale execution and reaches the drain caller")
    func leaseLossCancelsExecution() async throws {
        let gate = JobGate()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in
            await gate.markStarted()
            try await withTaskCancellationHandler {
                await gate.waitUntilCancelled()
                try Task.checkCancellation()
            } onCancel: {
                Task { await gate.markCancelled() }
            }
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(leaseDuration: 1, heartbeatInterval: 0.1)
        )
        let receipt = try await queue.dispatch(TestJob(value: "lease"))

        let drain = Task { try await queue.runDueJobs() }
        await gate.waitUntilStarted()
        try await database.write { db in
            try db.execute(
                sql: "UPDATE durable_queue_jobs SET lease_token = 'new-owner' WHERE id = ?",
                arguments: [receipt.id.description]
            )
        }

        do {
            try await drain.value
            Issue.record("Expected the stale worker to report lease loss")
        } catch let error as DurableQueueError {
            #expect(error == .leaseLost(receipt.id))
        }
        await gate.waitUntilCancelled()
        #expect(try await queue.status(receipt.id)?.state == .running)
    }

    @Test("A stale handler cannot fail a job owned by a newer lease")
    func staleHandlerCannotWriteTerminalFailure() async throws {
        let gate = JobGate()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in
            await gate.markStarted()
            await gate.waitUntilReleased()
            throw TestJobError.expected
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(
            TestJob(value: "stale"),
            options: .init(maxAttempts: 1)
        )

        let drain = Task { try await queue.runDueJobs() }
        await gate.waitUntilStarted()
        try await database.write { db in
            try db.execute(
                sql: "UPDATE durable_queue_jobs SET lease_token = 'new-owner' WHERE id = ?",
                arguments: [receipt.id.description]
            )
        }
        await gate.release()

        do {
            try await drain.value
            Issue.record("Expected the stale terminal transition to lose its lease")
        } catch let error as DurableQueueError {
            #expect(error == .leaseLost(receipt.id))
        }
        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .running)
        #expect(snapshot.lastFailure == nil)
    }

    @Test("Process interruption retries even when handler errors do not retry")
    func interruptionRetryIsIndependentFromHandlerRetryPolicy() async throws {
        let now = Date(timeIntervalSince1970: 50_000)
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            await recorder.record(job.value)
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { now })
        )
        let receipt = try await queue.dispatch(
            TestJob(value: "interrupted"),
            options: .init(retryPolicy: RetryPolicy.none)
        )
        try await database.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'running', attempt_count = 1,
                        lease_token = 'stale', lease_expires_at = 0
                    WHERE id = ?
                    """,
                arguments: [receipt.id.description]
            )
        }

        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .succeeded)
        #expect(snapshot.attempt == 2)
        #expect(await recorder.values == ["interrupted"])
    }

    @Test("Application data and a job commit or roll back together")
    func transactionAwareDispatch() async throws {
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(database: database, registry: registry)
        try await database.write { db in
            try db.execute(sql: "CREATE TABLE application_records (id TEXT PRIMARY KEY)")
        }

        await #expect(throws: TestJobError.expected) {
            try await database.write { db in
                try db.execute(
                    sql: "INSERT INTO application_records (id) VALUES ('rolled-back')"
                )
                _ = try queue.dispatch(
                    TestJob(value: "rolled-back"),
                    options: .init(tags: ["transaction"]),
                    in: db
                )
                throw TestJobError.expected
            }
        }
        let rolledBackCounts = try await database.read { db in
            (
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM application_records") ?? -1,
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM durable_queue_jobs") ?? -1
            )
        }
        #expect(rolledBackCounts == (0, 0))

        let receipt = try await database.write { db in
            try db.execute(sql: "INSERT INTO application_records (id) VALUES ('committed')")
            return try queue.dispatch(
                TestJob(value: "committed"),
                options: .init(tags: ["transaction"]),
                in: db
            )
        }
        #expect(receipt.result == .inserted)
        #expect(try await queue.status(receipt.id)?.state == .queued)
        #expect(
            try await queue.jobs(matching: JobQuery(tag: "transaction")).map(\.snapshot.id)
                == [receipt.id]
        )
    }

    @Test("Two queue instances deliver one failure hook")
    func failureHookHasExclusiveOwnership() async throws {
        let now = Date(timeIntervalSince1970: 60_000)
        let recorder = JobRecorder()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DurableQueuer-hooks-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let firstDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        let secondDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        var registry = JobRegistry()
        try registry.register(
            TestJob.self,
            handler: { _, _ in },
            onFailure: { _, failure, _ in await recorder.record(failure) }
        )
        let configuration = DurableQueueConfiguration(now: { now })
        let firstQueue = try DurableQueue(
            database: firstDatabase,
            registry: registry,
            configuration: configuration
        )
        let secondQueue = try DurableQueue(
            database: secondDatabase,
            registry: registry,
            configuration: configuration
        )
        let receipt = try await firstQueue.dispatch(TestJob(value: "hook"))
        try await firstDatabase.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'failed', finished_at = ?, failure_hook_pending = 1,
                        last_failure_kind = 'handlerError',
                        last_failure_message = 'failed', last_failure_at = ?
                    WHERE id = ?
                    """,
                arguments: [
                    Int64(now.timeIntervalSince1970 * 1_000),
                    Int64(now.timeIntervalSince1970 * 1_000),
                    receipt.id.description,
                ]
            )
        }

        async let firstRun: Void = firstQueue.runDueJobs()
        async let secondRun: Void = secondQueue.runDueJobs()
        _ = try await (firstRun, secondRun)

        #expect(await recorder.failures.count == 1)
    }

    @Test("A failed failure hook waits for its durable retry time")
    func failureHookUsesDurableBackoff() async throws {
        let now = Date(timeIntervalSince1970: 70_000)
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(
            TestJob.self,
            handler: { _, _ in },
            onFailure: { _, failure, _ in
                await recorder.record(failure)
                throw TestJobError.expected
            }
        )
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(
                failureHookRetryPolicy: .fixed(delay: 60),
                now: { now }
            )
        )
        let receipt = try await queue.dispatch(TestJob(value: "hook-retry"))
        let nowValue = Int64(now.timeIntervalSince1970 * 1_000)
        try await database.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'failed', finished_at = ?, failure_hook_pending = 1,
                        last_failure_kind = 'handlerError',
                        last_failure_message = 'failed', last_failure_at = ?
                    WHERE id = ?
                    """,
                arguments: [nowValue, nowValue, receipt.id.description]
            )
        }

        try await queue.runDueJobs()
        try await queue.runDueJobs()

        let hookState: (Int, String?, Int, Int64)? = try await database.read { db in
            guard let row = try Row.fetchOne(
                db,
                sql: """
                    SELECT failure_hook_pending, failure_hook_token,
                           failure_hook_attempt_count, failure_hook_available_at
                    FROM durable_queue_jobs WHERE id = ?
                """,
                arguments: [receipt.id.description]
            ) else {
                return nil
            }
            return (
                row["failure_hook_pending"],
                row["failure_hook_token"],
                row["failure_hook_attempt_count"],
                row["failure_hook_available_at"]
            )
        }
        let state = try #require(hookState)
        #expect(await recorder.failures.count == 1)
        #expect(state.0 == 1)
        #expect(state.1 == nil)
        #expect(state.2 == 1)
        #expect(state.3 == nowValue + 60_000)
    }
}
