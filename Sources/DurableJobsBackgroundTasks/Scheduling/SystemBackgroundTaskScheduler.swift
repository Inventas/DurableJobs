#if canImport(BackgroundTasks) && (os(iOS) || targetEnvironment(macCatalyst))

@preconcurrency import BackgroundTasks
import Foundation

private final class BackgroundTaskBox: @unchecked Sendable {
    let task: BGTask

    init(_ task: BGTask) {
        self.task = task
    }
}

#if compiler(>=6.2) && os(iOS) && !targetEnvironment(macCatalyst)
@available(iOS 26.0, *)
private final class ContinuedTaskBox: @unchecked Sendable {
    let task: BGContinuedProcessingTask

    init(_ task: BGContinuedProcessingTask) {
        self.task = task
    }
}
#endif

private final class ContinuedRegistrationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers = Set<String>()

    func insert(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return identifiers.insert(identifier).inserted
    }

    func remove(_ identifier: String) {
        lock.lock()
        identifiers.remove(identifier)
        lock.unlock()
    }
}

private let continuedRegistrationStore = ContinuedRegistrationStore()

/// The Apple BackgroundTasks implementation used by default on iOS.
public struct SystemBackgroundTaskScheduler: BackgroundTaskSchedulerClient, Sendable {
    public init() {}

    public func register(
        identifier: String,
        handler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) -> Bool {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            handler(Self.makeInvocation(for: task))
        }
    }

    public func submit(_ request: BackgroundTaskRequest) async throws {
        let taskRequest: BGTaskRequest

        switch request.lane {
        case .refresh:
            let refreshRequest = BGAppRefreshTaskRequest(identifier: request.identifier)
            refreshRequest.earliestBeginDate = request.earliestBeginDate
            taskRequest = refreshRequest

        case .processing, .processingNetwork, .processingPower, .processingNetworkAndPower:
            let processingRequest = BGProcessingTaskRequest(identifier: request.identifier)
            processingRequest.earliestBeginDate = request.earliestBeginDate
            processingRequest.requiresNetworkConnectivity = request.requiresNetworkConnectivity
            processingRequest.requiresExternalPower = request.requiresExternalPower
            taskRequest = processingRequest
        }

        // Xcode 27 (Swift 6.4) is the first SDK that exposes the iOS 27
        // async importer. Older SDKs use the throwing synchronous overload.
        #if compiler(>=6.4)
        if #available(iOS 27.0, *) {
            try await BGTaskScheduler.shared.submitTaskRequest(taskRequest)
            return
        }
        #endif

        do {
            try BGTaskScheduler.shared.submit(taskRequest)
        } catch {
            throw BackgroundTaskSchedulerError.submissionFailed(error.localizedDescription)
        }
    }

    public func cancel(identifier: String) async {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
    }

    public func submitContinuedProcessing(
        _ request: ContinuedProcessingRequest,
        launchHandler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) async throws {
        #if compiler(>=6.2) && os(iOS) && !targetEnvironment(macCatalyst)
        guard #available(iOS 26.0, *) else {
            throw BackgroundTaskSchedulerError.continuedProcessingUnavailable
        }
        try submitContinuedProcessingAvailable(request, launchHandler: launchHandler)
        #else
        _ = request
        _ = launchHandler
        throw BackgroundTaskSchedulerError.continuedProcessingUnavailable
        #endif
    }

    #if compiler(>=6.2) && os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 26.0, *)
    private func submitContinuedProcessingAvailable(
        _ request: ContinuedProcessingRequest,
        launchHandler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) throws {
        let shouldRegister = continuedRegistrationStore.insert(request.identifier)
        if shouldRegister {
            let registered = BGTaskScheduler.shared.register(
                forTaskWithIdentifier: request.identifier,
                using: nil
            ) { task in
                launchHandler(Self.makeInvocation(for: task))
            }
            guard registered else {
                continuedRegistrationStore.remove(request.identifier)
                throw BackgroundTaskSchedulerError.submissionFailed(
                    "Continued-processing identifier is not permitted: \(request.identifier)"
                )
            }
        }

        let taskRequest = BGContinuedProcessingTaskRequest(
            identifier: request.identifier,
            title: request.title,
            subtitle: request.subtitle
        )
        taskRequest.strategy = request.strategy == .queue ? .queue : .fail

        do {
            try BGTaskScheduler.shared.submit(taskRequest)
        } catch {
            throw BackgroundTaskSchedulerError.submissionFailed(error.localizedDescription)
        }
    }
    #endif

    private static func makeInvocation(for task: BGTask) -> BackgroundTaskInvocation {
        let box = BackgroundTaskBox(task)

        #if compiler(>=6.2) && os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 26.0, *), let continuedTask = task as? BGContinuedProcessingTask {
            let continuedBox = ContinuedTaskBox(continuedTask)
            return BackgroundTaskInvocation(
                identifier: task.identifier,
                expirationHandlerSetter: { expirationHandler in
                    box.task.expirationHandler = expirationHandler
                },
                completionHandler: { success in
                    box.task.setTaskCompleted(success: success)
                },
                progressHandler: { fraction in
                    let progress = continuedBox.task.progress
                    let total = max(progress.totalUnitCount, 1)
                    progress.completedUnitCount = Int64((Double(total) * fraction).rounded())
                }
            )
        }
        #endif

        return BackgroundTaskInvocation(
            identifier: task.identifier,
            expirationHandlerSetter: { expirationHandler in
                box.task.expirationHandler = expirationHandler
            },
            completionHandler: { success in
                box.task.setTaskCompleted(success: success)
            }
        )
    }
}

#else

/// A no-op implementation on macOS and SDKs without BackgroundTasks.
public struct SystemBackgroundTaskScheduler: BackgroundTaskSchedulerClient, Sendable {
    public init() {}

    public func register(
        identifier: String,
        handler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) -> Bool {
        _ = identifier
        _ = handler
        return false
    }

    public func submit(_ request: BackgroundTaskRequest) async throws {
        throw BackgroundTaskSchedulerError.submissionFailed(
            "BackgroundTasks is unavailable on this platform"
        )
    }

    public func cancel(identifier: String) async {
        _ = identifier
    }

    public func submitContinuedProcessing(
        _ request: ContinuedProcessingRequest,
        launchHandler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) async throws {
        _ = request
        _ = launchHandler
        throw BackgroundTaskSchedulerError.continuedProcessingUnavailable
    }
}

#endif
