public enum JobExecutionLane: String, Codable, CaseIterable, Hashable, Sendable {
    case refresh
    case processing
    case processingNetwork
    case processingPower
    case processingNetworkAndPower

    public var requiresNetworkConnectivity: Bool {
        self == .processingNetwork || self == .processingNetworkAndPower
    }

    public var requiresExternalPower: Bool {
        self == .processingPower || self == .processingNetworkAndPower
    }
}
