import Foundation
import Testing
import DurableJobs
import DurableJobsBackgroundTasks

@Suite("BackgroundTasks bridge")
struct BackgroundTaskBridgeTests {
    @Test("identifiers cover all five lanes")
    func identifiersCoverAllLanes() {
        let identifiers = BackgroundTaskIdentifiers(prefix: "com.example.queue")

        #expect(identifiers.refresh == "com.example.queue.refresh")
        #expect(identifiers.processing == "com.example.queue.processing")
        #expect(identifiers.processingNetwork == "com.example.queue.processing-network")
        #expect(identifiers.processingPower == "com.example.queue.processing-power")
        #expect(identifiers.processingNetworkAndPower == "com.example.queue.processing-network-power")
        #expect(Set(identifiers.all).count == 5)
    }

    @Test("requests map lane requirements")
    func requestsMapLaneConstraints() {
        let identifiers = BackgroundTaskIdentifiers(prefix: "com.example.queue")

        let refresh = BackgroundTaskRequest(
            identifier: identifiers.refresh,
            lane: .refresh,
            earliestBeginDate: nil
        )
        #expect(!refresh.requiresNetworkConnectivity)
        #expect(!refresh.requiresExternalPower)

        let network = BackgroundTaskRequest(
            identifier: identifiers.processingNetwork,
            lane: .processingNetwork,
            earliestBeginDate: nil
        )
        #expect(network.requiresNetworkConnectivity)
        #expect(!network.requiresExternalPower)

        let power = BackgroundTaskRequest(
            identifier: identifiers.processingPower,
            lane: .processingPower,
            earliestBeginDate: nil
        )
        #expect(!power.requiresNetworkConnectivity)
        #expect(power.requiresExternalPower)

        let networkAndPower = BackgroundTaskRequest(
            identifier: identifiers.processingNetworkAndPower,
            lane: .processingNetworkAndPower,
            earliestBeginDate: nil
        )
        #expect(networkAndPower.requiresNetworkConnectivity)
        #expect(networkAndPower.requiresExternalPower)
    }

    @Test("invocation completes exactly once")
    func invocationCompletesExactlyOnce() {
        let recorder = CompletionRecorder()
        let invocation = BackgroundTaskInvocation(identifier: "com.example.queue.refresh") {
            recorder.record($0)
        }

        #expect(invocation.complete(success: true))
        #expect(!invocation.complete(success: false))
        #expect(recorder.values == [true])
        #expect(invocation.isCompleted)
    }

    @Test("invocation forwards monotonic progress")
    func invocationForwardsProgress() {
        let recorder = ProgressRecorder()
        let invocation = BackgroundTaskInvocation(
            identifier: "com.example.queue.continued",
            progressHandler: { recorder.record($0) }
        )

        invocation.updateProgress(0.4)
        invocation.updateProgress(0.2)
        invocation.updateProgress(1.2)

        #expect(recorder.values == [0.4, 1])
        #expect(invocation.progress == 1)
    }

    @Test("expiration callback runs once and does not complete implicitly")
    func expirationCallbackRunsOnce() {
        let expirationCount = CompletionRecorder()
        let invocation = BackgroundTaskInvocation(identifier: "com.example.queue.processing")
        invocation.setExpirationHandler {
            expirationCount.record(true)
        }

        invocation.expire()
        invocation.expire()

        #expect(expirationCount.values == [true])
        #expect(!invocation.isCompleted)
    }

    @Test("bridge registers and schedules every lane")
    func bridgeRegistersAndSchedulesEveryLane() async {
        let identifiers = BackgroundTaskIdentifiers(prefix: "com.example.queue")
        let queue = TestQueue(date: Date(timeIntervalSince1970: 1_000))
        let scheduler = TestScheduler()
        let bridge = BackgroundTaskBridge(
            queue: queue,
            scheduler: scheduler,
            identifiers: identifiers
        )

        #expect(bridge.registerLaunchHandlers())
        #expect(bridge.registerLaunchHandlers())
        #expect(await bridge.scheduleAll())
        #expect(await scheduler.registrationCount == 5)
        #expect(await scheduler.requests.count == 5)
        #expect(await queue.nextEligibleDateCalls == 5)
    }

    @Test("expiration cancels queue work and completes unsuccessfully")
    func expirationCancelsQueueWork() async {
        let identifiers = BackgroundTaskIdentifiers(prefix: "com.example.queue")
        let queue = TestQueue(date: Date(timeIntervalSince1970: 1_000))
        let scheduler = TestScheduler()
        let bridge = BackgroundTaskBridge(
            queue: queue,
            scheduler: scheduler,
            identifiers: identifiers
        )

        #expect(bridge.registerLaunchHandlers())
        let invocation = await scheduler.launch(identifier: identifiers.refresh)
        invocation?.expire()

        for _ in 0 ..< 100 {
            if await queue.cancelActiveJobsCalls > 0 {
                break
            }
            await Task.yield()
        }

        #expect(await queue.cancelActiveJobsCalls == 1)
        #expect(await queue.cancelledLanes == [.refresh])
        #expect(await scheduler.lastCompletionValues == [false])
    }

    @Test("continued submission carries job and strategy and launches handler")
    func continuedSubmissionCarriesJobAndStrategy() async throws {
        let identifiers = BackgroundTaskIdentifiers(prefix: "com.example.queue")
        let queue = TestQueue(date: nil)
        let scheduler = TestScheduler()
        let bridge = BackgroundTaskBridge(
            queue: queue,
            scheduler: scheduler,
            identifiers: identifiers
        )
        let jobID = JobID()
        let request = ContinuedProcessingRequest(
            identifier: "com.example.queue.continued.\(jobID)",
            jobID: jobID,
            title: "Working",
            subtitle: "Queue",
            strategy: .fail
        )

        try await bridge.submitContinuedProcessing(request)

        #expect(await scheduler.continuedRequest == request)
        #expect(await scheduler.launchContinued() != nil)

        for _ in 0 ..< 100 {
            if await queue.runJobIDs == [jobID] {
                break
            }
            await Task.yield()
        }
        #expect(await queue.runJobIDs == [jobID])
    }

    @Test("a successful lane drain completes the system task successfully")
    func successfulLaneDrainCompletesSuccessfully() async {
        let identifiers = BackgroundTaskIdentifiers(prefix: "com.example.queue")
        let queue = TestQueue(date: nil)
        let scheduler = TestScheduler()
        let bridge = BackgroundTaskBridge(
            queue: queue,
            scheduler: scheduler,
            identifiers: identifiers
        )

        #expect(bridge.registerLaunchHandlers())
        _ = await scheduler.launch(identifier: identifiers.processing)
        await scheduler.waitForCompletionCount(1)

        #expect(await scheduler.lastCompletionValues == [true])
    }

    @Test("a failed lane drain completes the system task unsuccessfully")
    func failedLaneDrainCompletesUnsuccessfully() async {
        let identifiers = BackgroundTaskIdentifiers(prefix: "com.example.queue")
        let queue = TestQueue(date: nil, runShouldThrow: true)
        let scheduler = TestScheduler()
        let bridge = BackgroundTaskBridge(
            queue: queue,
            scheduler: scheduler,
            identifiers: identifiers
        )

        #expect(bridge.registerLaunchHandlers())
        _ = await scheduler.launch(identifier: identifiers.processing)
        await scheduler.waitForCompletionCount(1)

        #expect(await scheduler.lastCompletionValues == [false])
    }

    @Test(
        "continued processing uses the durable terminal state",
        arguments: [
            (JobState.succeeded, true),
            (JobState.failed, false),
            (JobState.cancelled, false),
            (JobState.queued, false),
        ]
    )
    func continuedProcessingUsesDurableJobState(
        state: JobState,
        expectedSuccess: Bool
    ) async throws {
        let identifiers = BackgroundTaskIdentifiers(prefix: "com.example.queue")
        let jobID = JobID()
        let queue = TestQueue(
            date: nil,
            runSnapshot: makeSnapshot(id: jobID, state: state)
        )
        let scheduler = TestScheduler()
        let bridge = BackgroundTaskBridge(
            queue: queue,
            scheduler: scheduler,
            identifiers: identifiers
        )
        try await bridge.submitContinuedProcessing(
            ContinuedProcessingRequest(
                identifier: "com.example.queue.continued.\(jobID)",
                jobID: jobID,
                title: "Working",
                subtitle: "Queue"
            )
        )

        _ = await scheduler.launchContinued()
        await scheduler.waitForCompletionCount(1)

        #expect(await scheduler.lastCompletionValues == [expectedSuccess])
    }
}

private func makeSnapshot(id: JobID, state: JobState) -> JobSnapshot {
    let now = Date(timeIntervalSince1970: 1_000)
    return JobSnapshot(
        id: id,
        typeIdentifier: "tests.job",
        queue: "default",
        state: state,
        lane: .processing,
        attempt: 1,
        maxAttempts: 1,
        availableAt: now,
        deadline: nil,
        progress: state == .succeeded ? 1 : 0,
        idempotencyKey: id.description,
        createdAt: now,
        updatedAt: now,
        finishedAt: now,
        lastFailure: state == .failed
            ? JobFailure(kind: .handlerError, message: "failed", occurredAt: now)
            : nil
    )
}

private final class CompletionRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Bool] = []

    func record(_ value: Bool) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var values: [Double] = []

    func record(_ value: Double) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }
}

private actor TestQueue: BackgroundTaskQueue {
    let date: Date?
    let runShouldThrow: Bool
    let runSnapshot: JobSnapshot?
    private(set) var nextEligibleDateCalls = 0
    private(set) var cancelActiveJobsCalls = 0
    private(set) var cancelledLanes: [JobExecutionLane] = []
    private(set) var runJobIDs: [JobID] = []

    init(
        date: Date?,
        runShouldThrow: Bool = false,
        runSnapshot: JobSnapshot? = nil
    ) {
        self.date = date
        self.runShouldThrow = runShouldThrow
        self.runSnapshot = runSnapshot
    }

    func runDueJobs() async throws {
        if runShouldThrow {
            throw TestBackgroundQueueError.expected
        }
    }

    func runDueJob(_ id: JobID) async throws -> JobSnapshot? {
        runJobIDs.append(id)
        if runShouldThrow {
            throw TestBackgroundQueueError.expected
        }
        return runSnapshot
    }

    func cancelActiveJobs() async {
        cancelActiveJobsCalls += 1
    }

    func cancelActiveJobs(lane: JobExecutionLane) async {
        cancelledLanes.append(lane)
        cancelActiveJobsCalls += 1
    }

    func nextEligibleDate(lane: JobExecutionLane) async throws -> Date? {
        _ = lane
        nextEligibleDateCalls += 1
        return date
    }

    func events() async -> AsyncStream<JobEvent> {
        AsyncStream { _ in }
    }

    func status(_ id: JobID) async throws -> JobSnapshot? {
        _ = id
        return nil
    }
}

private actor TestScheduler: BackgroundTaskSchedulerClient {
    private nonisolated let registrations = TestRegistrationRecorder()
    private(set) var requests: [BackgroundTaskRequest] = []
    private(set) var lastCompletionValues: [Bool] = []
    private(set) var continuedRequest: ContinuedProcessingRequest?
    private var continuedHandler: (@Sendable (BackgroundTaskInvocation) -> Void)?
    private var completionWaiters: [(Int, CheckedContinuation<Void, Never>)] = []

    var registrationCount: Int {
        registrations.count
    }

    nonisolated func register(
        identifier: String,
        handler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) -> Bool {
        registrations.register(identifier: identifier, handler: handler)
    }

    func submit(_ request: BackgroundTaskRequest) async throws {
        requests.append(request)
    }

    func cancel(identifier: String) async {
        _ = identifier
    }

    func submitContinuedProcessing(
        _ request: ContinuedProcessingRequest,
        launchHandler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) async throws {
        continuedRequest = request
        continuedHandler = launchHandler
    }

    func launch(identifier: String) -> BackgroundTaskInvocation? {
        guard let handler = registrations.handler(for: identifier) else {
            return nil
        }

        let invocation = BackgroundTaskInvocation(identifier: identifier) { [weak self] success in
            Task { await self?.recordCompletion(success) }
        }
        handler(invocation)
        return invocation
    }

    func launchContinued() -> BackgroundTaskInvocation? {
        guard let continuedHandler, let request = continuedRequest else {
            return nil
        }
        let invocation = BackgroundTaskInvocation(identifier: request.identifier) { [weak self] success in
            Task { await self?.recordCompletion(success) }
        }
        continuedHandler(invocation)
        return invocation
    }

    private func recordCompletion(_ success: Bool) {
        lastCompletionValues.append(success)
        let ready = completionWaiters.filter { lastCompletionValues.count >= $0.0 }
        completionWaiters.removeAll { lastCompletionValues.count >= $0.0 }
        for (_, continuation) in ready {
            continuation.resume()
        }
    }

    func waitForCompletionCount(_ count: Int) async {
        guard lastCompletionValues.count < count else { return }
        await withCheckedContinuation { continuation in
            completionWaiters.append((count, continuation))
        }
    }
}

private final class TestRegistrationRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var handlers: [String: @Sendable (BackgroundTaskInvocation) -> Void] = [:]

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return handlers.count
    }

    func register(
        identifier: String,
        handler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) -> Bool {
        lock.lock()
        handlers[identifier] = handler
        lock.unlock()
        return true
    }

    func handler(
        for identifier: String
    ) -> (@Sendable (BackgroundTaskInvocation) -> Void)? {
        lock.lock()
        defer { lock.unlock() }
        return handlers[identifier]
    }
}
