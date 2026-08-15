import Foundation

final class OperationResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var result: Result<Void, any Error>?

    func store(_ result: Result<Void, any Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard self.result == nil else { return }
        self.result = result
    }

    func storeCancellationIfEmpty() {
        store(.failure(CancellationError()))
    }

    func get() throws {
        lock.lock()
        let result = self.result
        lock.unlock()

        switch result {
        case .success:
            return
        case let .failure(error):
            throw error
        case nil:
            throw CancellationError()
        }
    }
}
