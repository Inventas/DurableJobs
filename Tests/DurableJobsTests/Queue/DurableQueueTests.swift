import DurableJobs
import DurableJobsTestSupport
import Foundation
import GRDB
import Testing

@Suite("Durable queue")
struct DurableQueueTests {
    @Test("Job requirements compose as an option set")
    func jobRequirementsCompose() throws {
        let requirements: JobRequirements = [.networkConnectivity, .externalPower]

        #expect(requirements.contains(.networkConnectivity))
        #expect(requirements.contains(.externalPower))
        #expect(requirements.rawValue == 3)

        let roundTripped = try JSONDecoder().decode(
            JobRequirements.self,
            from: JSONEncoder().encode(requirements)
        )
        #expect(roundTripped == requirements)
    }

    @Test("Requirements select the matching execution lane")
    func requirementsSelectExecutionLane() async throws {
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(database: database, registry: registry)

        let receipt = try await queue.dispatch(
            TestJob(value: "constrained"),
            options: .init(requirements: [.networkConnectivity, .externalPower])
        )

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.lane == .processingNetworkAndPower)
    }

    @Test("Dispatch and execute a typed Codable job")
    func dispatchAndExecute() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJobHandler(recorder: recorder))
        let queue = try DurableQueue(database: database, registry: registry)

        let receipt = try await queue.dispatch(TestJob(value: "one"))
        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(receipt.result == .inserted)
        #expect(snapshot.state == .succeeded)
        #expect(snapshot.attempt == 1)
        #expect(snapshot.progress == 1)
        #expect(await recorder.values == ["one"])
    }

    @Test("A delayed job stays queued")
    func delayedJobStaysQueued() async throws {
        let now = Date(timeIntervalSince1970: 1_000)
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
            TestJob(value: "later"),
            options: .init(delay: 60)
        )
        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .queued)
        #expect(snapshot.availableAt == now.addingTimeInterval(60))
        #expect(await recorder.values.isEmpty)
    }

    @Test("An active uniqueness key returns the existing job")
    func uniqueDispatchReturnsExistingJob() async throws {
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(database: database, registry: registry)

        let first = try await queue.dispatch(
            TestJob(value: "first"),
            options: .init(uniqueKey: "account:1")
        )
        let second = try await queue.dispatch(
            TestJob(value: "second"),
            options: .init(uniqueKey: "account:1")
        )

        #expect(first.result == .inserted)
        #expect(second.result == .existing)
        #expect(first.id == second.id)
    }

    @Test("Retries stop after three handler attempts")
    func retriesStopAtMaximumAttempts() async throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(
            TestJob.self,
            handler: { job, _ in
                await recorder.record(job.value)
                throw TestJobError.expected
            },
            onFailure: { _, failure, _ in
                await recorder.record(failure)
            }
        )
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { now }, randomUnit: { 0 })
        )

        let receipt = try await queue.dispatch(TestJob(value: "fails", shouldFail: true))
        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .failed)
        #expect(snapshot.attempt == 3)
        #expect(await recorder.values.count == 3)
        #expect(await recorder.failures.count == 1)
    }

    @Test("Cancelling a queued job is durable")
    func cancellationIsDurable() async throws {
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(TestJob(value: "cancel"))

        try await queue.cancel(receipt.id)
        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .cancelled)
        #expect(snapshot.attempt == 0)
    }

    @Test("A paused queue does not claim work")
    func persistedPauseAndResume() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            await recorder.record(job.value)
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(TestJob(value: "paused"))

        try await queue.pause()
        try await queue.runDueJobs()
        #expect(try await queue.status(receipt.id)?.state == .queued)

        try await queue.resume()
        try await queue.runDueJobs()
        #expect(try await queue.status(receipt.id)?.state == .succeeded)
        #expect(await recorder.values == ["paused"])
    }

    @Test("Two workers cannot execute the same claim")
    func concurrentWorkersClaimOnce() async throws {
        let recorder = JobRecorder()
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DurableJobs-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let firstDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        let secondDatabase = try TestDatabaseFactory.fileBacked(at: fileURL)
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            await recorder.record(job.value)
        }
        let firstQueue = try DurableQueue(database: firstDatabase, registry: registry)
        let secondQueue = try DurableQueue(database: secondDatabase, registry: registry)
        let receipt = try await firstQueue.dispatch(TestJob(value: "once"))

        async let firstRun: Void = firstQueue.runDueJobs()
        async let secondRun: Void = secondQueue.runDueJobs()
        _ = try await (firstRun, secondRun)

        #expect(await recorder.values == ["once"])
        #expect(try await firstQueue.status(receipt.id)?.state == .succeeded)
    }

    @Test("A lane drain claims only jobs in that lane")
    func laneDrainIsIsolated() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            await recorder.record(job.value)
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let refresh = try await queue.dispatch(
            TestJob(value: "refresh"),
            options: .init(lane: .refresh)
        )
        let processing = try await queue.dispatch(
            TestJob(value: "processing"),
            options: .init(lane: .processing)
        )

        try await queue.runDueJobs(lane: .refresh)

        #expect(try await queue.status(refresh.id)?.state == .succeeded)
        #expect(try await queue.status(processing.id)?.state == .queued)
        #expect(await recorder.values == ["refresh"])

        try await queue.runDueJob(processing.id)
        #expect(try await queue.status(processing.id)?.state == .succeeded)
        #expect(await recorder.values == ["refresh", "processing"])
    }
}
