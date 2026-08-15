import Foundation

public struct RecurringScheduleSnapshot: Codable, Equatable, Sendable {
    public let id: RecurringScheduleID
    public let interval: TimeInterval
    public let flex: TimeInterval
    public let missedRunPolicy: RecurringMissedRunPolicy
    public let nextRunAt: Date
    public let isPaused: Bool

    public init(
        id: RecurringScheduleID,
        interval: TimeInterval,
        flex: TimeInterval,
        missedRunPolicy: RecurringMissedRunPolicy,
        nextRunAt: Date,
        isPaused: Bool
    ) {
        self.id = id
        self.interval = interval
        self.flex = flex
        self.missedRunPolicy = missedRunPolicy
        self.nextRunAt = nextRunAt
        self.isPaused = isPaused
    }
}
