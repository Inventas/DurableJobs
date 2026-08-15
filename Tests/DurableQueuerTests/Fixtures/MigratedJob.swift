import DurableQueuer

struct MigratedJob: DurableJob {
    static let typeIdentifier = "tests.migrated-job"
    static let payloadVersion = 2

    let name: String
    let count: Int
}
