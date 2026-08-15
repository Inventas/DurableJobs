import Foundation

public struct DurableQueueConfiguration: Sendable {
    public var maximumConcurrentJobs: Int
    public var leaseDuration: TimeInterval
    public var heartbeatInterval: TimeInterval
    public var interruptionRetryDelay: TimeInterval
    public var failureHookLeaseDuration: TimeInterval
    public var failureHookRetryPolicy: RetryPolicy
    public var maximumFailureHookAttempts: Int
    public var progressWriteInterval: TimeInterval
    public var eventBufferLimit: Int
    public var observationPollingInterval: TimeInterval
    public var succeededRetention: TimeInterval
    public var cancelledRetention: TimeInterval
    public var failedRetention: TimeInterval
    public var now: @Sendable () -> Date
    public var randomUnit: @Sendable () -> Double
    public var logger: (@Sendable (QueueLogEntry) -> Void)?
    public var maximumPayloadBytes: Int?
    public var payloadProtection: (any JobPayloadProtection)?

    public init(
        maximumConcurrentJobs: Int = 2,
        leaseDuration: TimeInterval = 90,
        heartbeatInterval: TimeInterval = 30,
        interruptionRetryDelay: TimeInterval = 0,
        failureHookLeaseDuration: TimeInterval? = nil,
        failureHookRetryPolicy: RetryPolicy = .default,
        maximumFailureHookAttempts: Int = 5,
        progressWriteInterval: TimeInterval = 0.25,
        eventBufferLimit: Int = 256,
        observationPollingInterval: TimeInterval = 0.25,
        succeededRetention: TimeInterval = 7 * 24 * 60 * 60,
        cancelledRetention: TimeInterval = 7 * 24 * 60 * 60,
        failedRetention: TimeInterval = 30 * 24 * 60 * 60,
        now: @escaping @Sendable () -> Date = Date.init,
        randomUnit: @escaping @Sendable () -> Double = { Double.random(in: 0 ... 1) },
        logger: (@Sendable (QueueLogEntry) -> Void)? = nil,
        maximumPayloadBytes: Int? = nil,
        payloadProtection: (any JobPayloadProtection)? = nil
    ) {
        self.maximumConcurrentJobs = maximumConcurrentJobs
        self.leaseDuration = leaseDuration
        self.heartbeatInterval = heartbeatInterval
        self.interruptionRetryDelay = interruptionRetryDelay
        self.failureHookLeaseDuration = failureHookLeaseDuration ?? leaseDuration
        self.failureHookRetryPolicy = failureHookRetryPolicy
        self.maximumFailureHookAttempts = maximumFailureHookAttempts
        self.progressWriteInterval = progressWriteInterval
        self.eventBufferLimit = eventBufferLimit
        self.observationPollingInterval = observationPollingInterval
        self.succeededRetention = succeededRetention
        self.cancelledRetention = cancelledRetention
        self.failedRetention = failedRetention
        self.now = now
        self.randomUnit = randomUnit
        self.logger = logger
        self.maximumPayloadBytes = maximumPayloadBytes
        self.payloadProtection = payloadProtection
    }

    public static let `default` = Self()

    func validate() throws {
        guard maximumConcurrentJobs > 0 else {
            throw DurableQueueError.invalidConfiguration("maximumConcurrentJobs must be positive")
        }
        try validateFinitePositive(leaseDuration, name: "leaseDuration")
        try validateFinitePositive(heartbeatInterval, name: "heartbeatInterval")
        guard heartbeatInterval < leaseDuration else {
            throw DurableQueueError.invalidConfiguration("heartbeatInterval must be shorter than leaseDuration")
        }
        try validateFiniteNonnegative(interruptionRetryDelay, name: "interruptionRetryDelay")
        try validateFinitePositive(failureHookLeaseDuration, name: "failureHookLeaseDuration")
        guard maximumFailureHookAttempts > 0 else {
            throw DurableQueueError.invalidConfiguration("maximumFailureHookAttempts must be positive")
        }
        try validateFiniteNonnegative(progressWriteInterval, name: "progressWriteInterval")
        guard eventBufferLimit > 0 else {
            throw DurableQueueError.invalidConfiguration("eventBufferLimit must be positive")
        }
        try validateFinitePositive(observationPollingInterval, name: "observationPollingInterval")
        try validateFiniteNonnegative(succeededRetention, name: "succeededRetention")
        try validateFiniteNonnegative(cancelledRetention, name: "cancelledRetention")
        try validateFiniteNonnegative(failedRetention, name: "failedRetention")
        if let issue = failureHookRetryPolicy.validationIssue {
            throw DurableQueueError.invalidConfiguration("failureHookRetryPolicy: \(issue)")
        }
        let random = randomUnit()
        guard random.isFinite, (0 ... 1).contains(random) else {
            throw DurableQueueError.invalidConfiguration("randomUnit must return a finite value from 0 through 1")
        }
        guard now().timeIntervalSinceReferenceDate.isFinite else {
            throw DurableQueueError.invalidConfiguration("now must return a finite date")
        }
        if let maximumPayloadBytes, maximumPayloadBytes <= 0 {
            throw DurableQueueError.invalidConfiguration("maximumPayloadBytes must be positive")
        }
    }

    private func validateFinitePositive(_ value: TimeInterval, name: String) throws {
        guard value.isFinite, value > 0 else {
            throw DurableQueueError.invalidConfiguration("\(name) must be finite and positive")
        }
    }

    private func validateFiniteNonnegative(_ value: TimeInterval, name: String) throws {
        guard value.isFinite, value >= 0 else {
            throw DurableQueueError.invalidConfiguration("\(name) must be finite and nonnegative")
        }
    }
}
