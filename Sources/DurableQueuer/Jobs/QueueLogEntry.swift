import Foundation

public struct QueueLogEntry: Codable, Equatable, Sendable {
    public let level: QueueLogLevel
    public let event: String
    public let jobID: JobID?
    public let date: Date
    public let fields: [String: String]

    public init(
        level: QueueLogLevel,
        event: String,
        jobID: JobID? = nil,
        date: Date,
        fields: [String: String] = [:]
    ) {
        self.level = level
        self.event = event
        self.jobID = jobID
        self.date = date
        self.fields = fields
    }
}
