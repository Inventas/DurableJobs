public struct BatchSnapshot: Equatable, Sendable {
    public let id: JobBatchID
    public let stateCounts: JobStateCounts
    public let progress: Double
    public let completionJobID: JobID?

    public init(
        id: JobBatchID,
        stateCounts: JobStateCounts,
        progress: Double,
        completionJobID: JobID?
    ) {
        self.id = id
        self.stateCounts = stateCounts
        self.progress = progress
        self.completionJobID = completionJobID
    }
}
