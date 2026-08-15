import DurableQueuer
@testable import DurableQueuerDashboard
import Foundation

actor DashboardTestSource: DurableQueueDashboardDataSource {
    private(set) var queries: [JobQuery] = []
    private(set) var operations: [DashboardTestOperation] = []
    private(set) var payloadRequestCount = 0
    var shouldFailMetrics = false
    var shouldFailJobs = false

    private let jobs: [JobInfo]
    private let payload: EncodedJobPayload?
    private let metrics: QueueMetricsSnapshot

    init(
        jobs: [JobInfo] = [],
        payload: EncodedJobPayload? = nil,
        metrics: QueueMetricsSnapshot = makeDashboardTestMetrics()
    ) {
        self.jobs = jobs
        self.payload = payload
        self.metrics = metrics
    }

    func dashboardMetrics(
        since startDate: Date,
        bucketDuration: TimeInterval
    ) async throws -> QueueMetricsSnapshot {
        if shouldFailMetrics {
            throw DashboardTestError.expected
        }
        return metrics
    }

    func dashboardJobs(matching query: JobQuery) async throws -> [JobInfo] {
        queries.append(query)
        if shouldFailJobs {
            throw DashboardTestError.expected
        }
        let filtered = jobs.filter { job in
            (query.states.isEmpty || query.states.contains(job.snapshot.state))
                && (query.queues.isEmpty || query.queues.contains(job.snapshot.queue))
        }
        let start = min(query.offset, filtered.count)
        let end = min(start + query.limit, filtered.count)
        return Array(filtered[start ..< end])
    }

    func dashboardStatus(_ id: JobID) async throws -> JobSnapshot? {
        jobs.first { $0.snapshot.id == id }?.snapshot
    }

    func dashboardEncodedPayload(for id: JobID) async throws -> EncodedJobPayload? {
        payloadRequestCount += 1
        return payload
    }

    func dashboardRetry(_ id: JobID) async throws {
        operations.append(.retry(id))
    }

    func dashboardCancel(_ id: JobID) async throws {
        operations.append(.cancel(id))
    }

    func dashboardForget(_ id: JobID) async throws -> Bool {
        operations.append(.forget(id))
        return true
    }

    func dashboardPause(queue: String) async throws {
        operations.append(.pause(queue))
    }

    func dashboardResume(queue: String) async throws {
        operations.append(.resume(queue))
    }

    func dashboardEvents() async -> AsyncStream<JobEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}
