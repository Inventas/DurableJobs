import Foundation

public struct RecurringSchedule: Codable, Equatable, Sendable {
    public var interval: TimeInterval
    public var flex: TimeInterval
    public var firstRunAt: Date?
    public var missedRunPolicy: RecurringMissedRunPolicy

    public init(
        interval: TimeInterval,
        flex: TimeInterval = 0,
        firstRunAt: Date? = nil,
        missedRunPolicy: RecurringMissedRunPolicy = .latest
    ) {
        self.interval = interval
        self.flex = flex
        self.firstRunAt = firstRunAt
        self.missedRunPolicy = missedRunPolicy
    }
}
