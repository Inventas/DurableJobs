import Foundation

final class BackgroundTaskCancellationController: @unchecked Sendable {
    private let lock = NSLock()
    private var cancellation: (@Sendable () -> Void)?
    private var cancellationRequested = false

    func install(_ cancellation: @escaping @Sendable () -> Void) {
        let callImmediately: Bool

        lock.lock()
        if cancellationRequested {
            callImmediately = true
        } else {
            self.cancellation = cancellation
            callImmediately = false
        }
        lock.unlock()

        if callImmediately {
            cancellation()
        }
    }

    func cancel() {
        let cancellation: (@Sendable () -> Void)?

        lock.lock()
        guard !cancellationRequested else {
            lock.unlock()
            return
        }
        cancellationRequested = true
        cancellation = self.cancellation
        lock.unlock()

        cancellation?()
    }
}
