import Combine
import DurableQueuer
import DurableQueuerDashboard
import Foundation
import GRDB

@MainActor
final class DashboardSampleModel: ObservableObject {
    @Published private(set) var queue: DurableQueue?
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var errorMessage: String?

    let databaseURL: URL?
    let dashboardConfiguration = DurableQueueDashboardConfiguration(
        payloadFormatter: { payload in
            try SamplePayloadFormatter.format(payload)
        }
    )

    init() {
        do {
            let directory = try Self.makeApplicationSupportDirectory()
            let databaseURL = directory.appendingPathComponent("sample.sqlite")
            let database = try DatabasePool(path: databaseURL.path)
            let registry = try SampleJobRegistryFactory.make()
            let queue = try DurableQueue(database: database, registry: registry)

            self.databaseURL = databaseURL
            self.queue = queue
        } catch {
            self.databaseURL = nil
            self.errorMessage = error.localizedDescription
        }
    }

    func seedIfNeeded() async {
        guard let queue else { return }

        do {
            let existingJobs = try await queue.jobs(
                matching: JobQuery(tag: SampleConstants.tag, limit: 1)
            )
            if existingJobs.isEmpty {
                await seedExamples()
            }
        } catch {
            report(error)
        }
    }

    func seedExamples() async {
        guard let queue else { return }

        do {
            _ = try await queue.dispatch(
                SampleJob(name: uniqueName("Completed"), duration: 0.4, shouldFail: false),
                options: options()
            )
            _ = try await queue.dispatch(
                SampleJob(name: uniqueName("Failed"), duration: 0.4, shouldFail: true),
                options: options()
            )
            _ = try await queue.dispatch(
                SampleJob(name: uniqueName("Pending"), duration: 2, shouldFail: false),
                options: options(delay: 3_600)
            )
            try await drainQueue()
            statusMessage = "Created completed, failed, and pending sample jobs."
        } catch {
            report(error)
        }
    }

    func addPendingJob() async {
        await dispatch(
            SampleJob(name: uniqueName("Pending"), duration: 1, shouldFail: false),
            message: "Added a pending job."
        )
    }

    func addFailingJob() async {
        await dispatch(
            SampleJob(name: uniqueName("Failure"), duration: 0.7, shouldFail: true),
            message: "Added a failing job. Run the queue to execute it."
        )
    }

    func addDelayedJob() async {
        await dispatch(
            SampleJob(name: uniqueName("Delayed"), duration: 1, shouldFail: false),
            delay: 60,
            message: "Added a job with a one-minute delay."
        )
    }

    func addLongRunningJob() async {
        await dispatch(
            SampleJob(name: uniqueName("Long running"), duration: 15, shouldFail: false),
            message: "Added a 15-second job. Run the queue, then cancel it in the dashboard."
        )
    }

    func runQueue() async {
        await runQueue(showSuccessMessage: true)
    }

    func dismissMessage() {
        statusMessage = nil
        errorMessage = nil
    }

    private func dispatch(
        _ job: SampleJob,
        delay: TimeInterval? = nil,
        message: String
    ) async {
        guard let queue else { return }

        do {
            _ = try await queue.dispatch(job, options: options(delay: delay))
            statusMessage = message
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    private func runQueue(showSuccessMessage: Bool) async {
        guard queue != nil, !isRunning else { return }

        isRunning = true
        defer { isRunning = false }

        do {
            try await drainQueue()
            if showSuccessMessage {
                statusMessage = "Finished all due jobs."
            }
            errorMessage = nil
        } catch {
            report(error)
        }
    }

    private func drainQueue() async throws {
        guard let queue else { return }
        try await queue.runDueJobs()
    }

    private func options(delay: TimeInterval? = nil) -> DispatchOptions {
        DispatchOptions(
            delay: delay,
            maxAttempts: 1,
            tags: [SampleConstants.tag]
        )
    }

    private func uniqueName(_ prefix: String) -> String {
        "\(prefix) \(UUID().uuidString.prefix(6))"
    }

    private func report(_ error: Error) {
        errorMessage = error.localizedDescription
        statusMessage = nil
    }

    private static func makeApplicationSupportDirectory() throws -> URL {
        let baseURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = baseURL.appendingPathComponent(
            "DurableQueuerDashboardSample",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
