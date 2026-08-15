import SwiftUI

@main
struct DurableJobsDashboardSampleApp: App {
    @StateObject private var model = DashboardSampleModel()

    var body: some Scene {
        #if os(macOS)
        WindowGroup("DurableJobs Dashboard") {
            DashboardSampleView(model: model)
        }
        .defaultSize(width: 1_180, height: 760)
        #else
        WindowGroup {
            DashboardSampleView(model: model)
        }
        #endif
    }
}
