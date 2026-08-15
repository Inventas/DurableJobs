import SwiftUI

struct DashboardDestinationView: View {
    @ObservedObject var store: DurableQueueDashboardStore

    var body: some View {
        Group {
            if store.destination == .overview {
                DashboardOverviewView(store: store)
            } else {
                DashboardJobListView(store: store)
            }
        }
    }
}
