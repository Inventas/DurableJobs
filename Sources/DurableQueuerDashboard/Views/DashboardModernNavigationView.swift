import SwiftUI

@available(iOS 16.0, macOS 13.0, *)
struct DashboardModernNavigationView: View {
    @ObservedObject var store: DurableQueueDashboardStore
    @State private var selection: DashboardDestination? = .overview

    var body: some View {
        NavigationSplitView {
            DashboardSidebarView(store: store, selection: $selection)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            NavigationStack {
                DashboardDestinationView(store: store)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .onChange(of: selection) { newValue in
            guard let newValue else { return }
            store.destination = newValue
        }
        .onChange(of: store.destination) { newValue in
            selection = newValue
        }
    }
}
