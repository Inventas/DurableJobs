import DurableQueuer
import SwiftUI

struct DashboardMetricCard: View {
    let state: JobState
    let count: Int
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: state.dashboardSystemImage)
                        .font(.headline)
                        .foregroundStyle(state.dashboardColor)
                        .frame(width: 34, height: 34)
                        .background(state.dashboardColor.opacity(0.13), in: Circle())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(count, format: .number)
                        .font(.title.bold())
                        .foregroundStyle(.primary)
                    Text(state.dashboardTitle)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .dashboardCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(state.dashboardTitle), \(count) jobs")
        .accessibilityHint("Show these jobs")
    }
}
