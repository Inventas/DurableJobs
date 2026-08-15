public enum RecurringMissedRunPolicy: Codable, Equatable, Sendable {
    case latest
    case all(maximumCatchUp: Int)
}
