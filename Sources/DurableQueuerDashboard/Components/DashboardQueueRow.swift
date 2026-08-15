import DurableQueuer
import SwiftUI

struct DashboardQueueRow: View {
    let metrics: QueueMetrics
    let inspect: () -> Void
    let requestOperation: (DashboardOperation) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button(action: inspect) {
                    HStack(spacing: 10) {
                        Image(systemName: "shippingbox.fill")
                            .foregroundStyle(.tint)
                            .frame(width: 32, height: 32)
                            .background(Color.accentColor.opacity(0.12), in: Circle())
                        VStack(alignment: .leading, spacing: 2) {
                            Text(metrics.queue)
                                .font(.headline)
                            Text("\(metrics.stateCounts.total) jobs")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if metrics.isPaused {
                            Label("Paused", systemImage: "pause.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.orange.opacity(0.12), in: Capsule())
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityHint("Show jobs in this queue")

                Spacer()

                Button(metrics.isPaused ? "Resume" : "Pause") {
                    requestOperation(
                        metrics.isPaused
                            ? .resume(metrics.queue)
                            : .pause(metrics.queue)
                    )
                }
                .buttonStyle(.bordered)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 78), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                countLabel("Pending", metrics.stateCounts.queued, color: .orange)
                countLabel("Running", metrics.stateCounts.running, color: .blue)
                countLabel("Done", metrics.stateCounts.succeeded, color: .green)
                countLabel("Failed", metrics.stateCounts.failed, color: .red)
            }
        }
        .padding()
        .dashboardCard()
    }

    private func countLabel(_ title: String, _ count: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(count, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
