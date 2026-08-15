import SwiftUI

@MainActor
public struct DurableQueueDashboard: View {
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    @StateObject private var store: DurableQueueDashboardStore

    public init(
        queue: any DurableQueueDashboardDataSource,
        configuration: DurableQueueDashboardConfiguration = .default
    ) {
        _store = StateObject(
            wrappedValue: DurableQueueDashboardStore(
                source: queue,
                configuration: configuration
            )
        )
    }

    public var body: some View {
        Group {
            #if os(iOS)
            if horizontalSizeClass != .regular {
                DashboardCompactNavigationView(store: store)
            } else if #available(iOS 16.0, *) {
                DashboardModernNavigationView(store: store)
            } else {
                DashboardLegacyNavigationView(store: store)
            }
            #else
            DashboardModernNavigationView(store: store)
            #endif
        }
        .overlay(alignment: .top) {
            if let message = store.errorMessage {
                DashboardErrorBanner(
                    message: message,
                    dismiss: store.dismissError
                )
                .padding()
            }
        }
        .task {
            await store.observe()
        }
    }
}
