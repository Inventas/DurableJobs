import DurableQueuer
import Foundation

func makeDashboardTestJob(
    id: JobID = JobID(),
    state: JobState,
    queue: String = "default",
    createdAt: Date = Date(timeIntervalSince1970: 10_000)
) -> JobInfo {
    JobInfo(
        snapshot: JobSnapshot(
            id: id,
            typeIdentifier: "test.job",
            queue: queue,
            state: state,
            lane: .processing,
            attempt: state == .queued ? 0 : 1,
            maxAttempts: 3,
            availableAt: createdAt,
            deadline: nil,
            progress: state == .succeeded ? 1 : 0,
            idempotencyKey: id.description,
            createdAt: createdAt,
            updatedAt: createdAt,
            finishedAt: state == .succeeded || state == .failed || state == .cancelled
                ? createdAt
                : nil,
            lastFailure: nil
        ),
        tags: []
    )
}

func makeDashboardTestMetrics(
    capturedAt: Date = Date(timeIntervalSince1970: 10_000)
) -> QueueMetricsSnapshot {
    QueueMetricsSnapshot(
        capturedAt: capturedAt,
        activitySince: capturedAt.addingTimeInterval(-24 * 60 * 60),
        bucketDuration: 60 * 60,
        stateCounts: JobStateCounts(),
        queues: [],
        activity: []
    )
}
