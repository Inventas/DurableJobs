import Foundation

public struct JobRegistry: Sendable {
    private var jobs: [String: RegisteredJob] = [:]

    public init() {}

    public mutating func register<J: DurableJob>(
        _ type: J.Type,
        migrations: [JobPayloadMigration] = [],
        middleware: [any JobMiddleware] = [],
        handler: @escaping @Sendable (J, JobContext) async throws -> Void,
        onFailure: (@Sendable (J, JobFailure, JobContext) async throws -> Void)? = nil
    ) throws {
        guard !J.typeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DurableQueueError.invalidJobTypeIdentifier
        }
        guard jobs[J.typeIdentifier] == nil else {
            throw DurableQueueError.duplicateJobType(J.typeIdentifier)
        }
        guard J.payloadVersion > 0 else {
            throw DurableQueueError.invalidPayloadVersion(
                type: J.typeIdentifier,
                version: J.payloadVersion
            )
        }

        let sortedMigrations = migrations.sorted { $0.fromVersion < $1.fromVersion }
        var migrationByVersion: [Int: JobPayloadMigration] = [:]
        for migration in sortedMigrations {
            guard migration.fromVersion > 0,
                  migration.toVersion == migration.fromVersion + 1,
                  migration.toVersion <= J.payloadVersion,
                  migrationByVersion[migration.fromVersion] == nil else {
                throw DurableQueueError.invalidPayloadMigration(
                    type: J.typeIdentifier,
                    from: migration.fromVersion,
                    to: migration.toVersion
                )
            }
            migrationByVersion[migration.fromVersion] = migration
        }
        for start in migrationByVersion.keys {
            var version = start
            while version < J.payloadVersion {
                guard let migration = migrationByVersion[version] else {
                    throw DurableQueueError.incompletePayloadMigrationChain(
                        type: J.typeIdentifier,
                        from: start,
                        current: J.payloadVersion
                    )
                }
                version = migration.toVersion
            }
        }
        let erasedHandler: @Sendable (Data, Int, JobContext) async throws -> Void = {
            data,
            version,
            context in
            let migrated = try RegisteredJob.migrate(
                data,
                typeIdentifier: J.typeIdentifier,
                storedVersion: version,
                currentVersion: J.payloadVersion,
                migrations: sortedMigrations
            )
            let job = try JobPayloadCodec.decoder().decode(J.self, from: migrated)
            try await handler(job, context)
        }
        let erasedFailureHandler: (@Sendable (
            Data,
            Int,
            JobFailure,
            JobContext
        ) async throws -> Void)?
        if let onFailure {
            erasedFailureHandler = { data, version, failure, context in
                let migrated = try RegisteredJob.migrate(
                    data,
                    typeIdentifier: J.typeIdentifier,
                    storedVersion: version,
                    currentVersion: J.payloadVersion,
                    migrations: sortedMigrations
                )
                let job = try JobPayloadCodec.decoder().decode(J.self, from: migrated)
                try await onFailure(job, failure, context)
            }
        } else {
            erasedFailureHandler = nil
        }

        let registration = RegisteredJob(
            typeIdentifier: J.typeIdentifier,
            currentVersion: J.payloadVersion,
            migrations: sortedMigrations,
            middleware: middleware,
            handler: erasedHandler,
            failureHandler: erasedFailureHandler
        )
        jobs[J.typeIdentifier] = registration
    }

    func job(for typeIdentifier: String) -> RegisteredJob? {
        jobs[typeIdentifier]
    }
}

extension RegisteredJob {
    static func migrate(
        _ data: Data,
        typeIdentifier: String,
        storedVersion: Int,
        currentVersion: Int,
        migrations: [JobPayloadMigration]
    ) throws -> Data {
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
