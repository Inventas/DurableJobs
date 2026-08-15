import DurableQueuer
import Foundation

public struct DurableQueueDashboardConfiguration: Sendable {
    public typealias PayloadFormatter = @Sendable (EncodedJobPayload) async throws -> String?

    public var refreshInterval: TimeInterval
    public var pageSize: Int
    public var payloadFormatter: PayloadFormatter?

    public init(
        refreshInterval: TimeInterval = 1,
        pageSize: Int = 100,
        payloadFormatter: PayloadFormatter? = nil
    ) {
        self.refreshInterval = max(0.25, refreshInterval)
        self.pageSize = min(1_000, max(1, pageSize))
        self.payloadFormatter = payloadFormatter
    }

    public static let `default` = Self()
}
