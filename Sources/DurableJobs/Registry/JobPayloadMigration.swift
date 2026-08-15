import Foundation

public struct JobPayloadMigration: Sendable {
    public let fromVersion: Int
    public let toVersion: Int
    public let migrate: @Sendable (Data) throws -> Data

    public init(
        fromVersion: Int,
        toVersion: Int,
        migrate: @escaping @Sendable (Data) throws -> Data
    ) {
        self.fromVersion = fromVersion
        self.toVersion = toVersion
        self.migrate = migrate
    }
}
