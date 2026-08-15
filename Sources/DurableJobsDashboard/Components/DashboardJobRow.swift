import DurableJobs
import SwiftUI

struct DashboardJobRow: View {
    let job: JobInfo

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: job.snapshot.state.dashboardSystemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(job.snapshot.state.dashboardColor)
                .frame(width: 34, height: 34)
                .background(
                    job.snapshot.state.dashboardColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(job.snapshot.typeIdentifier)
                        .font(.headline)
                        .lineLimit(1)
                    Spacer()
                    Text(job.snapshot.createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                HStack(spacing: 12) {
                    DashboardStateBadge(state: job.snapshot.state)
                    Label(job.snapshot.queue, systemImage: "shippingbox")
                    if job.snapshot.attempt > 0 {
                        Label(
                            "\(job.snapshot.attempt)/\(job.snapshot.maxAttempts)",
                            systemImage: "arrow.triangle.2.circlepath"
                        )
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if job.snapshot.state == .running || job.snapshot.progress > 0 {
                    ProgressView(value: job.snapshot.progress)
                        .tint(job.snapshot.state.dashboardColor)
                }

                if let failure = job.snapshot.lastFailure {
                    Text(failure.message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(job.snapshot.typeIdentifier), \(job.snapshot.state.dashboardTitle), "
                + "queue \(job.snapshot.queue)"
        )
    }
}
