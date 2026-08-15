import DurableJobs
import Foundation

public protocol DurableQueueDashboardDataSource: Sendable {
    func dashboardMetrics(
        since startDate: Date,
        bucketDuration: TimeInterval
    ) async throws -> QueueMetricsSnapshot

    func dashboardJobs(matching query: JobQuery) async throws -> [JobInfo]
    func dashboardStatus(_ id: JobID) async throws -> JobSnapshot?
    func dashboardEncodedPayload(for id: JobID) async throws -> EncodedJobPayload?
    func dashboardRetry(_ id: JobID) async throws
    func dashboardCancel(_ id: JobID) async throws
    func dashboardForget(_ id: JobID) async throws -> Bool
    func dashboardPause(queue: String) async throws
    func dashboardResume(queue: String) async throws
    func dashboardEvents() async -> AsyncStream<JobEvent>
}

extension DurableQueue: DurableQueueDashboardDataSource {
    public func dashboardMetrics(
        since startDate: Date,
        bucketDuration: TimeInterval
    ) async throws -> QueueMetricsSnapshot {
        try await metrics(since: startDate, bucketDuration: bucketDuration)
    }

    public func dashboardJobs(matching query: JobQuery) async throws -> [JobInfo] {
        try await jobs(matching: query)
    }

    public func dashboardStatus(_ id: JobID) async throws -> JobSnapshot? {
        try await status(id)
    }

    public func dashboardEncodedPayload(for id: JobID) async throws -> EncodedJobPayload? {
        try await encodedPayload(for: id)
    }

    public func dashboardRetry(_ id: JobID) async throws {
        try await retry(id)
    }

    public func dashboardCancel(_ id: JobID) async throws {
        try await cancel(id)
    }

    public func dashboardForget(_ id: JobID) async throws -> Bool {
        try await forget(id)
    }

    public func dashboardPause(queue: String) async throws {
        try await pause(queue: queue)
    }

    public func dashboardResume(queue: String) async throws {
        try await resume(queue: queue)
    }

    public func dashboardEvents() async -> AsyncStream<JobEvent> {
        events()
    }
}
