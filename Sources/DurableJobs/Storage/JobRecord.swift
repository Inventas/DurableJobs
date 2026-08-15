import Foundation
import GRDB

struct JobRecord: Sendable {
    let id: JobID
    let typeIdentifier: String
    let payload: Data
    let payloadVersion: Int
    let queue: String
    let state: JobState
    let lane: JobExecutionLane
    let priority: Int
    let availableAt: Date
    let deadline: Date?
    let timeout: TimeInterval?
    let attempt: Int
    let maxAttempts: Int
    let retryPolicy: RetryPolicy
    let requirements: JobRequirements
    let uniqueKey: String?
    let idempotencyKey: String
    let leaseToken: String?
    let leaseExpiresAt: Date?
    let cancelRequested: Bool
    let progress: Double
    let createdAt: Date
    let updatedAt: Date
    let finishedAt: Date?
    let lastFailure: JobFailure?
    let failureHookPending: Bool
    let failureHookAttempt: Int
    let stopReason: JobStopReason?

    init(row: Row) throws {
        guard
            let uuid = UUID(uuidString: row["id"]),
            let state = JobState(rawValue: row["state"]),
            let lane = JobExecutionLane(rawValue: row["lane"])
        else {
            throw DurableQueueError.invalidJobTypeIdentifier
        }

        id = JobID(uuid)
        typeIdentifier = row["type_identifier"]
        payload = row["payload"]
        payloadVersion = row["payload_version"]
        queue = row["queue_name"]
        self.state = state
        self.lane = lane
        priority = row["priority"]
        availableAt = Date(databaseMilliseconds: row["available_at"])
        deadline = (row["deadline_at"] as Int64?).map(Date.init(databaseMilliseconds:))
        timeout = row["timeout_seconds"]
        attempt = row["attempt_count"]
        maxAttempts = row["max_attempts"]
        retryPolicy = try JobPayloadCodec.decoder().decode(
            RetryPolicy.self,
            from: row["retry_policy"]
        )
        var requirements: JobRequirements = []
        if (row["requires_network"] as Int) != 0 {
            requirements.insert(.networkConnectivity)
        }
        if (row["requires_power"] as Int) != 0 {
            requirements.insert(.externalPower)
        }
        self.requirements = requirements
        uniqueKey = row["unique_key"]
        idempotencyKey = row["idempotency_key"]
        leaseToken = row["lease_token"]
        leaseExpiresAt = (row["lease_expires_at"] as Int64?).map(Date.init(databaseMilliseconds:))
        cancelRequested = (row["cancel_requested"] as Int) != 0
        progress = row["progress"]
        createdAt = Date(databaseMilliseconds: row["created_at"])
        updatedAt = Date(databaseMilliseconds: row["updated_at"])
        finishedAt = (row["finished_at"] as Int64?).map(Date.init(databaseMilliseconds:))
        failureHookPending = (row["failure_hook_pending"] as Int) != 0
        failureHookAttempt = row["failure_hook_attempt_count"]
        stopReason = (row["stop_reason"] as String?).flatMap(JobStopReason.init(rawValue:))

        if let kindValue: String = row["last_failure_kind"],
           let kind = JobFailureKind(rawValue: kindValue),
           let message: String = row["last_failure_message"],
           let occurredAt: Int64 = row["last_failure_at"] {
            lastFailure = JobFailure(
                kind: kind,
                message: message,
                occurredAt: Date(databaseMilliseconds: occurredAt)
            )
        } else {
            lastFailure = nil
        }
    }

    var snapshot: JobSnapshot {
        JobSnapshot(
            id: id,
            typeIdentifier: typeIdentifier,
            queue: queue,
            state: state,
            lane: lane,
            requirements: requirements,
            attempt: attempt,
            maxAttempts: maxAttempts,
            availableAt: availableAt,
            deadline: deadline,
            progress: progress,
            idempotencyKey: idempotencyKey,
            createdAt: createdAt,
            updatedAt: updatedAt,
            finishedAt: finishedAt,
            lastFailure: lastFailure,
            stopReason: stopReason
        )
    }
}
