import Foundation

public struct QueueActivityBucket: Equatable, Sendable {
    public let start: Date
    public let end: Date
    public let succeeded: Int
    public let failed: Int

    public init(
        start: Date,
        end: Date,
        succeeded: Int,
        failed: Int
    ) {
        self.start = start
        self.end = end
        self.succeeded = succeeded
        self.failed = failed
    }
}
