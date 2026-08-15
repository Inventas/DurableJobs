import DurableQueuer
import Foundation

struct SampleJob: DurableJob {
    static let typeIdentifier = "dashboard.sample-job"
    static let defaults = JobDefaults(
        queue: "sample",
        maxAttempts: 1,
        timeout: 30
    )

    let name: String
    let duration: TimeInterval
    let shouldFail: Bool
}
