# Reliability and delivery semantics

DurableJobs stores job state in SQLite and uses Queuer only to execute a
claimed attempt in the current process. The database is the source of truth;
the in-memory `OperationQueue` is not a recovery log.

## State and recovery

The queue records a blocked, queued, running, succeeded, failed, or cancelled state,
the attempt number, the retry policy, the lease token and expiry, the payload
version, progress, and the last failure. `runDueJobs()` first recovers expired
work, then claims due rows. A lease owner must heartbeat before the lease
expires. A later process can claim a row after an owner disappears.

Claiming a row also increments its attempt in the same SQLite transaction. A
process stop after claim therefore consumes the attempt. Lease recovery retries
an interrupted attempt until `maxAttempts` is reached, even when
`RetryPolicy.none` disables retries for handler errors. Use
`interruptionRetryDelay` to delay this recovery retry.

Automatic lease maintenance races the handler as structured concurrent work.
If a heartbeat loses ownership or cannot update SQLite, the queue cancels the
handler, emits `leaseLost`, and throws from the drain. All terminal transitions
also compare the lease token, so a stale handler cannot overwrite a newer
owner's state.

One actor-level drain coordinator serializes full, lane, single-job, and
`runNext` drains for a queue instance. A drain claims no more than the executor
can start. Optional durable per-queue limits also constrain claims across queue
instances that share the database.

Corrupt scheduling metadata is changed to a readable failed row with
`JobFailureKind.corruptMetadata`. The drain then continues to valid work.

Recovery is deliberately at least once. It cannot know whether an external
side effect committed immediately before a crash. Make every handler idempotent
or pass its persisted idempotency key to a service that deduplicates requests.

## Retries and deadlines

Retry state is persisted before a later attempt is eligible. `RetryPolicy` is
owned by the queue, not by Queuer's in-memory retry loop. `maxAttempts` counts
total attempts, including the first attempt. A deadline or timeout is recorded
as a failure; it is not a guarantee that a non-cooperative synchronous API will
stop at the exact deadline.

Failure hooks use their own durable token and expiry. Only one queue instance
can own a hook attempt. A failed hook clears its token and stores its next
eligible time from `failureHookRetryPolicy`. An expired hook lease is available
for a later process. `maximumFailureHookAttempts` clears a permanently broken
hook so retention can remove the failed job. `RetryPolicy.none` disables
another hook attempt.

## Drain errors

`runDueJobs()`, lane drains, and `runDueJob(_:)` throw when the queue cannot
trust the drain result. Examples include SQLite errors, task cancellation, and
lease loss. Handler errors do not throw after the queue has committed the
failed or retry state. `runDueJob(_:)` returns the current durable snapshot so
a continued-processing integration can use the actual terminal state.

## Application transactions

Use `dispatch(_:options:in:)` inside an existing GRDB write transaction when
application state and a job must commit together. The normal asynchronous
dispatch method owns its own transaction. The transaction overload does not
emit the process-local dispatch event because the caller still controls the
outer commit or rollback.

`UniqueJobPolicy.replace` cancels active unique work and inserts its
replacement in the same transaction. If the old handler is still running, its
lease is removed before the new job becomes visible. The normal actor API also
asks the local operation to cancel. Transactional dispatch cannot cancel an
in-memory operation before the caller commits, but lease fencing still blocks
all later state writes from the old handler.
Replacement records `JobStopReason.replaced`; it is not reported as lease loss.

## Cancellation and pause

Cancelling a blocked or queued row writes a terminal cancellation. Cancelling a running
row sets a durable cancellation request and asks the active operation to stop.
Automatic lease maintenance reads this request, so another queue instance can
stop cooperative work. `pause(queue:)` prevents new claims for that queue; it
does not interrupt work that is already running. Background task expiration
releases interrupted work, records `backgroundTaskExpired`, and reschedules the
lane.

`JobRequirements` selects BackgroundTasks request lanes. Network connectivity
and external power are scheduling requirements only. iOS does not provide
continuous WorkManager-style constraint monitoring to this package.

## Retention

Completed rows remain available for inspection until retention pruning removes
them. Do not use completed-row retention as an idempotency mechanism. Keep
business idempotency records for as long as a remote service can replay a
request.

## Out of scope

This package does not provide exactly-once side effects, a remote broker,
cross-device synchronization, a continuous network reachability
monitor, arbitrary closure serialization, or a replacement for background
`URLSession` transfers. A synchronous handler that ignores cancellation can
continue until it returns.
