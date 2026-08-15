#if os(iOS)
import SwiftUI

struct DashboardCompactJobsView: View {
    @ObservedObject var store: DurableQueueDashboardStore

    var body: some View {
        DashboardJobListView(store: store)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(DashboardDestination.jobDestinations) { destination in
                            Button {
                                store.destination = destination
                            } label: {
                                Label(destination.title, systemImage: destination.systemImage)
                            }
                        }

                        if let metrics = store.metrics, !metrics.queues.isEmpty {
                            Divider()
                            ForEach(metrics.queues, id: \.queue) { queue in
                                Button {
                                    store.destination = .queue(queue.queue)
                                } label: {
                                    Label(queue.queue, systemImage: "shippingbox")
                                }
                            }
                        }
                    } label: {
                        Label(store.destination.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
    }
}
#endif
