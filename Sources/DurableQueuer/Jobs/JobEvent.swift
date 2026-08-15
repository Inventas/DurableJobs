import Foundation

public struct JobEvent: Sendable {
    public enum Kind: String, Sendable {
        case dispatched
        case claimed
        case progress
        case retryScheduled
        case succeeded
        case failed
        case cancelled
        case recovered
        case leaseLost
        case retried
        case forgotten
        case updated
    }

    public let jobID: JobID
    public let kind: Kind
    public let snapshot: JobSnapshot?
    public let date: Date
}
