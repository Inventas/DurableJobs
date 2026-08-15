import Foundation

public struct JobAttempt: Codable, Equatable, Sendable {
    public let number: Int
    public let startedAt: Date
    public let finishedAt: Date?
    public let outcome: String?
    public let message: String?

    public init(
        number: Int,
        startedAt: Date,
        finishedAt: Date?,
        outcome: String?,
        message: String?
    ) {
        self.number = number
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.message = message
    }
}
