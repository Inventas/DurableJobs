# DurableJobs

DurableJobs adds a typed, durable job layer on top of Queuer and GRDB. Jobs
are encoded as `Codable` payloads in SQLite, claimed with a lease, and then
run through Queuer's in-process executor. The package targets iOS 15 and later
and macOS 13 and later.

The delivery contract is **at least once**. A crash after a handler performs a
side effect but before the success transaction commits can run that job again.
Handlers must therefore be idempotent, or use the stable
`JobContext.idempotencyKey` with the downstream service. This package does not
provide exactly-once side effects.

## A typed job

`DurableJob` contains only the data needed to rebuild a job. Register the
handler separately. This keeps closures and service instances out of the
persisted payload.

```swift
import Foundation
import DurableJobs
import GRDB

struct SendInvoice: DurableJob {
    static let typeIdentifier = "billing.send-invoice"
    static let payloadVersion = 1
    static let defaults = JobDefaults(
        queue: "billing",
        maxAttempts: 4,
        retryPolicy: .default,
        lane: .processingNetwork
    )

    let invoiceID: UUID
}

var registry = JobRegistry()
try registry.register(SendInvoice.self) { job, context in
    // Make the service call idempotent with context.idempotencyKey.
    try await invoiceService.send(
        invoiceID: job.invoiceID,
        idempotencyKey: context.idempotencyKey
    )
}

let databaseURL = appSupportURL.appendingPathComponent("app.sqlite")
let database = try DatabasePool(path: databaseURL.path)
let queue = try DurableQueue(database: database, registry: registry)

let receipt = try await queue.dispatch(
    SendInvoice(invoiceID: invoiceID),
    options: DispatchOptions(idempotencyKey: "invoice:\(invoiceID.uuidString)")
)

try await queue.runDueJobs()
let status = try await queue.status(receipt.id)
```

`DispatchOptions` can override queue, priority, delay, availability, deadline,
timeout, attempts, retry policy, scheduling requirements, execution lane, a unique active
job key, an idempotency key, and inspection tags. `uniqueKey` suppresses a
second queued or running job. It is not a replacement for an idempotency key.
Completed rows can be pruned, and a retried side effect still needs an
idempotency boundary.

Unique jobs use `UniqueJobPolicy.keep` by default. Use `.replace` when the new
payload must cancel and supersede the active job. Replacement is durable and
fences a running job before the new row is inserted. Handler cancellation is
still cooperative, so both payloads must remain idempotent.

Use `.append` to create a durable dependency on the current unique-work tail.
Use `.appendOrReplace` to append to active work or start a new sequence after a
failed or cancelled sequence. `dispatchDebounced` is delayed `.replace` work.

Payload changes use `payloadVersion` and one-step `JobPayloadMigration` values
passed to `JobRegistry.register`. A stored version newer than the registered
handler is rejected. `JobMiddleware` composes around a handler; the supplied
`WithoutOverlapping` middleware uses a lease-renewed durable lock and releases
the job when the lock is busy. `RateLimited` and `ThrottleExceptions` keep
their counters in SQLite.

The queue exposes `status(_:)`, bounded process-local events, database-backed
`observe(_:)` and `observe(matching:)`, `cancel(_:)`,
`pause(queue:)`, `resume(queue:)`, full and lane-specific drains, and retention
helpers. A handler can call `context.heartbeat()`, report progress from 0
through 1, ask for cancellation, release itself for a later attempt, or fail
permanently. Drain methods throw when storage, lease maintenance, or
cancellation prevents a reliable drain. A recorded handler failure does not
make the drain throw because the failure or retry state is already durable.

## Shared GRDB database

Use one `DatabasePool` for the app's records and the durable queue. If the app
uses Point-Free SQLiteData, assign this same writer as SQLiteData's default
database, then pass it to `DurableQueue`. DurableJobs creates only its own
`durable_queue_*` tables and runs its migration on that writer.

```swift
let database = try DatabasePool(path: databaseURL.path)

prepareDependencies {
    $0.defaultDatabase = database       // SQLiteData
}

let queue = try DurableQueue(database: database, registry: registry)
```

When an application record and its job must be atomic, use the transactional
dispatch overload from the application's GRDB write closure:

```swift
let receipt = try await database.write { db in
    try order.insert(db)
    return try queue.dispatch(
        SendInvoice(invoiceID: order.invoiceID),
        in: db
    )
}
```

Both writes commit or roll back together. This overload does not emit the
process-local `dispatched` event because the outer transaction can still roll
back after the method returns. Persisted status is authoritative.

## Inspect and operate jobs

Use a bounded `JobQuery` to inspect local work by state, queue, job type, or
tag. Each field accepts a set. The default result limit is 100 and the maximum
is 1,000. Use the last `JobInfo.cursor` for stable pagination.

```swift
let failedSyncJobs = try await queue.jobs(
    matching: JobQuery(state: .failed, tag: "sync")
)

try await queue.retry(failedSyncJobs[0].snapshot.id)
try await queue.forget(oldCompletedJobID)
```

`retry(_:)` accepts only failed jobs. It resets execution state but keeps the
same job ID, payload, idempotency key, unique key, and tags. `forget(_:)`
accepts only terminal jobs and removes their tags with them.
The matching overloads cancel, retry, or forget a full query. `dispatchAll`
inserts independent jobs atomically. `health()` reports state and queue counts,
oldest eligible work, active leases, failure hooks, and next eligible dates.

## Recurring work and workflows

Recurring definitions have a stable `RecurringScheduleID`, an interval, an
optional flexible execution window, and either bounded `.all` catch-up or the
default `.latest` missed-run policy. Scheduling is inexact. Each occurrence is
an ordinary job with the normal lease, retry, progress, and inspection rules.

`dispatchChain` inserts sequential jobs atomically. Later steps start in
`blocked`. Success releases the next step. Failure and cancellation cascade,
unless a step uses `.runRegardless` for cleanup. `dispatchBatch` inserts
parallel jobs, reports aggregate progress, supports group cancellation, and
can release one completion job after all members finish. Jobs exchange record
IDs; the queue does not pass arbitrary output data between steps.

## In-app dashboard

`DurableJobsDashboard` is an optional SwiftUI product for development and
support builds. The core `DurableJobs` product does not link SwiftUI and does
not require the dashboard. Add the dashboard product only to targets that show
the tool, then present its root view with the same queue instance used by the
application:

```swift
#if DEBUG
import DurableJobsDashboard

DurableQueueDashboard(queue: queue)
#endif
```

The dashboard shows current counts, per-queue state, paused queues, hourly
completed and failed activity for the last 24 hours, bounded job lists, failure
details, and job progress. It refreshes from process-local events and polls the
durable database once per second while visible, so it also sees changes made by
another `DurableQueue` instance.

On iPhone, the dashboard uses compact Overview, Jobs, and Queues tabs. On iPad
and macOS, it uses an adaptive split view with a sidebar and a wide detail area.

The dashboard can retry failed jobs, cancel queued or running jobs, forget
terminal jobs, and pause or resume queues. It asks for confirmation before each
operation. It never starts a queue drain by itself.

Stored payload data is not fetched or shown by default. An application can
provide an asynchronous formatter for selected jobs. The formatter must decode
only known job types and return a redacted summary that is safe to display:

```swift
let configuration = DurableQueueDashboardConfiguration(
    payloadFormatter: { payload in
        guard payload.typeIdentifier == SendInvoice.typeIdentifier else {
            return nil
        }

        let job = try JSONDecoder().decode(SendInvoice.self, from: payload.data)
        return "Invoice \(job.invoiceID.uuidString)"
    }
)

DurableQueueDashboard(queue: queue, configuration: configuration)
```

The raw payload is passed only to this host-supplied formatter after a job is
selected. The dashboard does not render, cache, persist, or log the raw bytes.
The host application is responsible for removing credentials, personal data,
and other secrets from the returned string.

For runnable iOS and macOS examples with completed, failed, delayed, and
long-running jobs, see
[the dashboard sample app](Examples/DashboardSample/README.md).

The SQLiteData integration is an application fixture, not a dependency of this
package. For an app whose deployment target is iOS 15, pin SQLiteData to
**1.8.2** until a newer release is verified against the app's deployment target
and Swift toolchain. Do not add SQLiteData to this package's `Package.swift`.
See [the integration fixture](Examples/SQLiteDataIntegration/README.md).

## BackgroundTasks

`DurableJobsBackgroundTasks` maps the five `JobExecutionLane` values to five
identifiers. Create identifiers from the app's reverse-DNS bundle identifier:

```swift
let bridge = BackgroundTaskBridge(
    queue: queue,
    prefix: Bundle.main.bundleIdentifier!
)

let registered = bridge.registerLaunchHandlers()

Task {
    try await queue.runDueJobs()
    if registered {
        await bridge.attach(to: queue)
    }
}
```

Keep the bridge alive for the lifetime of the process. Add all five generated
strings to `BGTaskSchedulerPermittedIdentifiers` in `Info.plist`, and enable
the Background Modes capability needed by the app (Background fetch for the
refresh lane and Background processing for processing lanes). See
[BackgroundTasks setup](Documentation/BackgroundTasks.md) for the exact
identifiers and launch lifecycle.

The iOS 26 continued-processing request is optional and must be guarded with
`if #available(iOS 26.0, *)`. The package remains usable on iOS 15; an iOS 27
build must still keep iOS 26 calls availability-gated and should be tested with
the iOS 27 SDK. Background scheduling is best effort. It is not a guarantee of
immediate execution or a replacement for a background `URLSession` transfer.

## Scope

DurableJobs does not provide a remote broker, distributed workers, exactly-once
side effects, arbitrary closure serialization, continuous network reachability,
cross-device synchronization, or automatic URLSession transfer
management. It also cannot stop a non-cooperative synchronous handler. Those
concerns belong to the application or a separate integration.

Further details are in [package architecture](Documentation/Architecture.md),
[typed jobs](Documentation/TypedJobs.md),
[reliability semantics](Documentation/Reliability.md),
[GRDB/SQLiteData setup](Documentation/SQLiteDataIntegration.md), and
[BackgroundTasks](Documentation/BackgroundTasks.md), and
[recurring work and workflows](Documentation/Workflows.md).
