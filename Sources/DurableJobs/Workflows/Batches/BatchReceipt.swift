public struct BatchReceipt: Sendable {
    public let id: JobBatchID
    public let jobs: [DispatchReceipt]
    public let completionJob: DispatchReceipt?

    public init(
        id: JobBatchID,
        jobs: [DispatchReceipt],
        completionJob: DispatchReceipt?
    ) {
        self.id = id
        self.jobs = jobs
        self.completionJob = completionJob
    }
}
