import Foundation

public struct QueueHealth: Equatable, Sendable {
    public let capturedAt: Date
    public let stateCounts: JobStateCounts
    public let queues: [QueueMetrics]
    public let oldestEligibleJobAt: Date?
    public let activeLeaseCount: Int
    public let pendingFailureHookCount: Int
    public let nextEligibleDates: [JobExecutionLane: Date]

    public init(
        capturedAt: Date,
        stateCounts: JobStateCounts,
        queues: [QueueMetrics],
        oldestEligibleJobAt: Date?,
        activeLeaseCount: Int,
        pendingFailureHookCount: Int,
        nextEligibleDates: [JobExecutionLane: Date]
    ) {
        self.capturedAt = capturedAt
        self.stateCounts = stateCounts
        self.queues = queues
        self.oldestEligibleJobAt = oldestEligibleJobAt
        self.activeLeaseCount = activeLeaseCount
        self.pendingFailureHookCount = pendingFailureHookCount
        self.nextEligibleDates = nextEligibleDates
    }

    public var oldestEligibleJobAge: TimeInterval? {
        oldestEligibleJobAt.map { max(0, capturedAt.timeIntervalSince($0)) }
    }
}
