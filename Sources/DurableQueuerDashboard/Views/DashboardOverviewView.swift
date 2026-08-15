import DurableQueuer
import SwiftUI

struct DashboardOverviewView: View {
    @ObservedObject var store: DurableQueueDashboardStore
    @State private var pendingOperation: DashboardOperation?

    private let metricColumns = [
        GridItem(.adaptive(minimum: 145), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            if let metrics = store.metrics {
                LazyVStack(alignment: .leading, spacing: 24) {
                    header(metrics)

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(
                            title: "Current state",
                            subtitle: "Live totals across all queues"
                        )
                        LazyVGrid(columns: metricColumns, spacing: 12) {
                            metricCard(state: .blocked, count: metrics.stateCounts.blocked)
                            metricCard(state: .queued, count: metrics.stateCounts.queued)
                            metricCard(state: .running, count: metrics.stateCounts.running)
                            metricCard(state: .succeeded, count: metrics.stateCounts.succeeded)
                            metricCard(state: .failed, count: metrics.stateCounts.failed)
                            metricCard(state: .cancelled, count: metrics.stateCounts.cancelled)
                        }
                    }

                    DashboardActivityChart(buckets: metrics.activity)

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeader(
                            title: "Queues",
                            subtitle: "Inspect work or pause queue processing"
                        )
                        if metrics.queues.isEmpty {
                            DashboardEmptyStateView(
                                title: "No Queues",
                                systemImage: "shippingbox",
                                message: "Queues appear after a job is dispatched or a queue is paused."
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
                    }

                    Label(
                        "Updated \(metrics.capturedAt.formatted(date: .omitted, time: .standard))",
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(maxWidth: DashboardVisualStyle.contentMaximumWidth)
                .padding()
            } else {
                ProgressView("Loading dashboard")
                    .frame(maxWidth: .infinity, minHeight: 240)
            }
        }
        .navigationTitle("Dashboard")
        .refreshable {
            await store.refresh()
        }
        .toolbar {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .confirmsDashboardOperation($pendingOperation, store: store)
        .background(DashboardVisualStyle.pageBackground.ignoresSafeArea())
    }

    private func header(_ metrics: QueueMetricsSnapshot) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "waveform.path.ecg.rectangle.fill")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 48, height: 48)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Queue monitor")
                    .font(.title.bold())
                Text("\(metrics.stateCounts.total) jobs across \(metrics.queues.count) queues")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.title3.bold())
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func metricCard(state: JobState, count: Int) -> some View {
        DashboardMetricCard(state: state, count: count) {
            switch state {
            case .blocked:
                store.destination = .blocked
            case .queued:
                store.destination = .pending
            case .running:
                store.destination = .running
            case .succeeded:
                store.destination = .completed
            case .failed:
                store.destination = .failed
            case .cancelled:
                store.destination = .cancelled
            }
        }
    }
}
