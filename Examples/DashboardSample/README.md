# DurableJobs dashboard sample

This sample exercises the optional `DurableJobsDashboard` product against a
real, file-backed SQLite queue. It includes an iOS 15 Xcode app for iPhone and
iPad and a standalone macOS 13 Swift Package app.

On the first launch, the app creates:

- one completed job;
- one failed job with failure details;
- one pending job with a delayed start.

The control bar can add more pending, failing, delayed, and long-running jobs.
Select **Run Due Jobs** to drain the queue. A long-running job gives enough time
to open its detail view and test cancellation. The dashboard also supports
retry, pause, resume, and forget operations.

## Run on iOS

Open `DurableJobsDashboardSample.xcodeproj`, select the
`DurableJobsDashboardSample-iOS` scheme, and run it on an iPhone or iPad.

The command-line build is:

```sh
xcodebuild \
  -project DurableJobsDashboardSample.xcodeproj \
  -scheme DurableJobsDashboardSample-iOS \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

The iPhone interface uses separate Overview, Jobs, and Queues tabs. iPad uses
the framework's adaptive split view when the window has enough width.

## Run on macOS

From this directory:

```sh
./Scripts/compile_and_run.sh --test
```

To build without launching the app:

```sh
swift test
./Scripts/package_app.sh debug
```

The package script creates `DurableJobsDashboardSample.app` in this
directory. It signs the local development build with an ad hoc signature.

The queue database persists at:

```text
~/Library/Application Support/DurableJobsDashboardSample/sample.sqlite
```

Remove the database only when you want a clean sample state. Each simulator has
its own application container and database.

## Payload safety

The sample payload formatter decodes only `SampleJob` and returns three known,
non-sensitive fields. A host app must apply its own redaction rules before it
returns a payload summary to the dashboard.
