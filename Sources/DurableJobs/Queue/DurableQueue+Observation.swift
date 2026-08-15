import Foundation

extension DurableQueue {
    /// Observes durable state by polling SQLite. This sees writes from other
    /// queue instances and emits only changed values.
    public func observe(_ id: JobID) -> AsyncThrowingStream<JobSnapshot?, any Error> {
        let interval = configuration.observationPollingInterval
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                var previous: JobSnapshot??
                do {
                    while !Task.isCancelled {
                        let value = try await self.status(id)
                        if previous == nil || previous! != value {
                            continuation.yield(value)
                            previous = value
                        }
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Observes a durable query. The initial result is followed by coalesced
    /// changes from all queue instances that use the same SQLite database.
    public func observe(
        matching query: JobQuery
    ) -> AsyncThrowingStream<[JobInfo], any Error> {
        let interval = configuration.observationPollingInterval
        return AsyncThrowingStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                var previous: [JobInfo]?
                do {
                    while !Task.isCancelled {
                        let value = try await self.jobs(matching: query)
                        if previous != value {
                            continuation.yield(value)
                            previous = value
                        }
                        try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
