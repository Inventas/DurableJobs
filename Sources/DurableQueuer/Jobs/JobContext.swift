import Foundation

public struct JobContext: Sendable {
    public let id: JobID
    public let attempt: Int
    public let maxAttempts: Int
    public let queuedAt: Date
    public let idempotencyKey: String

    private let heartbeatAction: @Sendable () async throws -> Void
    private let progressAction: @Sendable (Double) async throws -> Void
    private let cancellationAction: @Sendable () async -> Bool
    private let acquireLockAction: @Sendable (String, TimeInterval) async throws -> Bool
    private let releaseLockAction: @Sendable (String) async -> Void
    private let rateLimitAction: @Sendable (String, Int, TimeInterval) async throws -> TimeInterval?
    private let exceptionThrottleAction: @Sendable (
        String, Int, TimeInterval, TimeInterval
    ) async throws -> TimeInterval?

    init(
        id: JobID,
        attempt: Int,
        maxAttempts: Int,
        queuedAt: Date,
        idempotencyKey: String,
        heartbeatAction: @escaping @Sendable () async throws -> Void,
        progressAction: @escaping @Sendable (Double) async throws -> Void,
        cancellationAction: @escaping @Sendable () async -> Bool,
        acquireLockAction: @escaping @Sendable (String, TimeInterval) async throws -> Bool,
        releaseLockAction: @escaping @Sendable (String) async -> Void,
        rateLimitAction: @escaping @Sendable (
            String, Int, TimeInterval
        ) async throws -> TimeInterval?,
        exceptionThrottleAction: @escaping @Sendable (
            String, Int, TimeInterval, TimeInterval
        ) async throws -> TimeInterval?
    ) {
        self.id = id
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.queuedAt = queuedAt
        self.idempotencyKey = idempotencyKey
        self.heartbeatAction = heartbeatAction
        self.progressAction = progressAction
        self.cancellationAction = cancellationAction
        self.acquireLockAction = acquireLockAction
        self.releaseLockAction = releaseLockAction
        self.rateLimitAction = rateLimitAction
        self.exceptionThrottleAction = exceptionThrottleAction
    }

    public func heartbeat() async throws {
        try await heartbeatAction()
    }

    public func reportProgress(_ fraction: Double) async throws {
        guard fraction.isFinite, (0 ... 1).contains(fraction) else {
            throw DurableQueueError.invalidProgress
        }
        try await progressAction(fraction)
    }

    public var isCancellationRequested: Bool {
        get async { await cancellationAction() }
    }

    public func release(after delay: TimeInterval) throws -> Never {
        guard delay.isFinite, delay >= 0 else {
            throw DurableQueueError.invalidDispatchOptions(
                "release delay must be finite and nonnegative"
            )
        }
        throw JobControl.release(delay: delay, consumesAttempt: true)
    }

    public func failPermanently(_ message: String) throws -> Never {
        throw JobControl.permanentFailure(message: message)
    }

    func acquireLock(key: String, expiresAfter: TimeInterval) async throws -> Bool {
        try await acquireLockAction(key, expiresAfter)
    }

    func releaseLock(key: String) async {
        await releaseLockAction(key)
    }

    func rateLimitDelay(key: String, maximum: Int, window: TimeInterval) async throws -> TimeInterval? {
        try await rateLimitAction(key, maximum, window)
    }

    func exceptionThrottleDelay(
        key: String,
        maximum: Int,
        decay: TimeInterval,
        retryAfter: TimeInterval
    ) async throws -> TimeInterval? {
        try await exceptionThrottleAction(key, maximum, decay, retryAfter)
    }
}
