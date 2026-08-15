import DurableQueuer
import DurableQueuerTestSupport
import Foundation
import GRDB
import Testing

@Suite("Durable queue roadmap")
struct DurableQueueRoadmapTests {
    @Test("Concurrent drains do not claim work beyond execution capacity")
    func concurrentDrainsRespectCapacity() async throws {
        let gate = JobGate()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            if job.value == "first" {
                await gate.markStarted()
                await gate.waitUntilReleased()
            }
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(maximumConcurrentJobs: 1)
        )
        _ = try await queue.dispatch(TestJob(value: "first"))
        let second = try await queue.dispatch(TestJob(value: "second"))

        let firstDrain = Task { try await queue.runDueJobs() }
        let secondDrain = Task { try await queue.runDueJobs() }
        await gate.waitUntilStarted()
        #expect(try await queue.status(second.id)?.state == .queued)
        await gate.release()
        try await firstDrain.value
        try await secondDrain.value
        #expect(try await queue.status(second.id)?.state == .succeeded)
    }

    @Test("Running replacement is an expected durable cancellation")
    func runningReplacement() async throws {
        let gate = JobGate()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            guard job.value == "old" else { return }
            await gate.markStarted()
            try await withTaskCancellationHandler {
                await gate.waitUntilCancelled()
                try Task.checkCancellation()
            } onCancel: {
                Task { await gate.markCancelled() }
            }
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let old = try await queue.dispatch(
            TestJob(value: "old"),
            options: .init(uniqueKey: "sync")
        )
        let drain = Task { try await queue.runDueJobs() }
        await gate.waitUntilStarted()
        let replacement = try await queue.dispatch(
            TestJob(value: "new"),
            options: .init(uniqueKey: "sync", uniquePolicy: .replace)
        )
        try await drain.value

        let oldSnapshot = try #require(try await queue.status(old.id))
        #expect(oldSnapshot.state == .cancelled)
        #expect(oldSnapshot.stopReason == .replaced)
        #expect(try await queue.status(replacement.id)?.state == .succeeded)
    }

    @Test("A second queue instance cancels cooperative work through lease maintenance")
    func crossInstanceCancellation() async throws {
        let gate = JobGate()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DurableQueuer-cancel-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let firstDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        let secondDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
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
        let configuration = DurableQueueConfiguration(
            leaseDuration: 1,
            heartbeatInterval: 0.02
        )
        let first = try DurableQueue(
            database: firstDatabase,
            registry: registry,
            configuration: configuration
        )
        let second = try DurableQueue(
            database: secondDatabase,
            registry: registry,
            configuration: configuration
        )
        let receipt = try await first.dispatch(TestJob(value: "cancel"))
        let drain = Task { try await first.runDueJobs() }
        await gate.waitUntilStarted()
        try await second.cancel(receipt.id)
        await gate.waitUntilCancelled()
        try await drain.value
        #expect(try await first.status(receipt.id)?.stopReason == .userCancelled)
    }

    @Test("Recurring latest work and chains use the normal job engine")
    func recurringAndChains() async throws {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 10_000))
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            await recorder.record(job.value)
            if job.shouldFail { throw TestJobError.expected }
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { clock.now }, randomUnit: { 0 })
        )
        _ = try await queue.scheduleRecurring(
            RecurringScheduleID(rawValue: "sync"),
            job: TestJob(value: "recurring"),
            schedule: .init(interval: 10, firstRunAt: clock.now)
        )
        try await queue.runDueJobs()
        clock.advance(by: 35)
        try await queue.runDueJobs()
        #expect(await recorder.values == ["recurring", "recurring"])

        let chain = try await queue.dispatchChain([
            try ChainStep(TestJob(value: "one")),
            try ChainStep(TestJob(value: "two")),
        ])
        #expect(try await queue.status(chain.jobs[1].id)?.state == .blocked)
        try await queue.runDueJobs()
        #expect(try await queue.status(chain.jobs[1].id)?.state == .succeeded)
    }

    @Test("Failure cascades and runRegardless releases cleanup work")
    func chainFailureAndCleanup() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            await recorder.record(job.value)
            if job.shouldFail { throw TestJobError.expected }
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let chain = try await queue.dispatchChain([
            try ChainStep(TestJob(value: "fail", shouldFail: true), options: .init(maxAttempts: 1)),
            try ChainStep(TestJob(value: "skipped")),
            try ChainStep(TestJob(value: "cleanup"), behavior: .runRegardless),
        ])
        try await queue.runDueJobs()

        #expect(try await queue.status(chain.jobs[0].id)?.state == .failed)
        #expect(try await queue.status(chain.jobs[1].id)?.stopReason == .dependencyFailed)
        #expect(try await queue.status(chain.jobs[2].id)?.state == .succeeded)
        #expect(await recorder.values == ["fail", "cleanup"])
    }

    @Test("Append, bulk dispatch, batch progress, and attempt history are durable")
    func workflowOperations() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in await recorder.record(job.value) }
        let queue = try DurableQueue(database: database, registry: registry)

        let first = try await queue.dispatch(
            TestJob(value: "append-1"),
            options: .init(uniqueKey: "ordered")
        )
        let appended = try await queue.dispatch(
            TestJob(value: "append-2"),
            options: .init(uniqueKey: "ordered", uniquePolicy: .append)
        )
        #expect(appended.result == .appended)
        #expect(try await queue.status(appended.id)?.state == .blocked)

        let bulk = try await queue.dispatchAll([
            try JobRequest(TestJob(value: "bulk-1")),
            try JobRequest(TestJob(value: "bulk-2")),
        ])
        #expect(bulk.count == 2)
        let batch = try await queue.dispatchBatch(
            [
                try JobRequest(TestJob(value: "batch-1")),
                try JobRequest(TestJob(value: "batch-2")),
            ],
            completion: try JobRequest(TestJob(value: "batch-complete"))
        )
        try await queue.runDueJobs()
        #expect(try await queue.status(first.id)?.state == .succeeded)
        #expect(try await queue.status(appended.id)?.state == .succeeded)
        #expect(try await queue.batch(batch.id)?.progress == 1)
        #expect(try await queue.attempts(for: first.id).count == 1)
    }

    @Test("Database-backed observation sees another queue instance")
    func crossInstanceObservation() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DurableQueuer-observe-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let firstDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        let secondDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let configuration = DurableQueueConfiguration(observationPollingInterval: 0.01)
        let first = try DurableQueue(
            database: firstDatabase,
            registry: registry,
            configuration: configuration
        )
        let second = try DurableQueue(
            database: secondDatabase,
            registry: registry,
            configuration: configuration
        )
        let receipt = try await second.dispatch(TestJob(value: "observed"))
        var iterator = await first.observe(receipt.id).makeAsyncIterator()
        let initial = try #require(try await iterator.next())
        #expect(initial?.state == .queued)
        try await second.cancel(receipt.id)
        let changed = try #require(try await iterator.next())
        #expect(changed?.state == .cancelled)
    }

    @Test("Invalid configuration and dispatch values return typed errors")
    func validation() async throws {
        let database = try TestDatabaseFactory.inMemory()
        #expect(throws: DurableQueueError.self) {
            _ = try DurableQueue(
                database: database,
                registry: JobRegistry(),
                configuration: .init(leaseDuration: .nan)
            )
        }

        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(database: database, registry: registry)
        await #expect(throws: DurableQueueError.self) {
            _ = try await queue.dispatch(TestJob(value: "invalid"), options: .init(delay: .infinity))
        }
    }

    @Test("Bounded all catch-up persists across queue instances")
    func recurringCatchUpAndRestart() async throws {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 20_000))
        let recorder = JobRecorder()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DurableQueuer-recurring-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let firstDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        let secondDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in await recorder.record(job.value) }
        let configuration = DurableQueueConfiguration(now: { clock.now })
        let first = try DurableQueue(
            database: firstDatabase,
            registry: registry,
            configuration: configuration
        )
        let scheduleID = RecurringScheduleID(rawValue: "catch-up")
        _ = try await first.scheduleRecurring(
            scheduleID,
            job: TestJob(value: "catch-up"),
            schedule: .init(
                interval: 10,
                firstRunAt: clock.now,
                missedRunPolicy: .all(maximumCatchUp: 2)
            )
        )
        clock.advance(by: 35)
        try await first.runDueJobs()
        #expect(await recorder.values.count == 2)

        let second = try DurableQueue(
            database: secondDatabase,
            registry: registry,
            configuration: configuration
        )
        clock.advance(by: 5)
        try await second.runDueJobs()
        #expect(await recorder.values.count == 3)

        let updated = try await second.scheduleRecurring(
            scheduleID,
            job: TestJob(value: "updated"),
            schedule: .init(interval: 20, firstRunAt: clock.now.addingTimeInterval(20)),
            conflictPolicy: .update
        )
        #expect(updated.interval == 20)
        try await second.pauseRecurring(scheduleID)
        clock.advance(by: 20)
        try await second.runDueJobs()
        #expect(await recorder.values.count == 3)
        try await second.resumeRecurring(scheduleID)
        try await second.runDueJobs()
        #expect(await recorder.values.last == "updated")
        #expect(try await second.cancelRecurring(scheduleID))
    }

    @Test("Group operations, health, updates, and protected payloads stay authoritative")
    func operationalAPIs() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in await recorder.record(job.value) }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(payloadProtection: TestPayloadProtection())
        )
        let first = try await queue.dispatch(
            TestJob(value: "old"),
            options: .init(delay: 60, tags: ["group"])
        )
        let createdAt = try #require(try await queue.status(first.id)?.createdAt)
        let updated = try await queue.update(
            first.id,
            with: TestJob(value: "new"),
            options: .init(tags: ["group"])
        )
        #expect(updated.id == first.id)
        #expect(updated.createdAt == createdAt)
        _ = try await queue.dispatch(
            TestJob(value: "other"),
            options: .init(delay: 60, tags: ["group"])
        )
        let health = try await queue.health()
        #expect(health.stateCounts.queued == 2)
        #expect(try await queue.cancel(tag: "group") == 2)
        #expect(try await queue.forget(matching: JobQuery(tag: "group")) == 2)

        let runnable = try await queue.dispatch(TestJob(value: "protected"))
        let stored = try #require(try await queue.encodedPayload(for: runnable.id))
        let unprotected = try JSONEncoder().encode(TestJob(value: "protected"))
        #expect(stored.data != unprotected)
        try await queue.runDueJobs()
        #expect(await recorder.values == ["protected"])
    }

    @Test("Bulk dispatch is atomic and durable rate limits release excess work")
    func atomicBulkAndRateLimit() async throws {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 30_000))
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(
            TestJob.self,
            middleware: [try RateLimited(key: "api", maximum: 1, per: 10)]
        ) { _, _ in }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { clock.now })
        )
        await #expect(throws: DurableQueueError.self) {
            _ = try await queue.dispatchAll([
                try JobRequest(TestJob(value: "valid")),
                try JobRequest(UnregisteredJob(value: "invalid")),
            ])
        }
        #expect(try await queue.jobs().isEmpty)

        let receipts = try await queue.dispatchAll([
            try JobRequest(TestJob(value: "one")),
            try JobRequest(TestJob(value: "two")),
        ])
        try await queue.runDueJobs()
        var states: [JobSnapshot?] = []
        for receipt in receipts {
            states.append(try await queue.status(receipt.id))
        }
        #expect(states.compactMap { $0 }.filter { $0.state == .succeeded }.count == 1)
        #expect(states.compactMap { $0 }.filter { $0.state == .queued }.count == 1)
        clock.advance(by: 10)
        try await queue.runDueJobs()
        for receipt in receipts {
            #expect(try await queue.status(receipt.id)?.state == .succeeded)
        }
    }

    @Test("Failure hooks stop after the configured maximum")
    func failureHookExhaustion() async throws {
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(
            TestJob.self,
            handler: { _, _ in throw TestJobError.expected },
            onFailure: { _, _, _ in throw TestJobError.expected }
        )
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(
                failureHookRetryPolicy: .fixed(delay: 0),
                maximumFailureHookAttempts: 2
            )
        )
        _ = try await queue.dispatch(TestJob(value: "fail"), options: .init(maxAttempts: 1))
        try await queue.runDueJobs()
        try await queue.runDueJobs()
        #expect(try await queue.health().pendingFailureHookCount == 0)
    }

    @Test("Corrupt metadata is quarantined without starving valid work")
    func corruptMetadataQuarantine() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in await recorder.record(job.value) }
        let queue = try DurableQueue(database: database, registry: registry)
        let poison = try await queue.dispatch(
            TestJob(value: "poison"),
            options: .init(priority: 100)
        )
        let valid = try await queue.dispatch(TestJob(value: "valid"))
        try await database.write { db in
            try db.execute(
                sql: "UPDATE durable_queue_jobs SET retry_policy = X'00' WHERE id = ?",
                arguments: [poison.id.description]
            )
        }
        try await queue.runDueJobs()
        #expect(try await queue.status(poison.id)?.lastFailure?.kind == .corruptMetadata)
        #expect(try await queue.status(valid.id)?.state == .succeeded)
        #expect(await recorder.values == ["valid"])
    }

    @Test("Job heartbeats renew owned overlap locks")
    func overlapLockRenewal() async throws {
        let clock = ManualClock(now: Date(timeIntervalSince1970: 40_000))
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(
            TestJob.self,
            middleware: [try WithoutOverlapping(key: "renewed", expiresAfter: 10)]
        ) { _, context in
            clock.advance(by: 20)
            try await context.heartbeat()
            let expiry = try await database.read { db in
                try Int64.fetchOne(
                    db,
                    sql: "SELECT expires_at FROM durable_queue_locks WHERE lock_key = 'renewed'"
                )
            }
            #expect(expiry == clock.now.addingTimeInterval(10).databaseMillisecondsForTest)
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(
                leaseDuration: 1,
                heartbeatInterval: 0.2,
                now: { clock.now }
            )
        )
        _ = try await queue.dispatch(TestJob(value: "lock"))
        try await queue.runDueJobs()
    }

    @Test("A durable per-queue limit restricts claims below global capacity")
    func perQueueConcurrency() async throws {
        let gate = JobGate()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            if job.value == "first" {
                await gate.markStarted()
                await gate.waitUntilReleased()
            }
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(maximumConcurrentJobs: 2)
        )
        try await queue.setMaximumConcurrentJobs(1, for: "limited")
        _ = try await queue.dispatch(TestJob(value: "first"), options: .init(queue: "limited"))
        let second = try await queue.dispatch(
            TestJob(value: "second"),
            options: .init(queue: "limited")
        )
        let drain = Task { try await queue.runDueJobs() }
        await gate.waitUntilStarted()
        #expect(try await queue.status(second.id)?.state == .queued)
        await gate.release()
        try await drain.value
        #expect(try await queue.status(second.id)?.state == .succeeded)
    }

    @Test("Chains retry in place, propagate cancellation, and roll back atomically")
    func chainRetryCancellationAndRollback() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            let count = await recorder.recordAndReturnCount(job.value)
            if job.value == "retry", count == 1 { throw TestJobError.expected }
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(randomUnit: { 0 })
        )
        let retrying = try await queue.dispatchChain([
            try ChainStep(
                TestJob(value: "retry"),
                options: .init(maxAttempts: 2, retryPolicy: .fixed(delay: 0))
            ),
            try ChainStep(TestJob(value: "after-retry")),
        ])
        try await queue.runDueJobs()
        #expect(try await queue.status(retrying.jobs[0].id)?.attempt == 2)
        #expect(try await queue.status(retrying.jobs[1].id)?.state == .succeeded)

        let cancelled = try await queue.dispatchChain([
            try ChainStep(TestJob(value: "cancelled"), options: .init(delay: 60)),
            try ChainStep(TestJob(value: "dependent")),
            try ChainStep(TestJob(value: "cancel-cleanup"), behavior: .runRegardless),
        ])
        try await queue.cancel(cancelled.jobs[0].id)
        #expect(try await queue.status(cancelled.jobs[1].id)?.stopReason == .dependencyCancelled)
        try await queue.runDueJobs()
        #expect(try await queue.status(cancelled.jobs[2].id)?.state == .succeeded)

        _ = try await queue.dispatch(
            TestJob(value: "unique"),
            options: .init(uniqueKey: "existing")
        )
        let before = try await queue.jobs().count
        await #expect(throws: DurableQueueError.self) {
            _ = try await queue.dispatchChain([
                try ChainStep(TestJob(value: "would-roll-back")),
                try ChainStep(
                    TestJob(value: "conflict"),
                    options: .init(uniqueKey: "existing")
                ),
            ])
        }
        #expect(try await queue.jobs().count == before)
    }
}

private extension Date {
    var databaseMillisecondsForTest: Int64 {
        Int64((timeIntervalSince1970 * 1_000).rounded())
    }
}
