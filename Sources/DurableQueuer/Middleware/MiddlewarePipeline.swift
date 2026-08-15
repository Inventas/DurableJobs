enum MiddlewarePipeline {
    static func run(
        _ middleware: [any JobMiddleware],
        context: JobContext,
        handler: @escaping @Sendable () async throws -> Void
    ) async throws {
        try await run(middleware, index: 0, context: context, handler: handler)
    }

    private static func run(
        _ middleware: [any JobMiddleware],
        index: Int,
        context: JobContext,
        handler: @escaping @Sendable () async throws -> Void
    ) async throws {
        guard index < middleware.count else {
            try await handler()
            return
        }

        try await middleware[index].handle(context: context) {
            try await run(middleware, index: index + 1, context: context, handler: handler)
        }
    }
}
