import DurableQueuer
import DurableQueuerDashboard
import SwiftUI

struct DashboardSampleView: View {
    @ObservedObject var model: DashboardSampleModel

    var body: some View {
        Group {
            if let queue = model.queue {
                #if os(macOS)
                VStack(spacing: 0) {
                    SampleControlBar(model: model)
                    Divider()
                    dashboard(queue: queue)
                }
                #else
                VStack(spacing: 0) {
                    SampleControlBar(model: model)
                    Divider()
                    dashboard(queue: queue)
                }
                #endif
            } else {
                unavailableView
            }
        }
        .frame(minWidth: 320, minHeight: 480)
        .tint(.indigo)
        .task {
            await model.seedIfNeeded()
        }
    }

    private func dashboard(queue: DurableQueue) -> some View {
        DurableQueueDashboard(
            queue: queue,
            configuration: model.dashboardConfiguration
        )
    }

    private var unavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("The sample queue is unavailable")
                .font(.title2.bold())
            Text(model.errorMessage ?? "The database could not be opened.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
