#if os(iOS)
import SwiftUI

struct DashboardCompactQueuesView: View {
    @ObservedObject var store: DurableQueueDashboardStore
    @State private var pendingOperation: DashboardOperation?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let metrics = store.metrics {
                    if metrics.queues.isEmpty {
                        DashboardEmptyStateView(
                            title: "No Queues",
                            systemImage: "shippingbox",
                            message: "Queues appear after a job is dispatched or paused."
                        )
                        .dashboardCard()
                    } else {
                        ForEach(metrics.queues, id: \.queue) { queue in
                            DashboardQueueRow(
                                metrics: queue,
                                inspect: {
                                    store.destination = .queue(queue.queue)
                                },
                                requestOperation: { operation in
                                    pendingOperation = operation
                                }
                            )
                        }
                    }
                } else {
                    ProgressView("Loading queues")
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
            .padding()
        }
        .navigationTitle("Queues")
        .refreshable {
            await store.refresh()
        }
        .toolbar {
            Button {
                Task { await store.refresh() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .background(DashboardVisualStyle.pageBackground.ignoresSafeArea())
        .confirmsDashboardOperation($pendingOperation, store: store)
    }
}
#endif
