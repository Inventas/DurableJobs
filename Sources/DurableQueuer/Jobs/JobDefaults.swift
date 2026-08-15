import Foundation

public struct JobDefaults: Codable, Equatable, Sendable {
    public var queue: String
    public var priority: Int
    public var maxAttempts: Int
    public var retryPolicy: RetryPolicy
    public var timeout: TimeInterval?
    public var requirements: JobRequirements
    public var lane: JobExecutionLane

    public init(
        queue: String = "default",
        priority: Int = 0,
        maxAttempts: Int = 3,
        retryPolicy: RetryPolicy = .default,
        timeout: TimeInterval? = nil,
        requirements: JobRequirements = [],
        lane: JobExecutionLane = .processing
    ) {
        self.queue = queue
        self.priority = priority
        self.maxAttempts = maxAttempts
        self.retryPolicy = retryPolicy
        self.timeout = timeout
        self.requirements = requirements
        self.lane = lane
    }
}
