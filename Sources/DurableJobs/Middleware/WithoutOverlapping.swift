import Foundation

public struct WithoutOverlapping: JobMiddleware {
    public let key: String
    public let expiresAfter: TimeInterval
    public let retryAfter: TimeInterval

    public init(
        key: String,
        expiresAfter: TimeInterval = 5 * 60,
        retryAfter: TimeInterval = 5
    ) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              expiresAfter.isFinite, expiresAfter > 0,
              retryAfter.isFinite, retryAfter >= 0 else {
            throw DurableQueueError.invalidConfiguration("invalid overlap lock settings")
        }
        self.key = key
        self.expiresAfter = expiresAfter
        self.retryAfter = retryAfter
    }

    public func handle(
        context: JobContext,
        next: @escaping @Sendable () async throws -> Void
    ) async throws {
        let acquired = try await context.acquireLock(key: key, expiresAfter: expiresAfter)
        guard acquired else {
            throw JobControl.release(delay: retryAfter, consumesAttempt: false)
        }

        do {
            try await next()
            await context.releaseLock(key: key)
        } catch {
            await context.releaseLock(key: key)
            throw error
        }
    }
}
