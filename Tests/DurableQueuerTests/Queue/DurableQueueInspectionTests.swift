import DurableQueuer
import DurableQueuerTestSupport
import Foundation
import Testing

@Suite("Durable queue inspection")
struct DurableQueueInspectionTests {
    @Test("Metrics aggregate states, queues, pause controls, and hourly activity")
    func metricsAggregateDurableState() async throws {
        let now = Date(timeIntervalSince1970: 90_000)
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            if job.value == "failure" {
                throw TestJobError.expected
            }
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { now })
        )

        _ = try await queue.dispatch(
            TestJob(value: "success"),
            options: .init(queue: "sync")
        )
        _ = try await queue.dispatch(
            TestJob(value: "failure"),
            options: .init(queue: "email", maxAttempts: 1)
        )
        _ = try await queue.dispatch(
            TestJob(value: "pending"),
            options: .init(queue: "sync", delay: 60)
        )
        let cancelled = try await queue.dispatch(
            TestJob(value: "cancelled"),
            options: .init(queue: "cleanup", delay: 60)
        )
        try await queue.cancel(cancelled.id)
        try await queue.pause(queue: "empty")
        try await queue.runDueJobs()

        let snapshot = try await queue.metrics(
            since: now.addingTimeInterval(-24 * 60 * 60),
            bucketDuration: 60 * 60
        )

        #expect(snapshot.capturedAt == now)
        #expect(snapshot.activity.count == 24)
        #expect(snapshot.stateCounts == JobStateCounts(
            queued: 1,
            succeeded: 1,
            failed: 1,
            cancelled: 1
        ))
        #expect(snapshot.activity.dropLast().allSatisfy {
            $0.succeeded == 0 && $0.failed == 0
        })
        #expect(snapshot.activity.last?.succeeded == 1)
        #expect(snapshot.activity.last?.failed == 1)

        let empty = try #require(snapshot.queues.first { $0.queue == "empty" })
        #expect(empty.isPaused)
        #expect(empty.stateCounts.total == 0)

        let sync = try #require(snapshot.queues.first { $0.queue == "sync" })
        #expect(sync.stateCounts.queued == 1)
        #expect(sync.stateCounts.succeeded == 1)
    }

    @Test("Encoded payload inspection is lazy and preserves stored bytes")
    func encodedPayloadIsLoadedByIdentifier() async throws {
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(TestJob(value: "payload"))

        let payload = try #require(try await queue.encodedPayload(for: receipt.id))
        let decoded = try JSONDecoder().decode(TestJob.self, from: payload.data)

        #expect(payload.typeIdentifier == TestJob.typeIdentifier)
        #expect(payload.version == TestJob.payloadVersion)
        #expect(decoded.value == "payload")
        #expect(try await queue.encodedPayload(for: JobID()) == nil)
    }
}
