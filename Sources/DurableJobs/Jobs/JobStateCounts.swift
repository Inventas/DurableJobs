public struct JobStateCounts: Equatable, Sendable {
    public let blocked: Int
    public let queued: Int
    public let running: Int
    public let succeeded: Int
    public let failed: Int
    public let cancelled: Int

    public init(
        blocked: Int = 0,
        queued: Int = 0,
        running: Int = 0,
        succeeded: Int = 0,
        failed: Int = 0,
        cancelled: Int = 0
    ) {
        self.blocked = blocked
        self.queued = queued
        self.running = running
        self.succeeded = succeeded
        self.failed = failed
        self.cancelled = cancelled
    }

    public var total: Int {
        blocked + queued + running + succeeded + failed + cancelled
    }

    public func count(for state: JobState) -> Int {
        switch state {
        case .blocked:
            blocked
        case .queued:
            queued
        case .running:
            running
        case .succeeded:
            succeeded
        case .failed:
            failed
        case .cancelled:
            cancelled
        }
    }
}
