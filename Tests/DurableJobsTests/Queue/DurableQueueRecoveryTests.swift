import DurableJobs
import DurableJobsTestSupport
import Foundation
import GRDB
import Testing

@Suite("Durable queue recovery")
struct DurableQueueRecoveryTests {
    @Test("An expired lease is recovered and consumes its prior attempt")
    func expiredLeaseRecovery() async throws {
        let now = Date(timeIntervalSince1970: 10_000)
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { job, _ in
            await recorder.record(job.value)
        }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { now }, randomUnit: { 0 })
        )
        let receipt = try await queue.dispatch(TestJob(value: "recovered"))
        try await database.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET state = 'running', attempt_count = 1,
                        lease_token = 'stale', lease_expires_at = 0
                    WHERE id = ?
                    """,
                arguments: [receipt.id.description]
            )
        }

        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .succeeded)
        #expect(snapshot.attempt == 2)
        #expect(await recorder.values == ["recovered"])
    }

    @Test("A deadline that passed before claim is terminal")
    func expiredDeadlineFailsWithoutAttempt() async throws {
        let now = Date(timeIntervalSince1970: 20_000)
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { now })
        )
        let receipt = try await queue.dispatch(
            TestJob(value: "late"),
            options: .init(deadline: now)
        )

        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .failed)
        #expect(snapshot.attempt == 0)
        #expect(snapshot.lastFailure?.kind == .deadlineExceeded)
    }

    @Test("A middleware lock releases the job without consuming an attempt")
    func overlapLockDoesNotConsumeAttempt() async throws {
        let now = Date(timeIntervalSince1970: 30_000)
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(
            TestJob.self,
            middleware: [try WithoutOverlapping(key: "shared", retryAfter: 60)]
        ) { _, _ in }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { now })
        )
        let receipt = try await queue.dispatch(TestJob(value: "locked"))
        try await database.write { db in
            let nowMilliseconds = Int64(now.timeIntervalSince1970 * 1_000)
            try db.execute(
                sql: """
                    INSERT INTO durable_queue_locks
                    (lock_key, owner_token, expires_at, updated_at)
                    VALUES ('shared', 'other', ?, ?)
                    """,
                arguments: [nowMilliseconds + 120_000, nowMilliseconds]
            )
        }

        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .queued)
        #expect(snapshot.attempt == 0)
        #expect(snapshot.availableAt == now.addingTimeInterval(60))
    }

    @Test("A registered migration decodes an older payload")
    func payloadMigration() async throws {
        let recorder = JobRecorder()
        let database = try TestDatabaseFactory.inMemory()
        let migration = JobPayloadMigration(fromVersion: 1, toVersion: 2) { data in
            var object = try #require(
                JSONSerialization.jsonObject(with: data) as? [String: Any]
            )
            object["count"] = 7
            return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        }
        var registry = JobRegistry()
        try registry.register(MigratedJob.self, migrations: [migration]) { job, _ in
            await recorder.record("\(job.name):\(job.count)")
        }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(MigratedJob(name: "new", count: 1))
        let oldPayload = try JSONSerialization.data(
            withJSONObject: ["name": "legacy"],
            options: [.sortedKeys]
        )
        try await database.write { db in
            try db.execute(
                sql: """
                    UPDATE durable_queue_jobs
                    SET payload = ?, payload_version = 1
                    WHERE id = ?
                    """,
                arguments: [oldPayload, receipt.id.description]
            )
        }

        try await queue.runDueJobs()

        #expect(try await queue.status(receipt.id)?.state == .succeeded)
        #expect(await recorder.values == ["legacy:7"])
    }

    @Test("Corrupt payload data is preserved as a failed job")
    func corruptPayloadFailsPermanently() async throws {
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(database: database, registry: registry)
        let receipt = try await queue.dispatch(TestJob(value: "corrupt"))
        try await database.write { db in
            try db.execute(
                sql: "UPDATE durable_queue_jobs SET payload = ? WHERE id = ?",
                arguments: [Data([0xFF]), receipt.id.description]
            )
        }

        try await queue.runDueJobs()

        let snapshot = try #require(try await queue.status(receipt.id))
        #expect(snapshot.state == .failed)
        #expect(snapshot.lastFailure?.kind == .payloadDecodingFailed)
    }

    @Test("Completed history can be pruned")
    func completedHistoryPruning() async throws {
        let now = Date(timeIntervalSince1970: 40_000)
        let database = try TestDatabaseFactory.inMemory()
        var registry = JobRegistry()
        try registry.register(TestJob.self) { _, _ in }
        let queue = try DurableQueue(
            database: database,
            registry: registry,
            configuration: .init(now: { now })
        )
        let receipt = try await queue.dispatch(TestJob(value: "prune"))
        try await queue.runDueJobs()

        try await queue.pruneCompleted(before: now.addingTimeInterval(1))

        #expect(try await queue.status(receipt.id) == nil)
    }
}
