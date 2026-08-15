import DurableQueuer
import SwiftUI

struct DashboardStateBadge: View {
    let state: JobState

    var body: some View {
        Label(state.dashboardTitle, systemImage: state.dashboardSystemImage)
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(.semibold))
            .foregroundStyle(state.dashboardColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(state.dashboardColor.opacity(0.12))
            .clipShape(Capsule())
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .overlay {
                Capsule()
                    .stroke(state.dashboardColor.opacity(0.18), lineWidth: 1)
            }
    }
}
