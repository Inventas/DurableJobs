import Foundation

public struct JobCursor: Codable, Equatable, Sendable {
    public let createdAt: Date
    public let id: JobID

    public init(createdAt: Date, id: JobID) {
        self.createdAt = createdAt
        self.id = id
    }
}
