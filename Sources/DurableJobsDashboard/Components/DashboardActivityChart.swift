import DurableJobs
import SwiftUI

struct DashboardActivityChart: View {
    let buckets: [QueueActivityBucket]

    private var maximumCount: Int {
        max(1, buckets.map { $0.succeeded + $0.failed }.max() ?? 0)
    }

    private var hasActivity: Bool {
        buckets.contains { $0.succeeded > 0 || $0.failed > 0 }
    }

    private var succeededTotal: Int {
        buckets.reduce(0) { $0 + $1.succeeded }
    }

    private var failedTotal: Int {
        buckets.reduce(0) { $0 + $1.failed }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Activity")
                        .font(.headline)
                    Text("Successful and failed jobs by hour")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                activityTotal(title: "Completed", count: succeededTotal, color: .green)
                activityTotal(title: "Failed", count: failedTotal, color: .red)
            }

            if hasActivity {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(buckets, id: \.start) { bucket in
                        VStack(spacing: 1) {
                            Spacer(minLength: 0)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.red)
                                .frame(height: height(for: bucket.failed))
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color.green)
                                .frame(height: height(for: bucket.succeeded))
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(bucket.start.formatted(date: .omitted, time: .shortened))
                        .accessibilityValue(
                            "\(bucket.succeeded) completed, \(bucket.failed) failed"
                        )
                    }
                }
                .frame(height: 120)
                .overlay(alignment: .bottom) {
                    Divider()
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .font(.title2)
                    Text("No activity in the last 24 hours")
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .padding()
        .dashboardCard()
    }

    private func height(for count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return max(3, CGFloat(count) / CGFloat(maximumCount) * 100)
    }

    private func activityTotal(title: String, count: Int, color: Color) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(count, format: .number)
                .font(.headline.monospacedDigit())
                .foregroundStyle(color)
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
