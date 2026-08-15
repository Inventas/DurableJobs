import SwiftUI

struct SampleControlBar: View {
    @ObservedObject var model: DashboardSampleModel

    var body: some View {
        #if os(macOS)
        macOSBar
        #else
        iOSBar
        #endif
    }

    #if os(macOS)
    private var macOSBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Label("Sample lab", systemImage: "testtube.2")
                    .font(.headline)

                Spacer()

                Button {
                    Task { await model.seedExamples() }
                } label: {
                    Label("Seed", systemImage: "square.stack.3d.up.fill")
                }

                addJobMenu
                    .menuStyle(.borderlessButton)
                    .fixedSize()

                runButton
                    .buttonStyle(.borderedProminent)
            }

            statusRow
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
    #endif

    #if os(iOS)
    private var iOSBar: some View {
        VStack(spacing: 8) {
            statusRow

            HStack(spacing: 12) {
                Menu {
                    Button {
                        Task { await model.seedExamples() }
                    } label: {
                        Label("Seed examples", systemImage: "square.stack.3d.up.fill")
                    }
                    Divider()
                    addJobButtons
                } label: {
                    Label("Demo jobs", systemImage: "testtube.2")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)

                runButton
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(.horizontal)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }
    #endif

    private var addJobMenu: some View {
        Menu {
            addJobButtons
        } label: {
            Label("Add job", systemImage: "plus")
        }
    }

    private var addJobButtons: some View {
        Group {
            Button("Pending job") {
                Task { await model.addPendingJob() }
            }
            Button("Failing job") {
                Task { await model.addFailingJob() }
            }
            Button("Delayed job") {
                Task { await model.addDelayedJob() }
            }
            Button("Long-running job") {
                Task { await model.addLongRunningJob() }
            }
        }
    }

    private var runButton: some View {
        Button {
            Task { await model.runQueue() }
        } label: {
            if model.isRunning {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Running")
                }
            } else {
                Label("Run due jobs", systemImage: "play.fill")
            }
        }
        .disabled(model.isRunning)
    }

    @ViewBuilder
    private var statusRow: some View {
        if let message = model.errorMessage ?? model.statusMessage {
            HStack(spacing: 8) {
                Image(
                    systemName: model.errorMessage == nil
                        ? "checkmark.circle.fill"
                        : "exclamationmark.triangle.fill"
                )
                Text(message)
                    .lineLimit(2)
                Spacer(minLength: 8)
                Button {
                    model.dismissMessage()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss message")
            }
            .font(.caption)
            .foregroundStyle(model.errorMessage == nil ? Color.secondary : Color.red)
        }
    }
}
