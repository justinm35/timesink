import AppKit
import SwiftUI

/// Quick-glance menu bar popover showing current activity and today's summary.
struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @State private var todayBreakdown: [AppDatabase.CategoryTimeSummary] = []
    @State private var totalTodaySeconds: Int = 0
    @State private var realmBreakdown = AppDatabase.RealmBreakdown(workSeconds: 0, personalSeconds: 0)
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 10) {
            // Header
            HStack {
                Text("TimeSink")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(appState.isTrackingActive ? .green : .red)
                    .frame(width: 8, height: 8)
                Text(appState.isTrackingActive ? "Tracking" : "Paused")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()

            // Current activity
            if let activity = appState.currentActivity {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current Activity")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    HStack {
                        Text(activity.isIdle ? "Idle" : activity.appName)
                            .font(.body)
                            .fontWeight(.medium)
                        Spacer()
                        Text(DateFormatting.formatDuration(seconds: Int(Date().timeIntervalSince(activity.startedAt))))
                            .font(.body)
                            .monospacedDigit()
                    }

                    if !activity.isIdle, let detail = activity.detail ?? Optional(activity.windowTitle), !detail.isEmpty {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(8)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Text("No active tracking")
                    .font(.body)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }

            Divider()

            // Today summary
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(DateFormatting.formatDuration(seconds: totalTodaySeconds))
                        .font(.body)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                }

                // Top 3 categories
                ForEach(todayBreakdown.prefix(3), id: \.categoryName) { item in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(Color(hex: item.categoryColor ?? "#888888"))
                            .frame(width: 8, height: 8)

                        Text(item.categoryName ?? "Uncategorized")
                            .font(.caption)

                        Spacer()

                        // Mini progress bar
                        GeometryReader { geo in
                            RoundedRectangle(cornerRadius: 2)
                                .fill(Color(hex: item.categoryColor ?? "#888888").opacity(0.2))
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(hex: item.categoryColor ?? "#888888"))
                                        .frame(width: max(2, geo.size.width * barWidth(for: item)))
                                }
                        }
                        .frame(width: 60, height: 6)

                        Text(DateFormatting.formatDuration(seconds: item.totalSeconds))
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }

                if todayBreakdown.isEmpty {
                    Text("No categorized data yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity)
                } else if appState.categoryStore.hasRealmCategories {
                    Text("Work: \(DateFormatting.formatDuration(seconds: realmBreakdown.workSeconds)) · Personal: \(DateFormatting.formatDuration(seconds: realmBreakdown.personalSeconds))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            // Actions
            HStack {
                Button(appState.isTrackingActive ? "Pause" : "Resume") {
                    appState.toggleTracking()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Categorize Now") {
                    Task {
                        await appState.categorizeNow()
                        loadTodayData()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Spacer()

                Button("Open TimeSink") {
                    openWindow(id: "main")
                    DispatchQueue.main.async {
                        NSApp.activate(ignoringOtherApps: true)
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear {
            loadTodayData()
        }
    }

    // MARK: - Data

    private func loadTodayData() {
        let (start, end) = DateFormatting.dayRange(for: Date())
        do {
            todayBreakdown = try appState.database.fetchCategoryBreakdown(from: start, to: end)
            totalTodaySeconds = try appState.database.fetchTotalTrackedSeconds(from: start, to: end)
            realmBreakdown = try appState.database.fetchRealmBreakdown(from: start, to: end)
        } catch {
            print("Failed to load today's data: \(error)")
        }
    }

    private func barWidth(for item: AppDatabase.CategoryTimeSummary) -> CGFloat {
        guard totalTodaySeconds > 0 else { return 0 }
        return CGFloat(item.totalSeconds) / CGFloat(totalTodaySeconds)
    }
}
