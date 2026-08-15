public protocol JobMiddleware: Sendable {
    func handle(
        context: JobContext,
        next: @escaping @Sendable () async throws -> Void
    ) async throws
}
