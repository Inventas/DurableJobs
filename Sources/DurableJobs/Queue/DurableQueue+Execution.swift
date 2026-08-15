import Foundation
import GRDB
import Queuer

extension DurableQueue {
    func enqueueAndWait(_ claimed: JobRecord) async throws {
        let resultBox = OperationResultBox()
        await withCheckedContinuation { continuation in
            let operation = AsyncConcurrentOperation(name: "job:\(claimed.id)") { _ in
                do {
                    try await self.perform(claimed)
                    resultBox.store(.success(()))
                } catch {
                    resultBox.store(.failure(error))
                }
            }
            operation.maximumRetries = 1
            operation.completionBlock = {
                resultBox.storeCancellationIfEmpty()
                continuation.resume()
            }
            activeOperations[claimed.id] = operation
            executor.addOperation(operation)
        }
        activeOperations[claimed.id] = nil
        lastProgressWrites[claimed.id] = nil
        activeStopReasons[claimed.id] = nil
        try resultBox.get()
    }

    func perform(_ record: JobRecord) async throws {
        await emit(kind: .claimed, jobID: record.id)

        guard let registration = registry.job(for: record.typeIdentifier) else {
            try await handleFailure(
                JobFailure(
                    kind: .unknownJobType,
                    message: "No handler is registered for \(record.typeIdentifier).",
                    occurredAt: configuration.now()
                ),
                for: record,
                forcePermanent: true
            )
            return
        }
        guard let leaseToken = record.leaseToken else { return }
        let context = makeContext(for: record, leaseToken: leaseToken)

        do {
            try await executeWithLeaseMaintenance(
                registration: registration,
                record: record,
                context: context,
                leaseToken: leaseToken
            )

            if try await durableCancellationRequested(id: record.id) {
                try await markCancelled(record)
            } else {
                try await markSucceeded(record)
            }
        } catch {
            if let queueError = error as? DurableQueueError {
                switch queueError {
                case .leaseLost, .heartbeatFailed:
                    if try await expectedCancellationAfterLeaseLoss(id: record.id) {
                        return
                    }
                    await emit(kind: .leaseLost, jobID: record.id)
                    throw queueError
                default:
                    break
                }
            }
            if error is DatabaseError {
                throw error
            }
            // Operation cancellation also cancels this task. Use a fresh task
            // so the durable terminal or retry transition can still commit.
            try await Task {
                try await self.handleExecutionError(error, record: record)
            }.value
        }
    }

    func executeWithLeaseMaintenance(
        registration: RegisteredJob,
        record: JobRecord,
        context: JobContext,
        leaseToken: String
    ) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await self.execute(
                    registration: registration,
                    record: record,
                    context: context
                )
            }
            group.addTask {
                try await self.maintainLease(id: record.id, leaseToken: leaseToken)
            }

            do {
                _ = try await group.next()
                group.cancelAll()
                try await group.waitForAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }

    func maintainLease(id: JobID, leaseToken: String) async throws {
        while !Task.isCancelled {
            do {
                try await Task.sleep(
                    nanoseconds: UInt64(configuration.heartbeatInterval * 1_000_000_000)
                )
                try Task.checkCancellation()
                try await heartbeat(id: id, leaseToken: leaseToken)
            } catch is CancellationError {
                return
            } catch is DurableCancellationRequested {
                throw DurableCancellationRequested()
            } catch let error as DurableQueueError {
                throw error
            } catch {
                throw DurableQueueError.heartbeatFailed(
                    id,
                    message: String(describing: error)
                )
            }
        }
    }

    func execute(
        registration: RegisteredJob,
        record: JobRecord,
        context: JobContext
    ) async throws {
        let work: @Sendable () async throws -> Void = {
            try Task.checkCancellation()
            try await MiddlewarePipeline.run(
                registration.middleware,
                context: context
            ) {
                try Task.checkCancellation()
                let payload = try self.configuration.payloadProtection?.unprotect(record.payload)
                    ?? record.payload
                try await registration.handler(
                    payload,
                    record.payloadVersion,
                    context
                )
            }
        }

        guard let timeout = record.timeout, timeout > 0 else {
            try await work()
            return
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(
                    nanoseconds: UInt64(timeout * 1_000_000_000)
                )
                throw JobTimedOut()
            }
            _ = try await group.next()
            group.cancelAll()
        }
    }

    func handleExecutionError(_ error: any Error, record: JobRecord) async throws {
        switch error {
            case let control as JobControl:
                switch control {
                case let .release(delay, consumesAttempt):
                    try await release(
                        record,
                        delay: delay,
                        consumesAttempt: consumesAttempt
                    )
                case let .permanentFailure(message):
                    try await handleFailure(
                        JobFailure(
                            kind: .permanent,
                            message: message,
                            occurredAt: configuration.now()
                        ),
                        for: record,
                        forcePermanent: true
                    )
                }
            case is DurableCancellationRequested, is CancellationError:
                if try await durableCancellationRequested(id: record.id) {
                    do {
                        try await markCancelled(record)
                    } catch let queueError as DurableQueueError {
                        if case .leaseLost = queueError,
                           try await expectedCancellationAfterLeaseLoss(id: record.id) {
                            return
                        }
                        throw queueError
                    }
                } else if activeStopReasons[record.id] == .backgroundTaskExpired {
                    try await releaseForBackgroundExpiration(record)
                } else {
                    try await handleFailure(
                        JobFailure(
                            kind: .leaseExpired,
                            message: "Execution was interrupted before completion.",
                            occurredAt: configuration.now()
                        ),
                        for: record
                    )
                }
            case is JobTimedOut:
                try await handleFailure(
                    JobFailure(
                        kind: .timedOut,
                        message: "The handler exceeded its configured timeout.",
                        occurredAt: configuration.now()
                    ),
                    for: record
                )
            case let queueError as DurableQueueError:
                let kind: JobFailureKind
                switch queueError {
                case .unsupportedPayloadVersion:
                    kind = .unsupportedPayloadVersion
                case .leaseLost, .heartbeatFailed:
                    throw queueError
                case .invalidJobTypeIdentifier:
                    kind = .payloadDecodingFailed
                default:
                    kind = .handlerError
                }
                try await handleFailure(
                    JobFailure(
                        kind: kind,
                        message: String(describing: queueError),
                        occurredAt: configuration.now()
                    ),
                    for: record,
                    forcePermanent: true
                )
            case is DecodingError:
                try await handleFailure(
                    JobFailure(
                        kind: .payloadDecodingFailed,
                        message: String(describing: error),
                        occurredAt: configuration.now()
                    ),
                    for: record,
                    forcePermanent: true
                )
            default:
                try await handleFailure(
                    JobFailure(
                        kind: .handlerError,
                        message: String(describing: error),
                        occurredAt: configuration.now()
                    ),
                    for: record
                )
            }
        }

    func makeContext(for record: JobRecord, leaseToken: String) -> JobContext {
        JobContext(
            id: record.id,
            attempt: record.attempt,
            maxAttempts: record.maxAttempts,
            queuedAt: record.createdAt,
            idempotencyKey: record.idempotencyKey,
            heartbeatAction: {
                try await self.heartbeat(id: record.id, leaseToken: leaseToken)
            },
            progressAction: { fraction in
                try await self.reportProgress(
                    id: record.id,
                    leaseToken: leaseToken,
                    fraction: fraction
                )
            },
            cancellationAction: {
                await self.cancellationRequested(id: record.id)
            },
            acquireLockAction: { key, expiresAfter in
                try await self.acquireLock(
                    key: key,
                    ownerToken: leaseToken,
                    expiresAfter: expiresAfter
                )
            },
            releaseLockAction: { key in
                await self.releaseLock(key: key, ownerToken: leaseToken)
            },
            rateLimitAction: { key, maximum, window in
                try await self.consumeRateLimit(key: key, maximum: maximum, window: window)
            },
            exceptionThrottleAction: { key, maximum, decay, retryAfter in
                try await self.recordThrottledException(
                    key: key,
                    maximum: maximum,
                    decay: decay,
                    retryAfter: retryAfter
                )
            }
        )
    }
}
