import SwiftUI

struct DashboardEmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 180)
        .padding()
        .accessibilityElement(children: .combine)
    }
}
