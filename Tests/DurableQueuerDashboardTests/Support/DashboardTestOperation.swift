import DurableQueuer

enum DashboardTestOperation: Equatable, Sendable {
    case retry(JobID)
    case cancel(JobID)
    case forget(JobID)
    case pause(String)
    case resume(String)
}
