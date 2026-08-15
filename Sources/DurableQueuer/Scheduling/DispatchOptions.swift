import Foundation

public struct DispatchOptions: Codable, Sendable {
    public var queue: String?
    public var priority: Int?
    public var delay: TimeInterval?
    public var availableAt: Date?
    public var deadline: Date?
    public var timeout: TimeInterval?
    public var maxAttempts: Int?
    public var retryPolicy: RetryPolicy?
    public var requirements: JobRequirements?
    public var lane: JobExecutionLane?
    public var uniqueKey: String?
    public var uniquePolicy: UniqueJobPolicy
    public var idempotencyKey: String?
    public var tags: Set<String>

    public init(
        queue: String? = nil,
        priority: Int? = nil,
        delay: TimeInterval? = nil,
        availableAt: Date? = nil,
        deadline: Date? = nil,
        timeout: TimeInterval? = nil,
        maxAttempts: Int? = nil,
        retryPolicy: RetryPolicy? = nil,
        requirements: JobRequirements? = nil,
        lane: JobExecutionLane? = nil,
        uniqueKey: String? = nil,
        uniquePolicy: UniqueJobPolicy = .keep,
        idempotencyKey: String? = nil,
        tags: Set<String> = []
    ) {
        self.queue = queue
        self.priority = priority
        self.delay = delay
        self.availableAt = availableAt
        self.deadline = deadline
        self.timeout = timeout
        self.maxAttempts = maxAttempts
        self.retryPolicy = retryPolicy
        self.requirements = requirements
        self.lane = lane
        self.uniqueKey = uniqueKey
        self.uniquePolicy = uniquePolicy
        self.idempotencyKey = idempotencyKey
        self.tags = tags
    }

    public static let defaults = Self()
}
