public struct JobInfo: Sendable, Equatable {
    public let snapshot: JobSnapshot
    public let tags: Set<String>

    public init(snapshot: JobSnapshot, tags: Set<String>) {
        self.snapshot = snapshot
        self.tags = tags
    }

    public var cursor: JobCursor {
        JobCursor(createdAt: snapshot.createdAt, id: snapshot.id)
    }
}
