public struct ChainReceipt: Sendable {
    public let id: JobChainID
    public let jobs: [DispatchReceipt]

    public init(id: JobChainID, jobs: [DispatchReceipt]) {
        self.id = id
        self.jobs = jobs
    }
}
