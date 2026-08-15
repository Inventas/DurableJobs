import Foundation

extension DurableQueue {
    func emit(kind: JobEvent.Kind, jobID: JobID) async {
        let snapshot = try? await status(jobID)
        let event = JobEvent(
            jobID: jobID,
            kind: kind,
            snapshot: snapshot,
            date: configuration.now()
        )
        configuration.logger?(
            QueueLogEntry(
                level: kind == .leaseLost ? .warning : .info,
                event: kind.rawValue,
                jobID: jobID,
                date: event.date,
                fields: snapshot.map {
                    ["state": $0.state.rawValue, "queue": $0.queue, "type": $0.typeIdentifier]
                } ?? [:]
            )
        )
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
        switch kind {
        case .dispatched, .retryScheduled, .succeeded, .failed, .cancelled,
             .recovered, .retried, .forgotten, .updated:
            await schedulingCoordinator?.reconcile()
        case .claimed, .progress, .leaseLost:
            break
        }
    }

    func removeEventContinuation(_ id: UUID) {
        eventContinuations[id] = nil
    }
}
