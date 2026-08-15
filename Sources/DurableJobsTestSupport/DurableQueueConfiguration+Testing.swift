import DurableJobs

public extension DurableQueueConfiguration {
    static func testing(
        clock: ManualClock,
        randomUnit: Double = 0,
        maximumConcurrentJobs: Int = 1
    ) -> Self {
        Self(
            maximumConcurrentJobs: maximumConcurrentJobs,
            now: { clock.now },
            randomUnit: { randomUnit }
        )
    }
}
