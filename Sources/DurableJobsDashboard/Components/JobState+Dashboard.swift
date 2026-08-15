import DurableJobs
import SwiftUI

extension JobState {
    var dashboardTitle: String {
        switch self {
        case .blocked:
            "Blocked"
        case .queued:
            "Pending"
        case .running:
            "Running"
        case .succeeded:
            "Completed"
        case .failed:
            "Failed"
        case .cancelled:
            "Cancelled"
        }
    }

    var dashboardSystemImage: String {
        switch self {
        case .blocked:
            "link"
        case .queued:
            "clock.fill"
        case .running:
            "bolt.fill"
        case .succeeded:
            "checkmark.circle.fill"
        case .failed:
            "exclamationmark.triangle.fill"
        case .cancelled:
            "xmark.circle.fill"
        }
    }

    var dashboardColor: Color {
        switch self {
        case .blocked:
            .purple
        case .queued:
            .orange
        case .running:
            .blue
        case .succeeded:
            .green
        case .failed:
            .red
        case .cancelled:
            .secondary
        }
    }
}
