import DurableJobs
import Foundation

enum SamplePayloadFormatter {
    static func format(_ payload: EncodedJobPayload) throws -> String? {
        guard payload.typeIdentifier == SampleJob.typeIdentifier else {
            return nil
        }

        let job = try JSONDecoder().decode(SampleJob.self, from: payload.data)
        let result = job.shouldFail ? "Planned failure" : "Success"
        return """
        Name: \(job.name)
        Expected duration: \(job.duration.formatted(.number.precision(.fractionLength(1)))) seconds
        Expected result: \(result)
        """
    }
}
