import Foundation
import DurableQueuer

/// Connects a ``DurableQueue`` to five static BackgroundTasks lanes.
public actor BackgroundTaskBridge {
    public static let lanes: [JobExecutionLane] = [
        .refresh,
        .processing,
        .processingNetwork,
        .processingPower,
        .processingNetworkAndPower,
    ]

    public let identifiers: BackgroundTaskIdentifiers

    private let queue: any BackgroundTaskQueue
    private let scheduler: any BackgroundTaskSchedulerClient
    private let appRefreshTimeLimit: TimeInterval
    private nonisolated let registrationStore = BackgroundTaskRegistrationStore()

    /// Creates a bridge with an injectable queue and scheduler.
    public init(
        queue: any BackgroundTaskQueue,
        scheduler: any BackgroundTaskSchedulerClient,
        identifiers: BackgroundTaskIdentifiers,
        appRefreshTimeLimit: TimeInterval = 20
    ) {
        self.queue = queue
        self.scheduler = scheduler
        self.identifiers = identifiers
        self.appRefreshTimeLimit = appRefreshTimeLimit.isFinite
            ? max(0, appRefreshTimeLimit)
            : 20
    }

    /// Creates a bridge for the package's durable queue and the system
    /// scheduler.
    public init(
        queue: DurableQueue,
        prefix: String,
        scheduler: any BackgroundTaskSchedulerClient = SystemBackgroundTaskScheduler(),
        appRefreshTimeLimit: TimeInterval = 20
    ) {
        self.init(
            queue: DurableQueueBackgroundTaskAdapter(queue: queue),
            scheduler: scheduler,
            identifiers: BackgroundTaskIdentifiers(prefix: prefix),
            appRefreshTimeLimit: appRefreshTimeLimit
        )
    }

    /// Attaches this bridge to a durable queue. The queue then reconciles
    /// BackgroundTasks requests after durable scheduling state changes.
    public func attach(to queue: DurableQueue) async {
        await queue.attachSchedulingCoordinator(self)
    }

    /// Registers each launch handler. Registration is idempotent for the
    /// lifetime of this bridge because Apple's scheduler rejects duplicates.
    @discardableResult
    public nonisolated func registerLaunchHandlers() -> Bool {
        var allRegistered = true

        for lane in Self.lanes {
            let identifier = identifiers.identifier(for: lane)
            guard registrationStore.reserve(identifier) else {
                continue
            }

            let registered = scheduler.register(identifier: identifier) { [weak self] invocation in
                guard let self else {
                    invocation.complete(success: false)
                    return
                }

                Task {
                    await self.handle(invocation, lane: lane)
                }
            }

            if !registered {
                registrationStore.release(identifier)
                allRegistered = false
            }
        }

        return allRegistered
    }

    /// Schedules all lanes that currently have an eligible job.
    @discardableResult
    public func scheduleAll() async -> Bool {
        var allScheduled = true
        for lane in Self.lanes {
            allScheduled = await schedule(lane: lane) && allScheduled
        }
        return allScheduled
    }

    /// Schedules one lane at its earliest eligible date. If no job is ready,
    /// any old request for that lane is cancelled.
    @discardableResult
    public func schedule(lane: JobExecutionLane) async -> Bool {
        let identifier = identifiers.identifier(for: lane)
        let earliestBeginDate: Date?

        do {
            earliestBeginDate = try await queue.nextEligibleDate(lane: lane)
        } catch {
            await scheduler.cancel(identifier: identifier)
            return false
        }

        guard let earliestBeginDate else {
            await scheduler.cancel(identifier: identifier)
            return true
        }

        do {
            try await scheduler.submit(
                BackgroundTaskRequest(
                    identifier: identifier,
                    lane: lane,
                    earliestBeginDate: earliestBeginDate
                )
            )
            return true
        } catch {
            return false
        }
    }

    /// Builds the platform-neutral request used by an injected scheduler.
    public func request(
        for lane: JobExecutionLane,
        earliestBeginDate: Date?
    ) -> BackgroundTaskRequest {
        BackgroundTaskRequest(
            identifier: identifiers.identifier(for: lane),
            lane: lane,
            earliestBeginDate: earliestBeginDate
        )
    }

    /// Submits an iOS 26 continued-processing request when the selected
    /// scheduler supports it. The default scheduler reports an explicit
    /// unavailable error on older platforms.
    public func submitContinuedProcessing(_ request: ContinuedProcessingRequest) async throws {
        try await scheduler.submitContinuedProcessing(request) { [weak self] invocation in
            guard let self else {
                invocation.complete(success: false)
                return
            }

            Task {
                await self.handleContinuedProcessing(invocation, request: request)
            }
        }
    }

    private func handle(_ invocation: BackgroundTaskInvocation, lane: JobExecutionLane) {
        let cancellation = BackgroundTaskCancellationController()
        let queue = self.queue
        let timeLimit = appRefreshTimeLimit

        invocation.setExpirationHandler { [weak self, queue] in
            cancellation.cancel()
            let didComplete = invocation.complete(success: false)

            Task {
                await queue.cancelActiveJobs(lane: lane)
                if didComplete, let self {
                    _ = await self.schedule(lane: lane)
                }
            }
        }

        let refreshDeadline = lane == .refresh ? Task {
            if timeLimit > 0 {
                try? await Task.sleep(
                    nanoseconds: UInt64(timeLimit * 1_000_000_000)
                )
            }
            guard !Task.isCancelled else { return }
            invocation.expire()
        } : nil

        let worker = Task { [weak self, queue] in
            let succeeded: Bool
            do {
                try await queue.runDueJobs(lane: lane)
                succeeded = !Task.isCancelled
            } catch {
                succeeded = false
            }

            refreshDeadline?.cancel()
            if invocation.complete(success: succeeded), let self {
                _ = await self.schedule(lane: lane)
            }
        }

        cancellation.install {
            worker.cancel()
            refreshDeadline?.cancel()
        }
    }

    private func handleContinuedProcessing(
        _ invocation: BackgroundTaskInvocation,
        request: ContinuedProcessingRequest
    ) {
        let cancellation = BackgroundTaskCancellationController()
        let queue = self.queue

        let progressTask = Task { [queue] in
            let events = await queue.events()
            if let snapshot = try? await queue.status(request.jobID) {
                invocation.updateProgress(snapshot.progress)
            }

            for await event in events {
                guard event.jobID == request.jobID else { continue }
                invocation.updateProgress(event.snapshot?.progress ?? 0)
                let isTerminal: Bool
                switch event.kind {
                case .succeeded, .failed, .cancelled:
                    isTerminal = true
                default:
                    isTerminal = false
                }
                if isTerminal {
                    break
                }
            }
        }

        invocation.setExpirationHandler { [weak self, queue] in
            cancellation.cancel()
            let didComplete = invocation.complete(success: false)
            progressTask.cancel()

            Task {
                await queue.cancelActiveJob(request.jobID)
                if didComplete, let self {
                    _ = await self.scheduleAll()
                }
            }
        }

        let worker = Task { [weak self, queue] in
            let snapshot: JobSnapshot?
            do {
                snapshot = try await queue.runDueJob(request.jobID)
            } catch {
                snapshot = nil
            }
            if let snapshot {
                invocation.updateProgress(snapshot.progress)
            }
            progressTask.cancel()

            let succeeded = !Task.isCancelled && snapshot?.state == .succeeded
            if invocation.complete(success: succeeded), let self {
                _ = await self.scheduleAll()
            }
        }

        cancellation.install {
            worker.cancel()
        }
    }
}

extension BackgroundTaskBridge: QueueSchedulingCoordinator {
    public func reconcile() async {
        _ = await scheduleAll()
    }
}
