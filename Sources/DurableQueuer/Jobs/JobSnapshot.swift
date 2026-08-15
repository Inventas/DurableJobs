import Foundation

public struct JobSnapshot: Codable, Equatable, Sendable {
    public let id: JobID
    public let typeIdentifier: String
    public let queue: String
    public let state: JobState
    public let lane: JobExecutionLane
    public let requirements: JobRequirements
    public let attempt: Int
    public let maxAttempts: Int
    public let availableAt: Date
    public let deadline: Date?
    public let progress: Double
    public let idempotencyKey: String
    public let createdAt: Date
    public let updatedAt: Date
    public let finishedAt: Date?
    public let lastFailure: JobFailure?
    public let stopReason: JobStopReason?

    public init(
        id: JobID,
        typeIdentifier: String,
        queue: String,
        state: JobState,
        lane: JobExecutionLane,
        requirements: JobRequirements = [],
        attempt: Int,
        maxAttempts: Int,
        availableAt: Date,
        deadline: Date?,
        progress: Double,
        idempotencyKey: String,
        createdAt: Date,
        updatedAt: Date,
        finishedAt: Date?,
        lastFailure: JobFailure?,
        stopReason: JobStopReason? = nil
    ) {
        self.id = id
        self.typeIdentifier = typeIdentifier
        self.queue = queue
        self.state = state
        self.lane = lane
        self.requirements = requirements
        self.attempt = attempt
        self.maxAttempts = maxAttempts
        self.availableAt = availableAt
        self.deadline = deadline
        self.progress = progress
        self.idempotencyKey = idempotencyKey
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.finishedAt = finishedAt
        self.lastFailure = lastFailure
        self.stopReason = stopReason
    }
}
