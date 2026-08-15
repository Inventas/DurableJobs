public struct DispatchReceipt: Sendable, Equatable {
    public enum Result: Sendable, Equatable {
        case inserted
        case existing
        case replaced
        case appended
    }

    public let id: JobID
    public let result: Result
    public let replacedJobID: JobID?
    public let replacedJobIDs: [JobID]

    public init(
        id: JobID,
        result: Result,
        replacedJobID: JobID? = nil,
        replacedJobIDs: [JobID] = []
    ) {
        self.id = id
        self.result = result
        self.replacedJobID = replacedJobID
        self.replacedJobIDs = replacedJobIDs.isEmpty
            ? replacedJobID.map { [$0] } ?? []
            : replacedJobIDs
    }
}
