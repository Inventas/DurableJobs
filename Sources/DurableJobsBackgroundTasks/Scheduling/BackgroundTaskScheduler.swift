import Foundation
import DurableJobs

/// A request independent of Apple's BackgroundTasks classes.
public struct BackgroundTaskRequest: Sendable {
    public let identifier: String
    public let lane: JobExecutionLane
    public let earliestBeginDate: Date?
    public let requiresNetworkConnectivity: Bool
    public let requiresExternalPower: Bool

    public init(
        identifier: String,
        lane: JobExecutionLane,
        earliestBeginDate: Date?
    ) {
        self.identifier = identifier
        self.lane = lane
        self.earliestBeginDate = earliestBeginDate

        switch lane {
        case .refresh, .processing:
            self.requiresNetworkConnectivity = false
            self.requiresExternalPower = false
        case .processingNetwork:
            self.requiresNetworkConnectivity = true
            self.requiresExternalPower = false
        case .processingPower:
            self.requiresNetworkConnectivity = false
            self.requiresExternalPower = true
        case .processingNetworkAndPower:
            self.requiresNetworkConnectivity = true
            self.requiresExternalPower = true
        }
    }
}

public enum ContinuedProcessingStrategy: String, Codable, Sendable, Equatable {
    case queue
    case fail
}

/// A request for the iOS 26 continued-processing API.
public struct ContinuedProcessingRequest: Sendable, Equatable {
    public let identifier: String
    public let jobID: JobID
    public let title: String
    public let subtitle: String
    public let strategy: ContinuedProcessingStrategy

    public init(
        identifier: String,
        jobID: JobID,
        title: String,
        subtitle: String,
        strategy: ContinuedProcessingStrategy = .queue
    ) {
        self.identifier = identifier
        self.jobID = jobID
        self.title = title
        self.subtitle = subtitle
        self.strategy = strategy
    }
}

public enum BackgroundTaskSchedulerError: Error, Sendable, Equatable {
    case continuedProcessingUnavailable
    case submissionFailed(String)
}

/// Injectable scheduler boundary used by ``BackgroundTaskBridge``.
public protocol BackgroundTaskSchedulerClient: Sendable {
    func register(
        identifier: String,
        handler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) -> Bool

    func submit(_ request: BackgroundTaskRequest) async throws
    func cancel(identifier: String) async
    func submitContinuedProcessing(
        _ request: ContinuedProcessingRequest,
        launchHandler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) async throws
}

public extension BackgroundTaskSchedulerClient {
    /// Schedulers that do not support iOS 26 continued processing report the
    /// capability through this default implementation.
    func submitContinuedProcessing(
        _ request: ContinuedProcessingRequest,
        launchHandler: @escaping @Sendable (BackgroundTaskInvocation) -> Void
    ) async throws {
        _ = request
        _ = launchHandler
        throw BackgroundTaskSchedulerError.continuedProcessingUnavailable
    }
}
