import DurableQueuer
import SwiftUI

struct DashboardJobDetailView: View {
    @ObservedObject var store: DurableQueueDashboardStore
    let jobID: JobID

    @State private var pendingOperation: DashboardOperation?

    private let sectionColumns = [
        GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top),
    ]

    private var job: JobInfo? {
        store.job(id: jobID)
    }

    var body: some View {
        Group {
            if let job {
                detailContent(job)
            } else {
                DashboardEmptyStateView(
                    title: "Job Unavailable",
                    systemImage: "questionmark.folder",
                    message: "The job was removed or is no longer available."
                )
            }
        }
        .navigationTitle("Job details")
        .toolbar {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
        }
        .task(id: jobID) {
            await store.loadPayloadSummary(for: jobID)
        }
        .confirmsDashboardOperation($pendingOperation, store: store)
        .background(DashboardVisualStyle.pageBackground.ignoresSafeArea())
    }

    private func detailContent(_ job: JobInfo) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                jobHeader(job)

                LazyVGrid(columns: sectionColumns, alignment: .leading, spacing: 16) {
                    identitySection(job)
                    executionSection(job)
                }

                if let failure = job.snapshot.lastFailure {
                    failureSection(failure)
                }

                if !job.tags.isEmpty {
                    tagsSection(job.tags)
                }

                if store.hasPayloadFormatter {
                    payloadSection()
                }

                operationsSection(job.snapshot.state)
            }
            .frame(maxWidth: DashboardVisualStyle.detailMaximumWidth)
            .padding()
        }
        .disabled(store.isPerformingOperation)
    }

    private func jobHeader(_ job: JobInfo) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    DashboardStateBadge(state: job.snapshot.state)
                    Text(job.snapshot.typeIdentifier)
                        .font(.title2.bold())
                        .textSelection(.enabled)
                    Label(job.snapshot.queue, systemImage: "shippingbox")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: job.snapshot.state.dashboardSystemImage)
                    .font(.title2)
                    .foregroundStyle(job.snapshot.state.dashboardColor)
                    .frame(width: 48, height: 48)
                    .background(
                        job.snapshot.state.dashboardColor.opacity(0.12),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
            }

            if job.snapshot.state == .running || job.snapshot.progress > 0 {
                ProgressView(value: job.snapshot.progress) {
                    Text("Progress")
                } currentValueLabel: {
                    Text(
                        job.snapshot.progress,
                        format: .percent.precision(.fractionLength(0))
                    )
                }
                .tint(job.snapshot.state.dashboardColor)
            }
        }
        .padding()
        .dashboardCard()
    }

    private func identitySection(_ job: JobInfo) -> some View {
        DashboardSectionCard(title: "Identity", systemImage: "number") {
            VStack(alignment: .leading, spacing: 14) {
                DashboardDetailRow(
                    label: "Job ID",
                    value: job.snapshot.id.description,
                    monospaced: true
                )
                DashboardDetailRow(label: "Type", value: job.snapshot.typeIdentifier)
                DashboardDetailRow(label: "Queue", value: job.snapshot.queue)
                DashboardDetailRow(
                    label: "Idempotency key",
                    value: job.snapshot.idempotencyKey,
                    monospaced: true
                )
            }
        }
    }

    private func executionSection(_ job: JobInfo) -> some View {
        DashboardSectionCard(title: "Execution", systemImage: "bolt.horizontal.fill") {
            VStack(alignment: .leading, spacing: 14) {
                DashboardDetailRow(
                    label: "Lane",
                    value: job.snapshot.lane.dashboardTitle
                )
                if !job.snapshot.requirements.isEmpty {
                    DashboardDetailRow(
                        label: "Requirements",
                        value: requirementsDescription(job.snapshot.requirements)
                    )
                }
                DashboardDetailRow(
                    label: "Attempts",
                    value: "\(job.snapshot.attempt) of \(job.snapshot.maxAttempts)"
                )
                DashboardDetailRow(
                    label: "Available",
                    value: format(job.snapshot.availableAt)
                )
                if let deadline = job.snapshot.deadline {
                    DashboardDetailRow(label: "Deadline", value: format(deadline))
                }
                DashboardDetailRow(label: "Created", value: format(job.snapshot.createdAt))
                DashboardDetailRow(label: "Updated", value: format(job.snapshot.updatedAt))
                if let finishedAt = job.snapshot.finishedAt {
                    DashboardDetailRow(label: "Finished", value: format(finishedAt))
                }
                if let stopReason = job.snapshot.stopReason {
                    DashboardDetailRow(label: "Stop reason", value: stopReason.rawValue)
                }
            }
        }
    }

    private func failureSection(_ failure: JobFailure) -> some View {
        DashboardSectionCard(title: "Last failure", systemImage: "exclamationmark.triangle.fill") {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    DashboardDetailRow(label: "Kind", value: failure.kind.rawValue)
                    DashboardDetailRow(label: "Occurred", value: format(failure.occurredAt))
                }
                Text(failure.message)
                    .font(.body)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func tagsSection(_ tags: Set<String>) -> some View {
        DashboardSectionCard(title: "Tags", systemImage: "tag.fill") {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 110), spacing: 8)],
                alignment: .leading,
                spacing: 8
            ) {
                ForEach(tags.sorted(), id: \.self) { tag in
                    Text(tag)
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.accentColor.opacity(0.10), in: Capsule())
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func payloadSection() -> some View {
        DashboardSectionCard(title: "Payload summary", systemImage: "doc.text.magnifyingglass") {
            if let summary = store.payloadSummary(for: jobID) {
                Text(summary)
                    .font(.body.monospaced())
                    .textSelection(.enabled)
            } else if store.hasLoadedPayload(for: jobID) {
                Text("The host formatter did not provide a summary.")
                    .foregroundStyle(.secondary)
            } else {
                ProgressView("Formatting payload")
            }
        }
    }

    private func operationsSection(_ state: JobState) -> some View {
        DashboardSectionCard(title: "Operations", systemImage: "wrench.and.screwdriver.fill") {
            operationButtons(for: state)
        }
    }

    @ViewBuilder
    private func operationButtons(for state: JobState) -> some View {
        switch state {
        case .blocked, .queued, .running:
            operationButton(
                "Cancel job",
                systemImage: "xmark.circle.fill",
                role: .destructive
            ) {
                pendingOperation = .cancel(jobID)
            }
        case .failed:
            VStack(spacing: 10) {
                operationButton(
                    "Retry job",
                    systemImage: "arrow.clockwise.circle.fill",
                    prominent: true
                ) {
                    pendingOperation = .retry(jobID)
                }
                operationButton(
                    "Forget job",
                    systemImage: "trash.fill",
                    role: .destructive
                ) {
                    pendingOperation = .forget(jobID)
                }
            }
        case .succeeded, .cancelled:
            operationButton(
                "Forget job",
                systemImage: "trash.fill",
                role: .destructive
            ) {
                pendingOperation = .forget(jobID)
            }
        }
    }

    @ViewBuilder
    private func operationButton(
        _ title: String,
        systemImage: String,
        role: ButtonRole? = nil,
        prominent: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        if prominent {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        } else {
            Button(role: role, action: action) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    private func format(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    private func requirementsDescription(_ requirements: JobRequirements) -> String {
        var values: [String] = []
        if requirements.contains(.networkConnectivity) {
            values.append("Network connectivity")
        }
        if requirements.contains(.externalPower) {
            values.append("External power")
        }
        return values.joined(separator: ", ")
    }
}
