import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct DashboardSidebarView: View {
    @ObservedObject var store: DurableQueueDashboardStore
    @Binding var selection: DashboardDestination?

    var body: some View {
        List(selection: $selection) {
            Section {
                NavigationLink(value: DashboardDestination.overview) {
                    Label("Overview", systemImage: "gauge")
                }
            }
            Section("Jobs") {
                ForEach(DashboardDestination.jobDestinations) { destination in
                    NavigationLink(value: destination) {
                        HStack {
                            Label(destination.title, systemImage: destination.systemImage)
                            Spacer()
                            if let count = count(for: destination), count > 0 {
                                Text(count, format: .number)
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            if let metrics = store.metrics, !metrics.queues.isEmpty {
                Section("Queues") {
                    ForEach(metrics.queues, id: \.queue) { queue in
                        NavigationLink(value: DashboardDestination.queue(queue.queue)) {
                            HStack {
                                Label(queue.queue, systemImage: "shippingbox")
                                Spacer()
                                if queue.stateCounts.total > 0 {
                                    Text(queue.stateCounts.total, format: .number)
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                if queue.isPaused {
                                    Image(systemName: "pause.circle.fill")
                                        .foregroundStyle(.orange)
                                        .accessibilityLabel("Paused")
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Queue Monitor")
    }

    private func count(for destination: DashboardDestination) -> Int? {
        guard let counts = store.metrics?.stateCounts else { return nil }
        return switch destination {
        case .all:
            counts.total
        case .blocked:
            counts.blocked
        case .pending:
            counts.queued
        case .running:
            counts.running
        case .completed:
            counts.succeeded
        case .failed:
            counts.failed
        case .cancelled:
            counts.cancelled
        case .overview, .queue:
            nil
        }
    }
}
