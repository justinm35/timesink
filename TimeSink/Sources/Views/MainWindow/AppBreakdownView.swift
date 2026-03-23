import AppKit
import SwiftUI

struct AppBreakdownView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedDate = Date()
    @State private var selectedRealmFilter: RealmFilter = .all
    @State private var appSummaries: [AppDatabase.AppTimeSummary] = []
    @State private var detailBreakdowns: [String: [AppDatabase.AppDetailSummary]] = [:]
    @State private var expandedApps: Set<String> = []
    @State private var animateDistribution = false
    @State private var animateCards = false

    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    enum RealmFilter: String, CaseIterable {
        case all = "All"
        case work = "Work"
        case personal = "Personal"

        var realmValue: String? {
            switch self {
            case .all: return nil
            case .work: return "work"
            case .personal: return "personal"
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerView

                if appSummaries.isEmpty {
                    emptyState
                } else {
                    AppDistributionBar(appSummaries: appSummaries)

                    LazyVStack(spacing: 14) {
                        ForEach(Array(appSummaries.enumerated()), id: \.element.appName) { index, summary in
                            AppBreakdownCard(
                                summary: summary,
                                details: detailBreakdowns[summary.appName] ?? [],
                                totalTrackedSeconds: totalTrackedSeconds,
                                isExpanded: expandedApps.contains(summary.appName),
                                onToggleExpanded: { toggleExpanded(summary.appName) },
                                animateIn: animateCards,
                                order: index
                            )
                        }
                    }
                }
            }
            .frame(maxWidth: 880, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .onAppear { loadData(animated: false) }
        .onChange(of: appState.categoryStore.hasRealmCategories) { _, hasRealms in
            if !hasRealms {
                selectedRealmFilter = .all
            }
        }
        .onChange(of: selectedDate) { _, _ in loadData(animated: true) }
        .onChange(of: selectedRealmFilter) { _, _ in loadData(animated: true) }
        .onReceive(refreshTimer) { _ in loadData(animated: false) }
    }

    private var totalTrackedSeconds: Int {
        appSummaries.reduce(0) { $0 + $1.totalSeconds }
    }

    private var topApp: AppDatabase.AppTimeSummary? {
        appSummaries.max(by: { $0.totalSeconds < $1.totalSeconds })
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("By App")
                        .font(.title2)
                        .fontWeight(.bold)

                    Text(DateFormatting.timelineDayTitle(for: selectedDate))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                HStack(spacing: 8) {
                    Button(action: { moveDate(by: -1) }) {
                        Image(systemName: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    DatePicker("", selection: $selectedDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    Button(action: { moveDate(by: 1) }) {
                        Image(systemName: "chevron.right")
                    }
                    .buttonStyle(.bordered)

                    todayButton
                }
            }

            HStack(spacing: 10) {
                if appState.categoryStore.hasRealmCategories {
                    Picker("Realm", selection: $selectedRealmFilter) {
                        ForEach(RealmFilter.allCases, id: \.self) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }

                AppStatChip(title: "Apps", value: "\(appSummaries.count)")
                AppStatChip(title: "Tracked", value: DateFormatting.formatDuration(seconds: totalTrackedSeconds))
                AppStatChip(
                    title: "Top App",
                    value: topApp.map { "\($0.appName) · \(DateFormatting.formatDuration(seconds: $0.totalSeconds))" } ?? "-"
                )
            }
        }
    }

    private func moveDate(by days: Int) {
        if let newDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) {
            selectedDate = newDate
        }
    }

    @ViewBuilder
    private var todayButton: some View {
        if Calendar.current.isDateInToday(selectedDate) {
            Button("Today") {
                selectedDate = Date()
            }
            .buttonStyle(.borderedProminent)
        } else {
            Button("Today") {
                selectedDate = Date()
            }
            .buttonStyle(.bordered)
        }
    }

    private func loadData(animated: Bool) {
        let (start, end) = DateFormatting.dayRange(for: selectedDate)
        let shouldApplyRealmFilter = appState.categoryStore.hasRealmCategories && selectedRealmFilter != .all
        do {
            let summaries: [AppDatabase.AppTimeSummary]
            if shouldApplyRealmFilter, let realm = selectedRealmFilter.realmValue {
                summaries = try appState.database.fetchAppBreakdown(from: start, to: end, realm: realm)
            } else {
                summaries = try appState.database.fetchAppBreakdown(from: start, to: end)
            }
            let topSummaries = Array(summaries.prefix(12))
            var nextDetails: [String: [AppDatabase.AppDetailSummary]] = [:]
            for summary in topSummaries {
                if shouldApplyRealmFilter, let realm = selectedRealmFilter.realmValue {
                    nextDetails[summary.appName] = try appState.database.fetchDetailBreakdownForApp(summary.appName, from: start, to: end, realm: realm)
                } else {
                    nextDetails[summary.appName] = try appState.database.fetchDetailBreakdownForApp(summary.appName, from: start, to: end)
                }
            }

            let apply = {
                self.appSummaries = summaries
                self.detailBreakdowns = nextDetails
                self.animateDistribution = false
                self.animateCards = false
            }

            if animated {
                withAnimation(.snappy(duration: 0.24)) { apply() }
            } else {
                apply()
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeInOut(duration: 0.45)) {
                    animateDistribution = true
                }
                withAnimation(.spring(response: 0.45, dampingFraction: 0.84)) {
                    animateCards = true
                }
            }
        } catch {
            print("Failed to load app breakdown: \(error)")
        }
    }

    private func toggleExpanded(_ appName: String) {
        if expandedApps.contains(appName) {
            expandedApps.remove(appName)
        } else {
            expandedApps.insert(appName)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 30)
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("No app activity yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("As you move between apps, this view will show where your day is going and what each app was used for.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 430)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }
}

private struct AppDistributionBar: View {
    let appSummaries: [AppDatabase.AppTimeSummary]
    @State private var animateSegments = false

    private var totalSeconds: Int {
        max(1, appSummaries.reduce(0) { $0 + $1.totalSeconds })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Distribution")
                .font(.subheadline)
                .fontWeight(.semibold)

            GeometryReader { geometry in
                HStack(spacing: 2) {
                    ForEach(appSummaries.prefix(8), id: \.appName) { summary in
                        let fraction = CGFloat(summary.totalSeconds) / CGFloat(totalSeconds)
                        let width = max(12, geometry.size.width * fraction)
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(AppColorHelper.color(for: summary.appName))

                            if width > 80 {
                                Text(summary.appName)
                                    .font(.caption2)
                                    .fontWeight(.medium)
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .padding(.horizontal, 8)
                            }
                        }
                        .frame(width: animateSegments ? width : 0)
                        .help("\(summary.appName) · \(DateFormatting.formatDuration(seconds: summary.totalSeconds))")
                    }
                }
            }
            .frame(height: 28)
        }
        .padding(16)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .onAppear {
            animateSegments = false
            withAnimation(.easeInOut(duration: 0.5)) {
                animateSegments = true
            }
        }
        .onChange(of: appSummaries.map(\.appName).joined(separator: "|")) { _, _ in
            animateSegments = false
            withAnimation(.easeInOut(duration: 0.45)) {
                animateSegments = true
            }
        }
    }
}

private struct AppBreakdownCard: View {
    let summary: AppDatabase.AppTimeSummary
    let details: [AppDatabase.AppDetailSummary]
    let totalTrackedSeconds: Int
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let animateIn: Bool
    let order: Int
    @State private var isHovered = false

    private var accentColor: Color {
        AppColorHelper.color(for: summary.appName)
    }

    private var percentage: Int {
        guard totalTrackedSeconds > 0 else { return 0 }
        return Int((Double(summary.totalSeconds) / Double(totalTrackedSeconds)) * 100)
    }

    private var shownDetails: [AppDatabase.AppDetailSummary] {
        isExpanded ? details : Array(details.prefix(5))
    }

    private var hiddenDetailCount: Int {
        max(0, details.count - 5)
    }

    private var appKindLabel: String {
        if details.contains(where: { $0.detailType == "terminal_pane" }) { return "terminal" }
        if details.contains(where: { $0.detailType == "url" }) { return "browser" }
        return "app"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(accentColor)
                    .frame(width: 5, height: 50)

                AppIconView(appName: summary.appName, accentColor: accentColor)

                VStack(alignment: .leading, spacing: 6) {
                    Text(summary.appName)
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text("\(summary.recordCount) sessions · \(appKindLabel)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(DateFormatting.formatDuration(seconds: summary.totalSeconds))
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()

                    Text("\(percentage)% of tracked time")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !details.isEmpty {
                VStack(spacing: 10) {
                    ForEach(shownDetails) { detail in
                        DetailRow(detail: detail, accentColor: accentColor, appTotalSeconds: summary.totalSeconds)
                    }
                }

                if hiddenDetailCount > 0 {
                    Button(isExpanded ? "Show less" : "Show all \(details.count) details") {
                        withAnimation(.snappy(duration: 0.2)) {
                            onToggleExpanded()
                        }
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(accentColor)
                }
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.primary.opacity(0.05), Color.primary.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(isHovered ? accentColor.opacity(0.18) : Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isHovered ? 0.05 : 0.03), radius: isHovered ? 14 : 10, y: isHovered ? 6 : 4)
        .scaleEffect(isHovered ? 1.008 : 1)
        .opacity(animateIn ? 1 : 0)
        .offset(y: animateIn ? 0 : 14)
        .animation(.spring(response: 0.45, dampingFraction: 0.84).delay(Double(order) * 0.035), value: animateIn)
        .animation(.easeOut(duration: 0.16), value: isHovered)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

private struct DetailRow: View {
    let detail: AppDatabase.AppDetailSummary
    let accentColor: Color
    let appTotalSeconds: Int
    @State private var animateBar = false

    private var fraction: CGFloat {
        guard appTotalSeconds > 0 else { return 0 }
        return CGFloat(detail.totalSeconds) / CGFloat(appTotalSeconds)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(detail.displayTitle)
                    .font(.subheadline)
                    .lineLimit(2)

                Spacer(minLength: 12)

                Text("\(detail.sessionCount) sessions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(DateFormatting.formatDuration(seconds: detail.totalSeconds))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(accentColor.opacity(0.12))

                    Capsule()
                        .fill(accentColor.opacity(0.85))
                        .frame(width: animateBar ? max(8, geometry.size.width * fraction) : 0)
                }
            }
            .frame(height: 7)
        }
        .padding(.vertical, 2)
        .onAppear {
            animateBar = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                animateBar = true
            }
        }
    }
}

private struct AppIconView: View {
    let appName: String
    let accentColor: Color

    var body: some View {
        Group {
            if let nsImage = AppIconResolver.icon(for: appName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(accentColor.opacity(0.15))
                    .overlay {
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(accentColor)
                    }
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    private var fallbackSymbol: String {
        switch appName.lowercased() {
        case let name where name.contains("chrome"),
             let name where name.contains("dia"),
             let name where name.contains("safari"),
             let name where name.contains("firefox"):
            return "globe"
        case let name where name.contains("kitty"),
             let name where name.contains("terminal"),
             let name where name.contains("iterm"):
            return "terminal"
        case let name where name.contains("slack"):
            return "message"
        case let name where name.contains("xcode"):
            return "hammer"
        default:
            return "app.fill"
        }
    }
}

private enum AppIconResolver {
    static func icon(for appName: String) -> NSImage? {
        let workspace = NSWorkspace.shared

        if let path = workspace.fullPath(forApplication: appName) {
            let image = workspace.icon(forFile: path)
            image.size = NSSize(width: 64, height: 64)
            return image
        }

        // Try a few common browser naming variants.
        let aliases = [
            appName,
            appName + ".app",
            appName.replacingOccurrences(of: "Google Chrome", with: "Chrome"),
        ]

        for alias in aliases where !alias.isEmpty {
            if let path = workspace.fullPath(forApplication: alias) {
                let image = workspace.icon(forFile: path)
                image.size = NSSize(width: 64, height: 64)
                return image
            }
        }

        return nil
    }
}

private struct AppStatChip: View {
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.05))
        .clipShape(Capsule())
    }
}
