import Foundation

public protocol DurableJobHandler: Sendable {
    associatedtype Job: DurableJob

    func handle(job: Job, context: JobContext) async throws
}
