import Foundation

public struct JobFailure: Codable, Equatable, Sendable {
    public let kind: JobFailureKind
    public let message: String
    public let occurredAt: Date

    public init(kind: JobFailureKind, message: String, occurredAt: Date = Date()) {
        self.kind = kind
        self.message = message
        self.occurredAt = occurredAt
    }
}
