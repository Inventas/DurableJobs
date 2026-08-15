import SwiftUI

struct DashboardCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DashboardVisualStyle.cardBackground)
            .clipShape(
                RoundedRectangle(
                    cornerRadius: DashboardVisualStyle.cardCornerRadius,
                    style: .continuous
                )
            )
            .overlay {
                RoundedRectangle(
                    cornerRadius: DashboardVisualStyle.cardCornerRadius,
                    style: .continuous
                )
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
    }
}

extension View {
    func dashboardCard() -> some View {
        modifier(DashboardCardModifier())
    }
}
