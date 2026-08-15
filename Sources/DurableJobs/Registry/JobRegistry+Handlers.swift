import Foundation

public extension JobRegistry {
    mutating func register<Handler: DurableJobHandler>(
        _ handler: Handler,
        migrations: [JobPayloadMigration] = [],
        middleware: [any JobMiddleware] = [],
        onFailure: (@Sendable (Handler.Job, JobFailure, JobContext) async throws -> Void)? = nil
    ) throws {
        try register(
            Handler.Job.self,
            migrations: migrations,
            middleware: middleware,
            handler: { job, context in
                try await handler.handle(job: job, context: context)
            },
            onFailure: onFailure
        )
    }
}
