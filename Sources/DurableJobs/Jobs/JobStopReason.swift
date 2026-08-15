public enum JobStopReason: String, Codable, Equatable, Sendable {
    case userCancelled
    case replaced
    case backgroundTaskExpired
    case dependencyFailed
    case dependencyCancelled
    case batchCancelled
}
