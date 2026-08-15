import DurableJobs

/// The five identifiers used by the BackgroundTasks bridge.
///
/// Pass an app's reverse-DNS bundle identifier as `prefix`. Each identifier
/// must also be listed in `BGTaskSchedulerPermittedIdentifiers` in the app's
/// `Info.plist`.
public struct BackgroundTaskIdentifiers: Sendable, Equatable {
    public let refresh: String
    public let processing: String
    public let processingNetwork: String
    public let processingPower: String
    public let processingNetworkAndPower: String

    public init(prefix: String) {
        let normalizedPrefix = prefix.hasSuffix(".") ? String(prefix.dropLast()) : prefix
        self.refresh = "\(normalizedPrefix).refresh"
        self.processing = "\(normalizedPrefix).processing"
        self.processingNetwork = "\(normalizedPrefix).processing-network"
        self.processingPower = "\(normalizedPrefix).processing-power"
        self.processingNetworkAndPower = "\(normalizedPrefix).processing-network-power"
    }

    public func identifier(for lane: JobExecutionLane) -> String {
        switch lane {
        case .refresh:
            refresh
        case .processing:
            processing
        case .processingNetwork:
            processingNetwork
        case .processingPower:
            processingPower
        case .processingNetworkAndPower:
            processingNetworkAndPower
        }
    }

    public var all: [String] {
        [
            refresh,
            processing,
            processingNetwork,
            processingPower,
            processingNetworkAndPower,
        ]
    }
}
