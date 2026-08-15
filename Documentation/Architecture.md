# Package architecture

DurableJobs groups source files by responsibility. Swift Package Manager
finds source files recursively, so these folders do not change the package's
public modules.

```text
Sources/
├── DurableJobs/
│   ├── Jobs/          Job contracts, state, events, and inspection models
│   ├── Middleware/    Handler middleware and durable coordination
│   ├── Queue/         Dispatch, execution, operations, and state transitions
│   ├── Registry/      Job registration, payload coding, and payload upgrades
│   ├── Scheduling/    Dispatch options, retry policy, and execution lanes
│   ├── Storage/       GRDB records, database helpers, and queue schema
│   └── Workflows/     Chain and batch public models
├── DurableJobsBackgroundTasks/
│   ├── Bridge/        Queue-to-BackgroundTasks coordination
│   ├── Execution/     Launch invocation, cancellation, and registration state
│   └── Scheduling/    Identifiers and system scheduling adapters
├── DurableJobsDashboard/
│   ├── Components/    Reusable SwiftUI dashboard components
│   ├── State/         Refresh, paging, payload, and operation coordination
│   └── Views/         Adaptive dashboard, list, and detail screens
└── DurableJobsTestSupport/  Shared public test database support
```

Tests use the same split where it helps navigation. Queue behavior tests are in
`Queue`, reusable test jobs are in `Fixtures`, and synchronization helpers are
in `Support`.

## Optional dashboard boundary

`DurableJobsDashboard` depends on `DurableJobs`; the core target does not
depend on the dashboard or SwiftUI. Applications opt in by linking the dashboard
product and constructing `DurableQueueDashboard` with a queue or another
`DurableQueueDashboardDataSource` implementation.

`Examples/DashboardSample` contains a separate macOS executable package and an
iOS Xcode application target. Both depend on the dashboard product and use a
file-backed queue. They do not add an executable target or SwiftUI dependency
to the root package.

The dashboard chooses compact tab navigation on iPhone. It uses a split view on
regular-width iPad windows and macOS. Overview, list, and detail content share
the same store and operation confirmation layer on each platform.

The core target owns durable inspection values and the aggregate SQL query.
The dashboard target owns presentation state, polling, pagination, confirmation
dialogs, and host-formatted payload summaries. Aggregate metrics are read in one
database snapshot. The current schema already contains the state and terminal
timestamps used by the dashboard, so this feature adds no migration.

## Schema lifecycle

The first release has one database migration, `durable-queue-v1`. It creates
the complete initial queue schema, including recurring definitions,
dependencies, batches, attempts, middleware state, tags, and failure-hook lease
columns. Add a new database migration only after a released version can have a
persistent database with the v1 schema. Do not change v1 after that release.

`JobPayloadMigration` is separate from the database schema migration. It
upgrades the encoded payload of a registered job type and remains part of the
public job registry API.

## One execution engine

Recurring occurrences, chain steps, appended unique work, batch members, and
batch completion callbacks are normal `durable_queue_jobs` rows. Dependencies
only control when a row changes from `blocked` to `queued`. This keeps one
claim, lease, retry, progress, cancellation, and retention implementation.

Database-backed observation polls the shared SQLite file and coalesces equal
values. This also sees writes from a different `DatabasePool` or queue
instance. Process-local events remain a bounded, low-latency hint.
