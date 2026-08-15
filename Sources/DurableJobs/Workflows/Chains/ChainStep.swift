public struct ChainStep: Sendable {
    let request: JobRequest
    let behavior: ChainDependencyBehavior

    public init<J: DurableJob>(
        _ job: J,
        options: DispatchOptions = .defaults,
        behavior: ChainDependencyBehavior = .onSuccess
    ) throws {
        request = try JobRequest(job, options: options)
        self.behavior = behavior
    }
}
