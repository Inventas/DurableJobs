import DurableJobs
import GRDB
import XCTest
@testable import DurableJobsDashboardSample

final class DashboardSampleQueueTests: XCTestCase {
    func testSampleJobsProduceCompletedFailedAndPendingStates() async throws {
        let database = try DatabaseQueue()
        let registry = try SampleJobRegistryFactory.make()
        let queue = try DurableQueue(database: database, registry: registry)
        let tag = SampleConstants.tag

        let completed = try await queue.dispatch(
            SampleJob(name: "Completed", duration: 0, shouldFail: false),
            options: DispatchOptions(maxAttempts: 1, tags: [tag])
        )
        let failed = try await queue.dispatch(
            SampleJob(name: "Failed", duration: 0, shouldFail: true),
            options: DispatchOptions(maxAttempts: 1, tags: [tag])
        )
        let pending = try await queue.dispatch(
            SampleJob(name: "Pending", duration: 0, shouldFail: false),
            options: DispatchOptions(delay: 3_600, maxAttempts: 1, tags: [tag])
        )

        try await queue.runDueJobs()

        let completedState = try await queue.status(completed.id)?.state
        let failedState = try await queue.status(failed.id)?.state
        let pendingState = try await queue.status(pending.id)?.state
        XCTAssertEqual(completedState, .succeeded)
        XCTAssertEqual(failedState, .failed)
        XCTAssertEqual(pendingState, .queued)

        let taggedJobs = try await queue.jobs(matching: JobQuery(tag: tag))
        XCTAssertEqual(taggedJobs.count, 3)
    }
}
