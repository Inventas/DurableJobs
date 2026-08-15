import Foundation

/// A lock-backed clock for synchronous `DurableQueueConfiguration.now` access.
public final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    public init(now: Date = Date(timeIntervalSince1970: 0)) {
        value = now
    }

    public var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func advance(by interval: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(interval)
        lock.unlock()
    }

    public func set(_ date: Date) {
        lock.lock()
        value = date
        lock.unlock()
    }
}
