# Typed jobs

DurableQueuer follows a Laravel-style split between a serializable job value
and its registered handler. A job type declares a stable `typeIdentifier`, a
`payloadVersion`, and `JobDefaults`:

```swift
import Foundation

struct RebuildSearchIndex: DurableJob {
    static let typeIdentifier = "search.rebuild-index"
    static let payloadVersion = 1
    static let defaults = JobDefaults(
        queue: "search",
        priority: 10,
        maxAttempts: 3,
        retryPolicy: .exponentialFullJitter(base: 5, maximum: 900),
        timeout: 300,
        requirements: [.networkConnectivity],
        lane: .processingNetwork
    )

    let indexID: UUID
}
```

Register the type once at app startup. The registry stores a decoder and a
typed closure; it never stores a live job object or a service instance.

```swift
var registry = JobRegistry()
try registry.register(RebuildSearchIndex.self) { job, context in
    try await searchService.rebuild(
        indexID: job.indexID,
        idempotencyKey: context.idempotencyKey
    )
}
```

Use the optional `migrations` and `onFailure` arguments when the payload shape
changes or failure notification is required:

```swift
try registry.register(
    RebuildSearchIndex.self,
    migrations: [
        JobPayloadMigration(fromVersion: 1, toVersion: 2) { oldData in
            // Decode version 1 and encode version 2.
            migrateSearchPayload(oldData)
        }
    ],
    onFailure: { job, failure, context in
        await failureReporter.record(failure, jobID: context.id)
    },
    handler: { job, context in
        try await searchService.rebuild(
            indexID: job.indexID,
            idempotencyKey: context.idempotencyKey
        )
    }
)
```

The registry rejects duplicate type identifiers and rejects a stored payload
version when a complete migration chain is not registered. Keep identifiers
stable after release. If a type is renamed, register the old identifier while
old rows can still exist and migrate them explicitly.

## Dispatch and control

```swift
let receipt = try await queue.dispatch(
    RebuildSearchIndex(indexID: indexID),
    options: DispatchOptions(
        delay: 30,
        maxAttempts: 5,
        uniqueKey: "search:\(indexID.uuidString)",
        idempotencyKey: "search-rebuild:\(indexID.uuidString)"
    )
)

if let snapshot = try await queue.status(receipt.id) {
    print(snapshot.state, snapshot.attempt, snapshot.progress)
}

try await queue.cancel(receipt.id)
```

`DispatchReceipt.result` is `.inserted` for a new row and `.existing` when an
active `uniqueKey` already owns the work. A queued cancellation is terminal.
For a running job, cancellation is cooperative: the handler must check
`context.isCancellationRequested` or use an async API that responds to task
cancellation.

`JobContext` provides:

- `id`, `attempt`, `maxAttempts`, `queuedAt`, and a stable `idempotencyKey`;
- `heartbeat()` to extend the lease;
- `reportProgress(_:)` for values from 0 through 1;
- `isCancellationRequested` for cooperative cancellation;
- `release(after:)` to schedule another attempt; and
- `failPermanently(_:)` to record a terminal failure.

`RetryPolicy.none`, `.fixed(delay:)`, and
`.exponentialFullJitter(base:maximum:)` are persisted with the job. The queue
owns retry scheduling. Do not add a second retry loop in the handler.

## Middleware

Middleware receives the same `JobContext` and a `next` closure. It can enforce
locks, tracing, or application policy without changing the payload. The
`WithoutOverlapping` middleware stores its lock in the queue database and
releases the job when another worker owns the lock:

```swift
let middleware: [any JobMiddleware] = [
    try WithoutOverlapping(key: "search-index")
]

try registry.register(
    RebuildSearchIndex.self,
    middleware: middleware,
    handler: { job, context in
        try await searchService.rebuild(
            indexID: job.indexID,
            idempotencyKey: context.idempotencyKey
        )
    }
)
```

## Reliability contract

Each attempt is claimed with a lease. If the process exits, a later drain
recovers an expired lease. The success/failure transition is written after the
handler returns. Therefore a side effect can happen twice when a process exits
between the side effect and that transition. Use `context.idempotencyKey` in
the downstream API, or write an application outbox in the same transaction as
the side effect.

`uniqueKey` is only an active-row constraint. It prevents duplicate queued or
running rows, but it does not make a remote operation idempotent and does not
survive deletion by retention. Keep a separate idempotency key for every
external side effect.

Tags are durable inspection metadata. Add them with `DispatchOptions.tags`,
then use `JobQuery(tag:)` to find matching jobs. Tags do not change scheduling,
uniqueness, retry, or idempotency behavior.

Failure hooks are retried from durable state. Each hook attempt has its own
token, lease expiry, attempt count, and next eligible time. This prevents two
queue instances from delivering the same hook at the same time. A failed hook
must still be safe to run more than once because a process can stop after the
hook side effect and before the completion write. A hook must not be required
to decide the primary job result.

## Payload size and protection

Keep payloads small and carry application record IDs instead of files or large
object graphs. Set `maximumPayloadBytes` to reject encoded payloads above an
application-defined limit. The default does not enforce a limit during this
pre-release phase.

An optional `JobPayloadProtection` in `DurableQueueConfiguration` can protect
bytes before storage and restore them before migration and decoding. Key
management remains an application responsibility. Raw payload inspection
returns the stored, protected bytes.
