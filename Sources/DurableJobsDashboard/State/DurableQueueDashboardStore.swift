import Combine
import DurableJobs
import Foundation

@MainActor
final class DurableQueueDashboardStore: ObservableObject {
    @Published private(set) var metrics: QueueMetricsSnapshot?
    @Published private(set) var jobs: [JobInfo] = []
    @Published private(set) var canLoadMore = false
    @Published private(set) var isLoadingJobs = false
    @Published private(set) var isPerformingOperation = false
    @Published private(set) var errorMessage: String?
    @Published var destination: DashboardDestination = .overview

    private let source: any DurableQueueDashboardDataSource
    private let configuration: DurableQueueDashboardConfiguration
    private let now: @Sendable () -> Date
    private var cachedJobs: [JobID: JobInfo] = [:]
    private var payloadSummaries: [JobID: String] = [:]
    private var loadedPayloads: Set<JobID> = []
    private var isRefreshing = false

    init(
        source: any DurableQueueDashboardDataSource,
        configuration: DurableQueueDashboardConfiguration,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.source = source
        self.configuration = configuration
        self.now = now
    }

    var hasPayloadFormatter: Bool {
        configuration.payloadFormatter != nil
    }

    func job(id: JobID) -> JobInfo? {
        cachedJobs[id]
    }

    func payloadSummary(for id: JobID) -> String? {
        payloadSummaries[id]
    }

    func hasLoadedPayload(for id: JobID) -> Bool {
        loadedPayloads.contains(id)
    }

    func dismissError() {
        errorMessage = nil
    }

    func observe() async {
        await refresh(presentErrors: true)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { [weak self] in
                await self?.pollForChanges()
            }
            group.addTask { [weak self] in
                await self?.observeEvents()
            }
            await group.waitForAll()
        }
    }

    func refresh(presentErrors: Bool = true) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            let capturedNow = now()
            metrics = try await source.dashboardMetrics(
                since: capturedNow.addingTimeInterval(-24 * 60 * 60),
                bucketDuration: 60 * 60
            )
            if destination.showsJobs {
                try await reloadVisibleJobs()
            }
            if presentErrors {
                errorMessage = nil
            }
        } catch {
            if presentErrors {
                errorMessage = String(describing: error)
            }
        }
    }

    func loadJobs(reset: Bool) async {
        guard destination.showsJobs else {
            jobs = []
            canLoadMore = false
            return
        }
        guard !isLoadingJobs else { return }

        let requestedDestination = destination
        let offset = reset ? 0 : jobs.count
        let remainingCapacity = reset ? 1_000 : max(0, 1_000 - jobs.count)
        let requestedLimit = min(configuration.pageSize, remainingCapacity)
        guard requestedLimit > 0 else {
            canLoadMore = false
            return
        }
        isLoadingJobs = true
        defer { isLoadingJobs = false }

        do {
            let page = try await source.dashboardJobs(
                matching: query(
                    for: requestedDestination,
                    limit: requestedLimit,
                    offset: offset
                )
            )
            guard destination == requestedDestination else { return }

            if reset {
                jobs = page
            } else {
                let existingIDs = Set(jobs.map(\.snapshot.id))
                jobs.append(contentsOf: page.filter {
                    !existingIDs.contains($0.snapshot.id)
                })
            }
            cache(page)
            canLoadMore = page.count == requestedLimit && jobs.count < 1_000
            errorMessage = nil
        } catch {
            guard destination == requestedDestination else { return }
            errorMessage = String(describing: error)
        }
    }

    func loadPayloadSummary(for id: JobID) async {
        guard !loadedPayloads.contains(id),
              let formatter = configuration.payloadFormatter else {
            return
        }

        do {
            if let payload = try await source.dashboardEncodedPayload(for: id),
               let summary = try await formatter(payload),
               !summary.isEmpty {
                payloadSummaries[id] = summary
            }
            loadedPayloads.insert(id)
        } catch {
            loadedPayloads.insert(id)
            errorMessage = String(describing: error)
        }
    }

    func perform(_ operation: DashboardOperation) async {
        guard !isPerformingOperation else { return }
        isPerformingOperation = true
        defer { isPerformingOperation = false }

        do {
            switch operation {
            case let .retry(id):
                try await source.dashboardRetry(id)
            case let .cancel(id):
                try await source.dashboardCancel(id)
            case let .forget(id):
                _ = try await source.dashboardForget(id)
            case let .pause(queue):
                try await source.dashboardPause(queue: queue)
            case let .resume(queue):
                try await source.dashboardResume(queue: queue)
            }

            if let jobID = operation.jobID {
                await refreshCachedJob(id: jobID)
            }
            await refresh(presentErrors: true)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func query(
        for destination: DashboardDestination,
        limit: Int,
        offset: Int
    ) -> JobQuery {
        JobQuery(
            state: destination.queryState,
            queue: destination.queryQueue,
            limit: limit,
            offset: offset
        )
    }

    private func cache(_ jobs: [JobInfo]) {
        for job in jobs {
            cachedJobs[job.snapshot.id] = job
        }
    }

    private func reloadVisibleJobs() async throws {
        let requestedDestination = destination
        let limit = max(configuration.pageSize, jobs.count)

        let refreshed = try await source.dashboardJobs(
            matching: query(
                for: requestedDestination,
                limit: limit,
                offset: 0
            )
        )
        guard destination == requestedDestination else { return }
        jobs = refreshed
        cache(refreshed)
        canLoadMore = refreshed.count == limit && refreshed.count < 1_000
    }

    private func refreshCachedJob(id: JobID) async {
        do {
            guard let snapshot = try await source.dashboardStatus(id) else {
                cachedJobs[id] = nil
                return
            }
            let tags = cachedJobs[id]?.tags ?? []
            cachedJobs[id] = JobInfo(snapshot: snapshot, tags: tags)
        } catch {
            errorMessage = String(describing: error)
        }
    }

    private func pollForChanges() async {
        while !Task.isCancelled {
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(configuration.refreshInterval * 1_000_000_000)
                )
            } catch {
                return
            }
            await refresh(presentErrors: false)
        }
    }

    private func observeEvents() async {
        let events = await source.dashboardEvents()
        for await _ in events {
            guard !Task.isCancelled else { return }
            await refresh(presentErrors: false)
        }
    }
}
