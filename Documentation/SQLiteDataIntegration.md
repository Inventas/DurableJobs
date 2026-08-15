# SQLiteData integration

DurableQueuer and Point-Free SQLiteData can share one GRDB `DatabasePool`.
DurableQueuer uses that writer for its own `durable_queue_*` tables. SQLiteData
continues to own the app's model tables and default database dependency.

```swift
import DurableQueuer
import GRDB
import SQLiteData

func makeQueue(
    at url: URL,
    registry: JobRegistry
) throws -> DurableQueue {
    let database = try DatabasePool(path: url.path)

    prepareDependencies {
        $0.defaultDatabase = database
    }

    // The initializer runs the DurableQueuer initial schema migration on this
    // writer. Keep the pool alive for both SQLiteData and the queue.
    return try DurableQueue(database: database, registry: registry)
}
```

Do not open a second pool for the queue when the app already has a shared pool.
Using the same writer avoids split migration order and gives SQLite one
connection policy for app records and queue records. Coordinate any app schema
migrations with queue initialization during startup.

## SQLiteData 1.8.2 pin

The fixture assumes the host app, not DurableQueuer, owns the SQLiteData
dependency. For an iOS 15 deployment target, pin SQLiteData to **1.8.2** in the
host app's package resolution until a newer release is verified with the app's
minimum OS and Swift toolchain. Do not add SQLiteData to DurableQueuer's
`Package.swift`, and do not copy the host app's package pin into this package.

The fixture is a separate nested Swift package. It pins SQLiteData 1.8.2 and
its iOS 15-compatible StructuredQueries line without changing DurableQueuer's
dependency graph. Build it from `Examples/SQLiteDataIntegration`.

## Schema and reliability

DurableQueuer's initial queue migration creates tables with a
`durable_queue_` prefix.
Keep those tables out of SQLiteData CloudKit synchronization unless the app has
an explicit design for syncing leases and execution history. A local queue is
usually the correct scope. SQLiteData storage does not change the at-least-once
delivery contract: handlers still need an idempotency key for external side
effects.
