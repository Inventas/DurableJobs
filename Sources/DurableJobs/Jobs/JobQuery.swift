public struct JobQuery: Sendable {
    public var states: Set<JobState>
    public var queues: Set<String>
    public var typeIdentifiers: Set<String>
    public var tags: Set<String>
    public var limit: Int
    public var cursor: JobCursor?
    /// Offset remains for source compatibility. New code must use a cursor.
    public var offset: Int

    public init(
        state: JobState? = nil,
        queue: String? = nil,
        typeIdentifier: String? = nil,
        tag: String? = nil,
        states: Set<JobState> = [],
        queues: Set<String> = [],
        typeIdentifiers: Set<String> = [],
        tags: Set<String> = [],
        limit: Int = 100,
        cursor: JobCursor? = nil,
        offset: Int = 0
    ) {
        self.states = states.union(state.map { [$0] } ?? [])
        self.queues = queues.union(queue.map { [$0] } ?? [])
        self.typeIdentifiers = typeIdentifiers.union(typeIdentifier.map { [$0] } ?? [])
        self.tags = tags.union(tag.map { [$0] } ?? [])
        self.limit = min(1_000, max(1, limit))
        self.cursor = cursor
        self.offset = max(0, offset)
    }

    public var state: JobState? {
        get { states.count == 1 ? states.first : nil }
        set { states = newValue.map { [$0] } ?? [] }
    }

    public var queue: String? {
        get { queues.count == 1 ? queues.first : nil }
        set { queues = newValue.map { [$0] } ?? [] }
    }

    public var typeIdentifier: String? {
        get { typeIdentifiers.count == 1 ? typeIdentifiers.first : nil }
        set { typeIdentifiers = newValue.map { [$0] } ?? [] }
    }

    public var tag: String? {
        get { tags.count == 1 ? tags.first : nil }
        set { tags = newValue.map { [$0] } ?? [] }
    }
}
