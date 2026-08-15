# SQLiteData compatibility fixture

This separate Swift package checks the intended host-app setup without adding
SQLiteData to DurableQueuer. It pins SQLiteData 1.8.2 for iOS 15 and supplies
the same `DatabasePool` to SQLiteData and DurableQueuer.

```sh
swift build --package-path Examples/SQLiteDataIntegration
```

See [`SharedDatabase.swift`](Sources/SQLiteDataIntegrationFixture/SharedDatabase.swift)
for the sample factory.

The queue schema is local durable state. Do not enable CloudKit synchronization
for lease, cancellation, or retry rows without a separate conflict design.
