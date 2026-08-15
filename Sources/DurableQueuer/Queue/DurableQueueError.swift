public enum DurableQueueError: Error, Sendable, Equatable {
    case duplicateJobType(String)
    case invalidJobTypeIdentifier
    case jobTypeNotRegistered(String)
    case unsupportedPayloadVersion(type: String, stored: Int, current: Int)
    case leaseLost(JobID)
    case heartbeatFailed(JobID, message: String)
    case failureHookLeaseLost(JobID)
    case invalidProgress
    case invalidQueueName
    case invalidTag
    case invalidConfiguration(String)
    case invalidDispatchOptions(String)
    case invalidPayloadVersion(type: String, version: Int)
    case invalidPayloadMigration(type: String, from: Int, to: Int)
    case incompletePayloadMigrationChain(type: String, from: Int, current: Int)
    case corruptMetadata(String)
    case jobNotFound(JobID)
    case invalidJobState(JobID, expected: JobState, actual: JobState)
    case jobNotTerminal(JobID, actual: JobState)
}
