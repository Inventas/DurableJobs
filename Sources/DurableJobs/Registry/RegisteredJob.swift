import Foundation

struct RegisteredJob: Sendable {
    let typeIdentifier: String
    let currentVersion: Int
    let migrations: [JobPayloadMigration]
    let middleware: [any JobMiddleware]
    let handler: @Sendable (Data, Int, JobContext) async throws -> Void
    let failureHandler: (@Sendable (Data, Int, JobFailure, JobContext) async throws -> Void)?

    func migratedPayload(_ data: Data, from storedVersion: Int) throws -> Data {
        guard storedVersion <= currentVersion else {
            throw DurableQueueError.unsupportedPayloadVersion(
                type: typeIdentifier,
                stored: storedVersion,
                current: currentVersion
            )
        }

        var payload = data
        var version = storedVersion
        while version < currentVersion {
            guard let migration = migrations.first(where: { $0.fromVersion == version }) else {
                throw DurableQueueError.unsupportedPayloadVersion(
                    type: typeIdentifier,
                    stored: storedVersion,
                    current: currentVersion
                )
            }
            payload = try migration.migrate(payload)
            version = migration.toVersion
        }
        return payload
    }
}
