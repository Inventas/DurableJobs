import DurableJobs

extension JobExecutionLane {
    var dashboardTitle: String {
        switch self {
        case .refresh:
            "Refresh"
        case .processing:
            "Processing"
        case .processingNetwork:
            "Processing with Network"
        case .processingPower:
            "Processing with Power"
        case .processingNetworkAndPower:
            "Processing with Network and Power"
        }
    }
}
