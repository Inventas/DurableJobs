import Foundation

public struct ThrottleExceptions: JobMiddleware {
    public let key: String
    public let maximum: Int
    public let decay: TimeInterval
    public let retryAfter: TimeInterval

    public init(
        key: String,
        maximum: Int,
        decay: TimeInterval,
        retryAfter: TimeInterval
    ) throws {
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              maximum > 0,
              decay.isFinite, decay > 0,
              retryAfter.isFinite, retryAfter >= 0 else {
            throw DurableQueueError.invalidConfiguration("invalid exception throttle")
        }
        self.key = key
        self.maximum = maximum
        self.decay = decay
        self.retryAfter = retryAfter
    }

    public func handle(
        context: JobContext,
        next: @escaping @Sendable () async throws -> Void
    ) async throws {
        do {
            try await next()
        } catch {
            if let delay = try await context.exceptionThrottleDelay(
                key: key,
                maximum: maximum,
                decay: decay,
                retryAfter: retryAfter
            ) {
                throw JobControl.release(delay: delay, consumesAttempt: true)
            }
            throw error
        }
    }
}
