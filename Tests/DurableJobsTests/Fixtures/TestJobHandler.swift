import DurableJobs

actor TestJobHandler: DurableJobHandler {
    let recorder: JobRecorder

    init(recorder: JobRecorder) {
        self.recorder = recorder
    }

    func handle(job: TestJob, context: JobContext) async throws {
        await recorder.record(job.value)
        try await context.reportProgress(0.5)
    }
}
