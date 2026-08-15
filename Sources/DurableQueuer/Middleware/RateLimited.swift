import Foundation

public struct RateLimited: JobMiddleware {
    public let key: String
    public let maximum: Int
    public let window: TimeInterval

    public init(key: String, maximum: Int, per window: TimeInterval) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              maximum > 0,
              window.isFinite,
              window > 0 else {
            throw DurableQueueError.invalidConfiguration("invalid durable rate limit")
        }
        self.key = key
        self.maximum = maximum
        self.window = window
    }

    public func handle(
        context: JobContext,
        next: @escaping @Sendable () async throws -> Void
    ) async throws {
        if let delay = try await context.rateLimitDelay(
            key: key,
            maximum: maximum,
            window: window
        ) {
            throw JobControl.release(delay: delay, consumesAttempt: false)
        }
        try await next()
    }
}
