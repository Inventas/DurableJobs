public struct JobRequirements: OptionSet, Codable, Equatable, Sendable {
    public let rawValue: UInt8

    /// Requests a BackgroundTasks processing lane that needs network access.
    /// This is a scheduling requirement, not continuous constraint monitoring.
    public static let networkConnectivity = Self(rawValue: 1 << 0)

    /// Requests a BackgroundTasks processing lane that needs external power.
    /// This is a scheduling requirement, not continuous constraint monitoring.
    public static let externalPower = Self(rawValue: 1 << 1)

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }
}
