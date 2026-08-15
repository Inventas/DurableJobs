# Recurring work and workflows

## Recurring work

Recurring schedules are durable definitions. They do not execute handlers
directly. A drain materializes each due occurrence as a normal one-time job.

```swift
let scheduleID = RecurringScheduleID(rawValue: "daily-sync")

try await queue.scheduleRecurring(
    scheduleID,
    job: SyncAccount(accountID: accountID),
    schedule: RecurringSchedule(
        interval: 24 * 60 * 60,
        flex: 60 * 60,
        missedRunPolicy: .latest
    )
)

try await queue.pauseRecurring(scheduleID)
try await queue.resumeRecurring(scheduleID)
try await queue.cancelRecurring(scheduleID)
```

`.latest` creates only the newest missed occurrence. `.all(maximumCatchUp:)`
creates at most the stated number and skips older excess occurrences. `flex`
opens an early execution window. Neither option promises an exact time.
Rescheduling with `.keep` preserves an existing definition. `.update` replaces
its job request and timing values.

## Sequential chains

```swift
let chain = try await queue.dispatchChain([
    try ChainStep(DownloadManifest(projectID: projectID)),
    try ChainStep(ImportRecords(projectID: projectID)),
    try ChainStep(
        RemoveTemporaryFiles(projectID: projectID),
        behavior: .runRegardless
    ),
])
```

The first job is queued and later jobs are blocked. Success releases the next
job. Permanent failure or cancellation cascades through normal steps.
`runRegardless` releases cleanup after its prerequisite reaches any terminal
state. Chain insertion is atomic.

Unique `.append` and `.appendOrReplace` use the same dependency table. They are
useful for an ordered stream of work under one `uniqueKey`. `dispatchDebounced`
uses delayed `.replace` work instead.

## Parallel batches

```swift
let batch = try await queue.dispatchBatch(
    records.map { record in
        try JobRequest(IndexRecord(recordID: record.id))
    },
    completion: try JobRequest(FinishIndexGeneration(generationID: generationID))
)

let status = try await queue.batch(batch.id)
try await queue.cancelBatch(batch.id)
```

Batch progress treats each terminal member as complete and averages active
member progress. The optional completion job is blocked until all members are
terminal. Jobs must exchange durable application record IDs. DurableQueuer does
not serialize closures or pass handler output between jobs.
