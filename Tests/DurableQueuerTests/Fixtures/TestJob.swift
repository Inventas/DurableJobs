import DurableQueuer

struct TestJob: DurableJob {
    static let typeIdentifier = "tests.test-job"

    let value: String
    let shouldFail: Bool

    init(value: String, shouldFail: Bool = false) {
        self.value = value
        self.shouldFail = shouldFail
    }
}
