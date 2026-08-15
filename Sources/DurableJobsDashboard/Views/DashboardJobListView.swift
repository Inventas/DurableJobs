import SwiftUI

struct DashboardJobListView: View {
    @ObservedObject var store: DurableQueueDashboardStore

    var body: some View {
        List {
            if store.jobs.isEmpty && store.isLoadingJobs {
                ProgressView("Loading jobs")
                    .frame(maxWidth: .infinity, minHeight: 160)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            } else if store.jobs.isEmpty {
                DashboardEmptyStateView(
                    title: "No Jobs",
                    systemImage: "tray",
                    message: "No jobs match this filter."
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            } else {
                ForEach(store.jobs, id: \.snapshot.id) { job in
                    NavigationLink {
                        DashboardJobDetailView(
                            store: store,
                            jobID: job.snapshot.id
                        )
                    } label: {
                        DashboardJobRow(job: job)
                            .padding(12)
                            .dashboardCard()
                    }
                    .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if store.canLoadMore {
                    Button {
                        Task {
                            await store.loadJobs(reset: false)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            if store.isLoadingJobs {
                                ProgressView()
                            } else {
                                Text("Load More")
                            }
                            Spacer()
                        }
                    }
                    .disabled(store.isLoadingJobs)
                    .buttonStyle(.bordered)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .listStyle(.plain)
        .background(DashboardVisualStyle.pageBackground.ignoresSafeArea())
        .navigationTitle(store.destination.title)
        .refreshable {
            await store.refresh()
        }
        .toolbar {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .task(id: store.destination) {
            await store.loadJobs(reset: true)
        }
    }
}
