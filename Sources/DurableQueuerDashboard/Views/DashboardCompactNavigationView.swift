#if os(iOS)
import SwiftUI

struct DashboardCompactNavigationView: View {
    @ObservedObject var store: DurableQueueDashboardStore
    @State private var selection: DashboardCompactTab = .overview

    var body: some View {
        TabView(selection: $selection) {
            NavigationView {
                DashboardOverviewView(store: store)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Overview", systemImage: "gauge")
            }
            .tag(DashboardCompactTab.overview)

            NavigationView {
                DashboardCompactJobsView(store: store)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Jobs", systemImage: "tray.full.fill")
            }
            .tag(DashboardCompactTab.jobs)

            NavigationView {
                DashboardCompactQueuesView(store: store)
            }
            .navigationViewStyle(.stack)
            .tabItem {
                Label("Queues", systemImage: "shippingbox.fill")
            }
            .tag(DashboardCompactTab.queues)
        }
        .onChange(of: selection) { newValue in
            switch newValue {
            case .overview:
                store.destination = .overview
            case .jobs:
                if store.destination == .overview {
                    store.destination = .all
                }
            case .queues:
                break
            }
        }
        .onChange(of: store.destination) { newValue in
            switch newValue {
            case .overview:
                selection = .overview
            default:
                selection = .jobs
            }
        }
    }
}
#endif
