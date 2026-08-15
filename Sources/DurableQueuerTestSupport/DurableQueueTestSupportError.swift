public enum DurableQueueTestSupportError: Error, Equatable, Sendable {
    case expectedJob(typeIdentifier: String, tags: Set<String>)
    case unexpectedJob(typeIdentifier: String, tags: Set<String>)
}
