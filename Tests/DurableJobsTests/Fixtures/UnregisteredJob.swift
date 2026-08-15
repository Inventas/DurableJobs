import DurableJobs

struct UnregisteredJob: DurableJob {
    static let typeIdentifier = "tests.unregistered"
    let value: String
}
