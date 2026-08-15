import DurableQueuer

actor JobRecorder {
    private(set) var values: [String] = []
    private(set) var failures: [JobFailure] = []

    func record(_ value: String) {
        values.append(value)
    }

    func recordAndReturnCount(_ value: String) -> Int {
        values.append(value)
        return values.count
    }

    func record(_ failure: JobFailure) {
        failures.append(failure)
    }
}
