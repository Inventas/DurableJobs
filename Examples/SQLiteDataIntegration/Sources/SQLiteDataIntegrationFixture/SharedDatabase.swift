import DurableJobs
import Foundation
import GRDB
import SQLiteData

public enum SQLiteDataDurableQueueFixture {
    public static func makeQueue(
        appSupportURL: URL,
        registry: JobRegistry
    ) throws -> DurableQueue {
        let databaseURL = appSupportURL.appendingPathComponent("app.sqlite")
        let database = try DatabasePool(path: databaseURL.path)

        prepareDependencies {
            $0.defaultDatabase = database
        }

        return try DurableQueue(database: database, registry: registry)
    }
}
