import Foundation
import GRDB

public enum TestDatabaseFactory {
    public static func inMemory() throws -> DatabaseQueue {
        try DatabaseQueue()
    }

    public static func fileBacked(at url: URL) throws -> DatabasePool {
        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        return try DatabasePool(path: url.path, configuration: configuration)
    }
}
