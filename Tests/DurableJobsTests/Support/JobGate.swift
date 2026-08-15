actor JobGate {
    private var started = false
    private var cancelled = false
    private var released = false
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []
    private var cancelledWaiters: [CheckedContinuation<Void, Never>] = []
    private var releasedWaiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        let waiters = startedWaiters
        startedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startedWaiters.append(continuation)
        }
    }

    func markCancelled() {
        cancelled = true
        let waiters = cancelledWaiters
        cancelledWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilCancelled() async {
        guard !cancelled else { return }
        await withCheckedContinuation { continuation in
            cancelledWaiters.append(continuation)
        }
    }

    func release() {
        released = true
        let waiters = releasedWaiters
        releasedWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func waitUntilReleased() async {
        guard !released else { return }
        await withCheckedContinuation { continuation in
            releasedWaiters.append(continuation)
        }
    }
}
