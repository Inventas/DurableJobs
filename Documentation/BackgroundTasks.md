# BackgroundTasks integration

`DurableQueuerBackgroundTasks` adapts five durable execution lanes to Apple's
BackgroundTasks framework. The system decides when a request runs. An
`earliestBeginDate` is a lower bound, not a deadline or an execution promise.

## Five permitted identifiers

Create one `BackgroundTaskIdentifiers` value from the app's reverse-DNS bundle
identifier. With `com.example.myapp` as the prefix, the required values are:

| Lane | Identifier |
| --- | --- |
| `.refresh` | `com.example.myapp.refresh` |
| `.processing` | `com.example.myapp.processing` |
| `.processingNetwork` | `com.example.myapp.processing-network` |
| `.processingPower` | `com.example.myapp.processing-power` |
| `.processingNetworkAndPower` | `com.example.myapp.processing-network-power` |

The prefix is normalized when it ends in a period. Add all five strings to
`BGTaskSchedulerPermittedIdentifiers`:

```xml
<key>BGTaskSchedulerPermittedIdentifiers</key>
<array>
    <string>com.example.myapp.refresh</string>
    <string>com.example.myapp.processing</string>
    <string>com.example.myapp.processing-network</string>
    <string>com.example.myapp.processing-power</string>
    <string>com.example.myapp.processing-network-power</string>
</array>
```

Enable the **Background Modes** capability for the app target. Enable
**Background fetch** for the refresh lane and **Background processing** for the
processing lanes. The app must still register each identifier with
`BGTaskScheduler` before submitting requests.

## Register and schedule

Create and retain one bridge during app lifetime. Register handlers before the
app launch method returns, then reconcile and schedule the lanes asynchronously:

```swift
let bridge = BackgroundTaskBridge(
    queue: durableQueue,
    prefix: Bundle.main.bundleIdentifier!
)

let registered = bridge.registerLaunchHandlers()

Task {
    try await durableQueue.runDueJobs()
    if registered {
        await bridge.attach(to: durableQueue)
    }
}
```

`BackgroundTaskBridge` drains only the launched lane. On expiration it cancels
only active work in that lane, completes the invocation once, and schedules the
lane again. The completion gate is protected against an expiration/worker race.
The refresh lane also has an internal 20-second limit by default. You can set a
different limit in the bridge initializer.

After attachment, the queue asks the bridge to reconcile requests after
dispatch, retry, resume, release, cancellation, recovery, and terminal state
changes. A scheduler rejection never rolls back a durable database change.
Call `scheduleAll()` directly only when the host needs an explicit result.

The bridge reports success only when the lane drain returns without an
infrastructure or cancellation error. For continued processing, it reports
success only when the requested durable job ends in `succeeded`. A failed,
cancelled, queued, missing, or unreadable job reports an unsuccessful system
task completion.

For tests or another host scheduler, implement
`BackgroundTaskSchedulerClient` and inject it into the bridge. Its
`BackgroundTaskInvocation` is also platform-neutral and can be expired in a
test.

## iOS 26 continued processing

`ContinuedProcessingRequest` represents the iOS 26 continued-processing API.
Use it only for a user-started workload that should continue after the app is
backgrounded. Guard the call and the concrete scheduler with availability:

```swift
if #available(iOS 26.0, *) {
    let jobID = dispatchReceipt.id
    try await bridge.submitContinuedProcessing(
        ContinuedProcessingRequest(
            identifier: "com.example.app.jobs.continued.\(jobID)",
            jobID: jobID,
            title: "Processing queued work",
            subtitle: "The operation is still running",
            strategy: .queue
        )
    )
}
```

The host app must permit a matching wildcard identifier, such as
`com.example.app.jobs.continued.*`. The adapter runs only the requested durable
job, forwards its progress, and reconciles the five static lanes when it ends.

The default scheduler reports `continuedProcessingUnavailable` on older
systems. This package keeps its core deployment target at iOS 15. An iOS 27
build must continue to gate iOS 26 calls and should be tested with the iOS 27
SDK. When built with the iOS 27 SDK, the system scheduler uses Apple's async
task-submission API where available; the five identifiers and lane mapping do
not change. No iOS 27-only entitlement is assumed by this package. Use a
separate application integration for iOS 27 features such as background GPU
or Neural Engine work.

## Availability and limits

- Core DurableQueuer: iOS 15+, macOS 13+.
- Standard `BGTaskScheduler` integration: iOS 13+, gated by the host target's
  deployment setting.
- Continued processing: iOS 26+, guarded at each call site.
- iOS 27: keep the iOS 26 availability checks and validate any new system
  entitlement or API in the host app.

BackgroundTasks does not provide an exact execution time, a process lifetime,
or exactly-once side effects. The SQLite lease and idempotency rules remain
required even when a task is launched by the system. Use background
`URLSession` for transfers that must continue independently of app execution;
that integration is outside this package.
