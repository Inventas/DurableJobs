import DurableJobs

enum DashboardOperation: Identifiable {
    case retry(JobID)
    case cancel(JobID)
    case forget(JobID)
    case pause(String)
    case resume(String)

    var id: String {
        switch self {
        case let .retry(id):
            "retry:\(id)"
        case let .cancel(id):
            "cancel:\(id)"
        case let .forget(id):
            "forget:\(id)"
        case let .pause(queue):
            "pause:\(queue)"
        case let .resume(queue):
            "resume:\(queue)"
        }
    }

    var title: String {
        switch self {
        case .retry:
            "Retry Job?"
        case .cancel:
            "Cancel Job?"
        case .forget:
            "Forget Job?"
        case .pause:
            "Pause Queue?"
        case .resume:
            "Resume Queue?"
        }
    }

    var message: String {
        switch self {
        case .retry:
            "The failed job will return to the pending queue and can run again."
        case .cancel:
            "The job will stop when its handler cooperates with cancellation."
        case .forget:
            "The terminal job and its tags will be deleted permanently."
        case let .pause(queue):
            "New jobs in the \(queue) queue will not start until the queue resumes."
        case let .resume(queue):
            "Pending jobs in the \(queue) queue can start again."
        }
    }

    var confirmationLabel: String {
        switch self {
        case .retry:
            "Retry"
        case .cancel:
            "Cancel Job"
        case .forget:
            "Forget"
        case .pause:
            "Pause"
        case .resume:
            "Resume"
        }
    }

    var isDestructive: Bool {
        switch self {
        case .cancel, .forget, .pause:
            true
        case .retry, .resume:
            false
        }
    }

    var jobID: JobID? {
        switch self {
        case let .retry(id), let .cancel(id), let .forget(id):
            id
        case .pause, .resume:
            nil
        }
    }
}
