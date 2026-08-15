import SwiftUI

enum DashboardVisualStyle {
    static let contentMaximumWidth: CGFloat = 1_100
    static let detailMaximumWidth: CGFloat = 920
    static let cardCornerRadius: CGFloat = 16

    static var pageBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemGroupedBackground)
        #else
        Color(nsColor: .windowBackgroundColor)
        #endif
    }

    static var cardBackground: Color {
        #if os(iOS)
        Color(uiColor: .secondarySystemGroupedBackground)
        #else
        Color(nsColor: .controlBackgroundColor)
        #endif
    }
}
