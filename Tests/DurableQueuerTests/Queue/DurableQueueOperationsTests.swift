import DurableQueuer
import DurableQueuerTestSupport
import Foundation
import Testing

@Suite("Durable queue operations")
struct DurableQueueOperationsTests {
    @Test("Replace policy cancels active unique work and runs the new payload")
    func replaceUniqueJob() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            await recorder.record(job.value)
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let first = try await queue.dispatch(
            TestJob(value: "old"),
            options: .init(uniqueKey: "sync:account")
        )
        let replacement = try await queue.dispatch(
            TestJob(value: "new"),
            options: .init(
                uniqueKey: "sync:account",
                uniquePolicy: .replace
            )
        )

        #expect(first.result == .inserted)
        #expect(replacement.result == .replaced)
        #expect(replacement.replacedJobID == first.id)
        #expect(try await queue.status(first.id)?.state == .cancelled)
        #expect(try await queue.status(replacement.id)?.state == .queued)

        try await queue.runDueJobs()
        #expect(await recorder.values == ["new"])
        #expect(try await queue.status(replacement.id)?.state == .succeeded)
    }

    @Test("Job queries filter bounded durable status and tags")
    func queriesFilterJobsAndTags() async throws {
        let now = Date(timeIntervalSince1970: 80_000)
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { now })
        )
        let completed = try await queue.dispatch(
            TestJob(value: "completed"),
            options: .init(queue: "sync", tags: ["account:1", "sync"])
        )
        let delayed = try await queue.dispatch(
            TestJob(value: "delayed"),
            options: .init(delay: 60, tags: ["account:2", "sync"])
        )
        try await queue.runDueJobs()

        let succeeded = try await queue.jobs(
            matching: JobQuery(state: .succeeded, queue: "sync")
        )
        #expect(succeeded.map(\.snapshot.id) == [completed.id])
        #expect(succeeded.first?.tags == ["account:1", "sync"])

        let accountTwo = try await queue.jobs(
            matching: JobQuery(tag: "account:2")
        )
        #expect(accountTwo.map(\.snapshot.id) == [delayed.id])
        #expect(accountTwo.first?.snapshot.state == .queued)

        let firstPage = try await queue.jobs(
            matching: JobQuery(typeIdentifier: TestJob.typeIdentifier, limit: 1)
        )
        #expect(firstPage.count == 1)
    }

    @Test("A failed job can be retried with its tags preserved")
    func retryFailedJob() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            let count = await recorder.recordAndReturnCount(job.value)
            if count == 1 {
                throw TestJobError.expected
            }
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(
            TestJob(value: "retry"),
            options: .init(maxAttempts: 1, tags: ["manual-retry"])
        )
        try await queue.runDueJobs()
        #expect(try await queue.status(receipt.id)?.state == .failed)

        try await queue.retry(receipt.id)
        let queued = try #require(try await queue.status(receipt.id))
        #expect(queued.state == .queued)
        #expect(queued.attempt == 0)
        #expect(queued.lastFailure == nil)

        try await queue.runDueJobs()
        let succeeded = try #require(try await queue.status(receipt.id))
        #expect(succeeded.state == .succeeded)
        #expect(succeeded.attempt == 1)
        let result = try #require(
            try await queue.jobs(matching: JobQuery(tag: "manual-retry")).first
        )
        #expect(result.snapshot.id == receipt.id)
    }

    @Test("Only terminal jobs can be forgotten")
    func forgetRequiresTerminalJob() async throws {
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(
            TestJob(value: "forget"),
            options: .init(tags: ["removable"])
        )

        await #expect {
            try await queue.forget(receipt.id)
        } throws: { error in
            error as? DurableQueueError == .jobNotTerminal(receipt.id, actual: .queued)
        }

        try await queue.cancel(receipt.id)
        #expect(try await queue.forget(receipt.id))
        #expect(try await queue.status(receipt.id) == nil)
        #expect(try await queue.jobs(matching: JobQuery(tag: "removable")).isEmpty)
        #expect(try await queue.forget(receipt.id) == false)
    }
}
