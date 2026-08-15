import SwiftUI

struct DashboardLegacyNavigationView: View {
    @ObservedObject var store: DurableQueueDashboardStore

    var body: some View {
        NavigationView {
            List {
                Section {
                    legacyLink(to: .overview)
                }
                Section("Jobs") {
                    ForEach(DashboardDestination.jobDestinations) { destination in
                        legacyLink(to: destination)
                    }
                }
                if let metrics = store.metrics, !metrics.queues.isEmpty {
                    Section("Queues") {
                        ForEach(metrics.queues, id: \.queue) { queue in
                            legacyLink(to: .queue(queue.queue))
                        }
                    }
                }
            }
            .navigationTitle("Durable Queuer")

            DashboardDestinationView(store: store)
        }
        .navigationViewStyle(.columns)
    }

    private func legacyLink(to destination: DashboardDestination) -> some View {
        NavigationLink {
            DashboardDestinationView(store: store)
                .onAppear {
                    store.destination = destination
                }
        } label: {
            Label(destination.title, systemImage: destination.systemImage)
        }
    }
}
