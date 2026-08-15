import DurableQueuer

public extension DurableQueue {
    func assertDispatched<J: DurableJob>(
        _ type: J.Type,
        tags: Set<String> = []
    ) async throws {
        let jobs = try await jobs(
            matching: JobQuery(typeIdentifier: J.typeIdentifier, tags: tags)
        )
        guard !jobs.isEmpty else {
            throw DurableQueueTestSupportError.expectedJob(
                typeIdentifier: J.typeIdentifier,
                tags: tags
            )
        }
    }

    func assertNotDispatched<J: DurableJob>(
        _ type: J.Type,
        tags: Set<String> = []
    ) async throws {
        let jobs = try await jobs(
            matching: JobQuery(typeIdentifier: J.typeIdentifier, tags: tags)
        )
        guard jobs.isEmpty else {
            throw DurableQueueTestSupportError.unexpectedJob(
                typeIdentifier: J.typeIdentifier,
                tags: tags
            )
        }
    }
}
