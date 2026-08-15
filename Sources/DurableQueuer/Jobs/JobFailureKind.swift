public enum JobFailureKind: String, Codable, Sendable {
    case handlerError
    case permanent
    case deadlineExceeded
    case timedOut
    case unknownJobType
    case unsupportedPayloadVersion
    case payloadDecodingFailed
    case corruptMetadata
    case leaseExpired
}
