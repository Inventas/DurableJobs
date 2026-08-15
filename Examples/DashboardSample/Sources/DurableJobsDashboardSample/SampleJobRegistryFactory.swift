import DurableJobs
import Foundation

enum SampleJobRegistryFactory {
    static func make() throws -> JobRegistry {
        var registry = JobRegistry()
        try registry.register(SampleJob.self) { job, context in
            let stepCount = 20
            let stepDuration = max(0, job.duration) / Double(stepCount)

            for step in 1 ... stepCount {
                if await context.isCancellationRequested {
                    throw CancellationError()
                }

                if stepDuration > 0 {
                    try await Task.sleep(
                        nanoseconds: UInt64(stepDuration * 1_000_000_000)
                    )
                }
                try await context.reportProgress(Double(step) / Double(stepCount))
            }

            if job.shouldFail {
                throw SampleJobError.plannedFailure(job.name)
            }
        }
        return registry
    }
}
