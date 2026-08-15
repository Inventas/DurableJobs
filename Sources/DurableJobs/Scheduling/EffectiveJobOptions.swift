import Foundation

struct EffectiveJobOptions: Sendable {
    let queue: String
    let priority: Int
    let availableAt: Date
    let deadline: Date?
    let timeout: TimeInterval?
    let maxAttempts: Int
    let retryPolicy: RetryPolicy
    let requirements: JobRequirements
    let lane: JobExecutionLane
    let uniqueKey: String?
    let uniquePolicy: UniqueJobPolicy
    let idempotencyKey: String
    let tags: Set<String>
}
