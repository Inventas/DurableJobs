public enum JobState: String, Codable, CaseIterable, Equatable, Sendable {
    case blocked
    case queued
    case running
    case succeeded
    case failed
    case cancelled

    public var isTerminal: Bool {
        self == .succeeded || self == .failed || self == .cancelled
    }
}
