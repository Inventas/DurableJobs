public enum UniqueJobPolicy: Codable, Equatable, Sendable {
    /// Keep the active job and return its ID.
    case keep

    /// Cancel the active job and insert the new job.
    case replace

    /// Add the new job after the current unique work. Requires chain support.
    case append

    /// Append to valid work, or replace a failed or cancelled tail.
    case appendOrReplace
}
