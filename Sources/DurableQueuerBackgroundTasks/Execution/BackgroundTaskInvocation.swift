import Foundation

/// A launch handed to the queue bridge by a background-task scheduler.
///
/// The object owns the completion gate. This is important because an
/// expiration callback and the worker can race, while Apple's task contract
/// requires exactly one call to `setTaskCompleted`.
public final class BackgroundTaskInvocation: @unchecked Sendable {
    public typealias ExpirationHandler = @Sendable () -> Void
    public typealias ProgressHandler = @Sendable (Double) -> Void

    typealias ExpirationHandlerSetter = @Sendable (@escaping ExpirationHandler) -> Void

    public let identifier: String

    private let lock = NSLock()
    private let expirationHandlerSetter: ExpirationHandlerSetter?
    private let completionHandler: @Sendable (Bool) -> Void
    private let progressHandler: ProgressHandler?
    private var expirationHandler: ExpirationHandler?
    private var expirationRequested = false
    private var completed = false
    private var currentProgress = 0.0

    /// Creates an invocation for a platform-neutral scheduler or test.
    public convenience init(
        identifier: String,
        completionHandler: @escaping @Sendable (Bool) -> Void = { _ in },
        progressHandler: @escaping ProgressHandler = { _ in }
    ) {
        self.init(
            identifier: identifier,
            expirationHandlerSetter: nil,
            completionHandler: completionHandler,
            progressHandler: progressHandler
        )
    }

    init(
        identifier: String,
        expirationHandlerSetter: ExpirationHandlerSetter?,
        completionHandler: @escaping @Sendable (Bool) -> Void,
        progressHandler: @escaping ProgressHandler = { _ in }
    ) {
        self.identifier = identifier
        self.expirationHandlerSetter = expirationHandlerSetter
        self.completionHandler = completionHandler
        self.progressHandler = progressHandler
    }

    /// Installs the scheduler's expiration callback.
    public func setExpirationHandler(_ handler: @escaping ExpirationHandler) {
        let callImmediately: Bool
        let shouldInstall: Bool

        lock.lock()
        if completed {
            callImmediately = false
            shouldInstall = false
        } else {
            expirationHandler = handler
            callImmediately = expirationRequested
            shouldInstall = true
        }
        lock.unlock()

        if shouldInstall {
            expirationHandlerSetter?(handler)
        }
        if callImmediately {
            handler()
        }
    }

    /// Completes the invocation. Returns `true` only for the first completion.
    @discardableResult
    public func complete(success: Bool) -> Bool {
        lock.lock()
        guard !completed else {
            lock.unlock()
            return false
        }
        completed = true
        lock.unlock()

        completionHandler(success)
        return true
    }

    /// Publishes durable job progress to the scheduler's progress surface.
    /// Progress is clamped and never moves backwards.
    public func updateProgress(_ fraction: Double) {
        let bounded = min(max(fraction, 0), 1)
        let progress: Double

        lock.lock()
        guard bounded > currentProgress else {
            lock.unlock()
            return
        }
        currentProgress = bounded
        progress = bounded
        lock.unlock()

        progressHandler?(progress)
    }

    /// Simulates an expiration callback. It is useful for injected schedulers
    /// and tests; Apple's scheduler calls the installed callback itself.
    public func expire() {
        let handler: ExpirationHandler?

        lock.lock()
        guard !completed, !expirationRequested else {
            lock.unlock()
            return
        }
        expirationRequested = true
        handler = expirationHandler
        lock.unlock()

        handler?()
    }

    public var isCompleted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return completed
    }

    public var progress: Double {
        lock.lock()
        defer { lock.unlock() }
        return currentProgress
    }
}
