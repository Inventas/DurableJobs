import Foundation
import DurableQueuer

/// The part of a durable queue that the BackgroundTasks bridge needs.
///
/// Keeping this protocol small makes the bridge testable without a running
/// database. `DurableQueue` is accepted directly by
/// ``BackgroundTaskBridge/init(queue:scheduler:identifiers:)``.
public protocol BackgroundTaskQueue: Sendable {
    func runDueJobs() async throws
    func runDueJobs(lane: JobExecutionLane) async throws
    func runDueJob(_ id: JobID) async throws -> JobSnapshot?
    func cancelActiveJobs() async
    func cancelActiveJobs(lane: JobExecutionLane) async
    func cancelActiveJob(_ id: JobID) async
    func nextEligibleDate(lane: JobExecutionLane) async throws -> Date?
    func events() async -> AsyncStream<JobEvent>
    func status(_ id: JobID) async throws -> JobSnapshot?
}

public extension BackgroundTaskQueue {
    func runDueJobs(lane: JobExecutionLane) async throws {
        _ = lane
        try await runDueJobs()
    }

    func runDueJob(_ id: JobID) async throws -> JobSnapshot? {
        _ = id
        try await runDueJobs()
        return nil
    }

    func cancelActiveJobs(lane: JobExecutionLane) async {
        _ = lane
        await cancelActiveJobs()
    }

    func cancelActiveJob(_ id: JobID) async {
        _ = id
        await cancelActiveJobs()
    }

    func events() async -> AsyncStream<JobEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func status(_ id: JobID) async throws -> JobSnapshot? {
        _ = id
        return nil
    }
}

struct DurableQueueBackgroundTaskAdapter: BackgroundTaskQueue {
    let queue: DurableQueue

    func runDueJobs() async throws {
        try await queue.runDueJobs()
    }

    func runDueJobs(lane: JobExecutionLane) async throws {
        try await queue.runDueJobs(lane: lane)
    }

    func runDueJob(_ id: JobID) async throws -> JobSnapshot? {
        try await queue.runDueJob(id)
    }

    func cancelActiveJobs() async {
        await queue.cancelActiveJobs()
    }

    func cancelActiveJobs(lane: JobExecutionLane) async {
        await queue.cancelActiveJobs(lane: lane)
    }

    func cancelActiveJob(_ id: JobID) async {
        await queue.cancelActiveJob(id)
    }

    func nextEligibleDate(lane: JobExecutionLane) async throws -> Date? {
        try await queue.nextEligibleDate(lane: lane)
    }

    func events() async -> AsyncStream<JobEvent> {
        await queue.events()
    }

    func status(_ id: JobID) async throws -> JobSnapshot? {
        try await queue.status(id)
    }
}
