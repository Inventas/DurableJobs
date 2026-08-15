import Foundation

public struct QueueMetricsSnapshot: Equatable, Sendable {
    public let capturedAt: Date
    public let activitySince: Date
    public let bucketDuration: TimeInterval
    public let stateCounts: JobStateCounts
    public let queues: [QueueMetrics]
    public let activity: [QueueActivityBucket]

    public init(
        capturedAt: Date,
        activitySince: Date,
        bucketDuration: TimeInterval,
        stateCounts: JobStateCounts,
        queues: [QueueMetrics],
        activity: [QueueActivityBucket]
    ) {
        self.capturedAt = capturedAt
        self.activitySince = activitySince
        self.bucketDuration = bucketDuration
        self.stateCounts = stateCounts
        self.queues = queues
        self.activity = activity
    }
}
