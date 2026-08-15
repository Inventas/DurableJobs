import Foundation

final class BackgroundTaskRegistrationStore: @unchecked Sendable {
    private let lock = NSLock()
    private var identifiers = Set<String>()

    func reserve(_ identifier: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return identifiers.insert(identifier).inserted
    }

    func release(_ identifier: String) {
        lock.lock()
        identifiers.remove(identifier)
        lock.unlock()
    }
}
