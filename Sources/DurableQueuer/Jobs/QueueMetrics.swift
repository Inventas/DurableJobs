public struct QueueMetrics: Equatable, Sendable {
    public let queue: String
    public let isPaused: Bool
    public let stateCounts: JobStateCounts

    public init(
        queue: String,
        isPaused: Bool,
        stateCounts: JobStateCounts
    ) {
        self.queue = queue
        self.isPaused = isPaused
        self.stateCounts = stateCounts
    }
}
