import DurableQueuer

enum DashboardDestination: Hashable, Identifiable {
    case overview
    case all
    case blocked
    case pending
    case running
    case completed
    case failed
    case cancelled
    case queue(String)

    static let jobDestinations: [DashboardDestination] = [
        .all,
        .blocked,
        .pending,
        .running,
        .completed,
        .failed,
        .cancelled,
    ]

    var id: String {
        switch self {
        case .overview:
            "overview"
        case .all:
            "all"
        case .blocked:
            "blocked"
        case .pending:
            "pending"
        case .running:
            "running"
        case .completed:
            "completed"
        case .failed:
            "failed"
        case .cancelled:
            "cancelled"
        case let .queue(name):
            "queue:\(name)"
        }
    }

    var title: String {
        switch self {
        case .overview:
            "Dashboard"
        case .all:
            "All Jobs"
        case .blocked:
            "Blocked"
        case .pending:
            "Pending"
        case .running:
            "Running"
        case .completed:
            "Completed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        case let .queue(name):
            name
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "gauge"
        case .all:
            "tray.full"
        case .blocked:
            "link"
        case .pending:
            "clock"
        case .running:
            "bolt"
        case .completed:
            "checkmark.circle"
        case .failed:
            "exclamationmark.triangle"
        case .cancelled:
            "xmark.circle"
        case .queue:
            "shippingbox"
        }
    }

    var queryState: JobState? {
        switch self {
        case .blocked:
            .blocked
        case .pending:
            .queued
        case .running:
            .running
        case .completed:
            .succeeded
        case .failed:
            .failed
        case .cancelled:
            .cancelled
        case .overview, .all, .queue:
            nil
        }
    }

    var queryQueue: String? {
        if case let .queue(name) = self {
            name
        } else {
            nil
        }
    }

    var showsJobs: Bool {
        self != .overview
    }
}
