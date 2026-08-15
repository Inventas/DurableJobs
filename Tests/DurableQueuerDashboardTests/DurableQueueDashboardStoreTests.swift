import DurableQueuer
@testable import DurableQueuerDashboard
import Foundation
import Testing

@Suite("Durable queue dashboard store")
struct DurableQueueDashboardStoreTests {
    @Test("State filters and bounded pages are sent to the data source")
    @MainActor
    func filtersAndPagesJobs() async throws {
        let first = makeDashboardTestJob(state: .failed)
        let second = makeDashboardTestJob(state: .failed)
        let third = makeDashboardTestJob(state: .failed)
        let source = DashboardTestSource(
            jobs: [
                first,
                makeDashboardTestJob(state: .succeeded),
                second,
                third,
            ]
        )
        let store = DurableQueueDashboardStore(
            source: source,
            configuration: .init(pageSize: 2)
        )
        store.destination = .failed

        await store.loadJobs(reset: true)
        #expect(store.jobs.map(\.snapshot.id) == [
            first.snapshot.id,
            second.snapshot.id,
        ])
        #expect(store.canLoadMore)

        await store.loadJobs(reset: false)
        #expect(store.jobs.map(\.snapshot.id) == [
            first.snapshot.id,
            second.snapshot.id,
            third.snapshot.id,
        ])
        #expect(!store.canLoadMore)

        let queries = await source.queries
        #expect(queries.count == 2)
        #expect(queries[0].state == .failed)
        #expect(queries[0].limit == 2)
        #expect(queries[0].offset == 0)
        #expect(queries[1].offset == 2)
    }

    @Test("Refresh failures remain visible")
    @MainActor
    func reportsRefreshFailures() async {
        let source = DashboardTestSource()
        await source.setShouldFailMetrics(true)
        let store = DurableQueueDashboardStore(
            source: source,
            configuration: .default
        )

        await store.refresh()

        #expect(store.errorMessage?.contains("expected") == true)
    }

    @Test("Every approved operation is forwarded once")
    @MainActor
    func forwardsOperations() async {
        let job = makeDashboardTestJob(state: .failed)
        let source = DashboardTestSource(jobs: [job])
        let store = DurableQueueDashboardStore(
            source: source,
            configuration: .default
        )

        await store.perform(.retry(job.snapshot.id))
        await store.perform(.cancel(job.snapshot.id))
        await store.perform(.forget(job.snapshot.id))
        await store.perform(.pause("sync"))
        await store.perform(.resume("sync"))

        #expect(await source.operations == [
            .retry(job.snapshot.id),
            .cancel(job.snapshot.id),
            .forget(job.snapshot.id),
            .pause("sync"),
            .resume("sync"),
        ])
    }

    @Test("Payload formatting is lazy and cached")
    @MainActor
    func formatsPayloadOnce() async {
        let payload = EncodedJobPayload(
            typeIdentifier: "test.job",
            version: 1,
            data: Data("secret".utf8)
        )
        let source = DashboardTestSource(payload: payload)
        let store = DurableQueueDashboardStore(
            source: source,
            configuration: .init(payloadFormatter: { payload in
                "\(payload.typeIdentifier) v\(payload.version), redacted"
            })
        )
        let id = JobID()

        await store.loadPayloadSummary(for: id)
        await store.loadPayloadSummary(for: id)

        #expect(store.payloadSummary(for: id) == "test.job v1, redacted")
        #expect(await source.payloadRequestCount == 1)
    }
}

private extension DashboardTestSource {
    func setShouldFailMetrics(_ value: Bool) {
        shouldFailMetrics = value
    }
}
