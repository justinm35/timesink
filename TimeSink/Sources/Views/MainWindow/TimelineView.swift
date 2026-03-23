import SwiftUI

struct TimelineView: View {
    @Environment(AppState.self) private var appState

    @State private var selectedDate = Date()
    @State private var records: [ActivityRecord] = []
    @State private var searchText = ""
    @State private var selectedBlockID: Int64?
    @State private var scrollTargetBlockID: Int64?
    @State private var displayBlocks: [TimelineBlock] = []
    @State private var groupedSections: [HourSection] = []
    @State private var graphRecords: [ActivityRecord] = []
    @State private var totalTrackedSeconds: Int = 0
    @State private var productivePercentage: Int = 0
    @State private var topAppName: String = "None"
    @State private var topAppSeconds: Int = 0
    @State private var workSeconds: Int = 0
    @State private var personalSeconds: Int = 0
    @State private var animateSummary = false
    @State private var animateFlameGraph = false
    @State private var contentTransitionID = UUID()
    @State private var hasLoadedInitially = false

    private let refreshTimer = Timer.publish(every: 10, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            headerView

            if displayBlocks.isEmpty {
                emptyState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                            flameGraphSection

                            ForEach(groupedSections) { section in
                                Section {
                                    LazyVStack(spacing: 10) {
                                        ForEach(Array(section.blocks.enumerated()), id: \.element.id) { index, block in
                                            ActivityRow(
                                                block: block,
                                                categories: appState.categoryStore.categories,
                                                isSelected: block.id == selectedBlockID,
                                                isCurrentOpenBlock: block.id == latestOpenBlockID,
                                                order: index
                                            )
                                            .id(block.id)
                                            .onTapGesture {
                                                selectedBlockID = block.id
                                            }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                    .padding(.top, 10)
                                } header: {
                                    HourSectionHeader(section: section)
                                        .padding(.horizontal, 20)
                                        .padding(.vertical, 10)
                                        .background(.ultraThinMaterial)
                                }
                            }
                        }
                        .padding(.vertical, 18)
                        .id(contentTransitionID)
                    }
                    .background(Color.primary.opacity(0.015))
                    .onChange(of: scrollTargetBlockID) { _, newValue in
                        guard let newValue else { return }
                        withAnimation(.snappy(duration: 0.28)) {
                            proxy.scrollTo(newValue, anchor: .center)
                        }
                        scrollTargetBlockID = nil
                    }
                }
            }
        }
        .onChange(of: selectedDate) { _, _ in
            loadRecords(animated: true, animateSurface: true)
        }
        .onChange(of: searchText) { _, _ in
            recomputeDerivedState(animated: false, animateSurface: false)
        }
        .onReceive(refreshTimer) { _ in
            loadRecords(animated: false, animateSurface: false)
        }
        .onAppear {
            loadRecords(animated: false, animateSurface: true)
        }
    }

    private var headerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Timeline")
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
                    .controlSize(.regular)

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
                    .controlSize(.regular)

                    todayButton
                }
            }

            SummaryStrip(
                totalTrackedSeconds: totalTrackedSeconds,
                productivePercentage: productivePercentage,
                topAppName: topAppName,
                topAppSeconds: topAppSeconds,
                workSeconds: workSeconds,
                personalSeconds: personalSeconds,
                showRealmStats: appState.categoryStore.hasRealmCategories,
                animate: animateSummary
            )

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("Search apps, pages, commands...", text: $searchText)
                    .textFieldStyle(.plain)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if !searchText.isEmpty {
                Text("\(displayBlocks.count) result\(displayBlocks.count == 1 ? "" : "s") for \"\(searchText)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 14)
        .background(
            LinearGradient(
                colors: [Color.primary.opacity(0.035), Color.clear],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var flameGraphSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FlameGraphView(
                records: graphRecords,
                dayStart: timelineStart,
                dayEnd: timelineEnd,
                categories: appState.categoryStore.categories,
                selectedRecordID: selectedBlockID,
                onRecordTapped: { record in
                    selectedBlockID = record.id
                    scrollTargetBlockID = record.id
                }
            )
            .opacity(animateFlameGraph ? 1 : 0)
            .offset(y: animateFlameGraph ? 0 : 8)
        }
        .padding(.horizontal, 20)
    }

    private var filteredRecords: [ActivityRecord] {
        if searchText.isEmpty { return records }
        let query = searchText.lowercased()
        return records.filter { record in
            record.appName.lowercased().contains(query) ||
            record.windowTitle.lowercased().contains(query) ||
            (record.detail?.lowercased().contains(query) ?? false)
        }
    }

    private func buildDisplayBlocks() -> [TimelineBlock] {
        let sorted = filteredRecords.sorted { $0.startedAt < $1.startedAt }
        guard !sorted.isEmpty else { return [] }

        var blocks: [TimelineBlock] = []
        var bucket: [ActivityRecord] = []

        func shouldMerge(_ lhs: ActivityRecord, _ rhs: ActivityRecord) -> Bool {
            guard lhs.isIdle == rhs.isIdle else { return false }
            guard lhs.appName == rhs.appName else { return false }
            guard lhs.categoryId == rhs.categoryId else { return false }

            let lhsEnd = lhs.endedAt ?? lhs.startedAt
            let gap = rhs.startedAt.timeIntervalSince(lhsEnd)
            return gap <= 10
        }

        func flushBucket() {
            guard !bucket.isEmpty else { return }
            blocks.append(TimelineBlock(records: bucket))
            bucket.removeAll(keepingCapacity: true)
        }

        for record in sorted {
            if let last = bucket.last, shouldMerge(last, record) {
                bucket.append(record)
            } else {
                flushBucket()
                bucket = [record]
            }
        }
        flushBucket()

        return blocks.sorted { $0.startedAt > $1.startedAt }
    }

    private func buildGroupedSections(from blocks: [TimelineBlock]) -> [HourSection] {
        let grouped = Dictionary(grouping: blocks) { block in
            DateFormatting.hourOfDay(for: block.startedAt)
        }

        return grouped
            .map { HourSection(hour: $0.key, blocks: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.hour > $1.hour }
    }

    private var timelineStart: Date {
        let (start, _) = DateFormatting.dayRange(for: selectedDate)
        return min(graphRecords.map(\.startedAt).min() ?? start, start)
    }

    private var timelineEnd: Date {
        let (_, end) = DateFormatting.dayRange(for: selectedDate)
        let latest = graphRecords.map { $0.endedAt ?? Date() }.max() ?? end
        return max(latest, end)
    }

    private var latestOpenBlockID: Int64? {
        displayBlocks.first(where: { $0.endedAt == nil })?.id
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
            .controlSize(.regular)
        } else {
            Button("Today") {
                selectedDate = Date()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    private func loadRecords(animated: Bool, animateSurface: Bool) {
        let (start, end) = DateFormatting.dayRange(for: selectedDate)
        do {
            let newRecords = try appState.database.fetchRecords(from: start, to: end)
            if animated {
                withAnimation(.snappy(duration: 0.25)) {
                    records = newRecords
                    recomputeDerivedState(animated: false, animateSurface: animateSurface)
                    contentTransitionID = UUID()
                }
            } else {
                records = newRecords
                recomputeDerivedState(animated: false, animateSurface: animateSurface)
            }
        } catch {
            print("Failed to load records: \(error)")
        }
    }

    private func recomputeDerivedState(animated: Bool, animateSurface: Bool) {
        let nextBlocks = buildDisplayBlocks()
        let nextGraphRecords = nextBlocks.map(\.displayRecord)
        let nextSections = buildGroupedSections(from: nextBlocks)

        let nextTotalTrackedSeconds = nextBlocks.filter { !$0.isIdle }.reduce(0) { $0 + $1.durationSeconds }
        let productiveIDs = Set(appState.categoryStore.categories.filter(\.isProductive).compactMap(\.id))
        let productiveSeconds = nextBlocks
            .filter { productiveIDs.contains($0.categoryId ?? -1) }
            .reduce(0) { $0 + $1.durationSeconds }
        let nextProductivePercentage = nextTotalTrackedSeconds > 0
            ? Int((Double(productiveSeconds) / Double(nextTotalTrackedSeconds)) * 100)
            : 0

        let groupedApps = Dictionary(grouping: nextBlocks.filter { !$0.isIdle }, by: \.appName)
        let nextTopAppName = groupedApps.max { lhs, rhs in
            lhs.value.reduce(0) { $0 + $1.durationSeconds } < rhs.value.reduce(0) { $0 + $1.durationSeconds }
        }?.key ?? "None"
        let nextTopAppSeconds = nextBlocks.filter { $0.appName == nextTopAppName }.reduce(0) { $0 + $1.durationSeconds }
        let categoriesByID = Dictionary(uniqueKeysWithValues: appState.categoryStore.categories.compactMap { category in
            category.id.map { ($0, category) }
        })
        let nextWorkSeconds = nextBlocks.reduce(0) { partial, block in
            guard let categoryId = block.categoryId, categoriesByID[categoryId]?.realm == "work" else { return partial }
            return partial + block.durationSeconds
        }
        let nextPersonalSeconds = nextBlocks.reduce(0) { partial, block in
            guard let categoryId = block.categoryId, categoriesByID[categoryId]?.realm == "personal" else { return partial }
            return partial + block.durationSeconds
        }

        let apply = {
            displayBlocks = nextBlocks
            graphRecords = nextGraphRecords
            groupedSections = nextSections
            totalTrackedSeconds = nextTotalTrackedSeconds
            productivePercentage = nextProductivePercentage
            topAppName = nextTopAppName
            topAppSeconds = nextTopAppSeconds
            workSeconds = nextWorkSeconds
            personalSeconds = nextPersonalSeconds
        }

        if animated {
            withAnimation(.snappy(duration: 0.22)) {
                apply()
            }
        } else {
            apply()
        }

        if animateSurface {
            animateSummary = false
            animateFlameGraph = false

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(35))
                withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                    animateSummary = true
                }
                withAnimation(.easeInOut(duration: 0.28)) {
                    animateFlameGraph = true
                }
                hasLoadedInitially = true
            }
        } else if !hasLoadedInitially {
            animateSummary = true
            animateFlameGraph = true
            hasLoadedInitially = true
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "sparkles.rectangle.stack")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("Nothing tracked yet")
                .font(.title3)
                .fontWeight(.semibold)
            Text("As you move between apps, pages, and terminals, your day will start taking shape here.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(30)
    }
}

private struct TimelineBlock: Identifiable {
    let id: Int64
    let records: [ActivityRecord]

    init(records: [ActivityRecord]) {
        self.records = records
        self.id = records.compactMap(\.id).first ?? Int64(records.first?.startedAt.timeIntervalSince1970 ?? 0)
    }

    var primaryRecord: ActivityRecord { records.max(by: { ($0.durationSeconds ?? 0) < ($1.durationSeconds ?? 0) }) ?? records[0] }
    var appName: String { primaryRecord.appName }
    var startedAt: Date { records.map(\.startedAt).min() ?? primaryRecord.startedAt }
    var endedAt: Date? {
        if records.contains(where: { $0.endedAt == nil }) { return nil }
        return records.compactMap(\.endedAt).max()
    }
    var durationSeconds: Int {
        let closed = records.compactMap(\.durationSeconds).reduce(0, +)
        if closed > 0 { return closed }
        return max(0, Int((endedAt ?? Date()).timeIntervalSince(startedAt)))
    }
    var isIdle: Bool { records.allSatisfy(\.isIdle) }
    var categoryId: Int64? { primaryRecord.categoryId }
    var detailText: String {
        let longest = records
            .compactMap { $0.detail?.isEmpty == false ? $0.detail : ($0.windowTitle.isEmpty ? nil : $0.windowTitle) }
            .max(by: { $0.count < $1.count })
        return longest ?? appName
    }
    var segmentCount: Int { records.count }

    var displayRecord: ActivityRecord {
        ActivityRecord(
            id: id,
            appName: appName,
            windowTitle: primaryRecord.windowTitle,
            detail: detailText,
            detailType: primaryRecord.detailType,
            startedAt: startedAt,
            endedAt: endedAt,
            durationSeconds: durationSeconds,
            isIdle: isIdle,
            categoryId: categoryId,
            categorizedAt: primaryRecord.categorizedAt
        )
    }
}

private struct HourSection: Identifiable {
    let hour: Int
    let blocks: [TimelineBlock]
    var id: Int { hour }
    var totalSeconds: Int { blocks.reduce(0) { $0 + $1.durationSeconds } }
    var uniqueApps: Int { Set(blocks.filter { !$0.isIdle }.map(\.appName)).count }
}

private struct SummaryStrip: View {
    let totalTrackedSeconds: Int
    let productivePercentage: Int
    let topAppName: String
    let topAppSeconds: Int
    let workSeconds: Int
    let personalSeconds: Int
    let showRealmStats: Bool
    let animate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                SummaryPill(title: "Tracked", value: DateFormatting.formatDuration(seconds: totalTrackedSeconds), order: 0, animate: animate)
                SummaryPill(title: "Productive", value: "\(productivePercentage)%", order: 1, animate: animate)
                SummaryPill(title: "Top App", value: topAppName == "None" ? "-" : "\(topAppName) · \(DateFormatting.formatDuration(seconds: topAppSeconds))", order: 2, animate: animate)
                if showRealmStats {
                    SummaryPill(title: "Work", value: DateFormatting.formatDuration(seconds: workSeconds), order: 3, animate: animate)
                    SummaryPill(title: "Personal", value: DateFormatting.formatDuration(seconds: personalSeconds), order: 4, animate: animate)
                }
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [Color.green.opacity(0.9), Color.orange.opacity(0.75)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: animate ? geometry.size.width * CGFloat(productivePercentage) / 100 : 0)
                }
            }
            .frame(height: 8)
        }
    }
}

private struct SummaryPill: View {
    let title: String
    let value: String
    let order: Int
    let animate: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(animate ? 1 : 0)
        .offset(y: animate ? 0 : 10)
        .animation(.spring(response: 0.4, dampingFraction: 0.85).delay(Double(order) * 0.04), value: animate)
    }
}

private struct HourSectionHeader: View {
    let section: HourSection

    var body: some View {
        HStack(spacing: 10) {
            Text(DateFormatting.formatHour(section.hour))
                .font(.headline)
                .fontWeight(.semibold)

            Text("\(DateFormatting.formatDuration(seconds: section.totalSeconds)) tracked")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("\(section.uniqueApps) app\(section.uniqueApps == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }
}

private struct ActivityRow: View {
    let block: TimelineBlock
    let categories: [Category]
    let isSelected: Bool
    let isCurrentOpenBlock: Bool
    let order: Int

    @State private var appeared = false
    @State private var isHovered = false

    private var category: Category? {
        guard let categoryId = block.categoryId else { return nil }
        return categories.first { $0.id == categoryId }
    }

    private var accentColor: Color {
        AppColorHelper.color(for: block.appName, isIdle: block.isIdle)
    }

    var body: some View {
        HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(accentColor)
                .frame(width: 4)

            HStack(spacing: 14) {
                Circle()
                    .fill(accentColor.opacity(block.isIdle ? 0.35 : 0.18))
                    .frame(width: 34, height: 34)
                    .overlay {
                        Image(systemName: iconForApp(block.appName, isIdle: block.isIdle))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(accentColor)
                    }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(block.isIdle ? "Idle" : block.appName)
                            .font(.body)
                            .fontWeight(.semibold)

                        if block.segmentCount > 1 {
                            Text("\(block.segmentCount) segments")
                                .font(.caption2)
                                .fontWeight(.medium)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(Capsule())
                        }

                        if let category {
                            CategoryBadge(category: category)
                        }
                    }

                    if block.isIdle {
                        HStack(spacing: 10) {
                            Rectangle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(height: 1)
                            Text("Idle gap")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Rectangle()
                                .fill(Color.secondary.opacity(0.35))
                                .frame(height: 1)
                        }
                    } else {
                        Text(block.detailText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(DateFormatting.formatDuration(seconds: block.durationSeconds))
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .monospacedDigit()

                    Text(timeRangeText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if block.endedAt == nil, isCurrentOpenBlock {
                        Text("ongoing")
                            .font(.caption2)
                            .fontWeight(.medium)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .background(isSelected ? accentColor.opacity(0.10) : Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? accentColor.opacity(0.45) : (isHovered ? accentColor.opacity(0.16) : Color.primary.opacity(0.05)), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isSelected ? 0.08 : (isHovered ? 0.05 : 0.03)), radius: isHovered ? 12 : 8, y: isHovered ? 5 : 3)
        .opacity(block.isIdle ? 0.85 : 1)
        .scaleEffect(isHovered ? 1.006 : 1)
        .opacity(appeared ? (block.isIdle ? 0.85 : 1) : 0)
        .offset(y: appeared ? 0 : 12)
        .animation(.spring(response: 0.42, dampingFraction: 0.86).delay(Double(order) * 0.025), value: appeared)
        .animation(.easeOut(duration: 0.14), value: isHovered)
        .onAppear {
            appeared = false
            withAnimation {
                appeared = true
            }
        }
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var timeRangeText: String {
        let start = DateFormatting.timeFormatter.string(from: block.startedAt)
        let end = block.endedAt.map(DateFormatting.timeFormatter.string(from:)) ?? "now"
        return "\(start) - \(end)"
    }

    private func iconForApp(_ appName: String, isIdle: Bool) -> String {
        if isIdle { return "moon.zzz" }
        switch appName.lowercased() {
        case let name where name.contains("dia"), let name where name.contains("chrome"),
             let name where name.contains("safari"), let name where name.contains("firefox"):
            return "globe"
        case let name where name.contains("kitty"), let name where name.contains("terminal"),
             let name where name.contains("iterm"):
            return "terminal"
        case let name where name.contains("slack"):
            return "message"
        case let name where name.contains("mail"):
            return "envelope"
        case let name where name.contains("xcode"):
            return "hammer"
        case let name where name.contains("finder"):
            return "folder"
        default:
            return "app"
        }
    }
}

struct CategoryBadge: View {
    let category: Category

    var body: some View {
        Text(category.name)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color(hex: category.color).opacity(0.16))
            .foregroundStyle(Color(hex: category.color))
            .clipShape(Capsule())
    }
}

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: Double
        switch hex.count {
        case 6:
            r = Double((int >> 16) & 0xFF) / 255.0
            g = Double((int >> 8) & 0xFF) / 255.0
            b = Double(int & 0xFF) / 255.0
        default:
            r = 0.5; g = 0.5; b = 0.5
        }
        self.init(red: r, green: g, blue: b)
    }
}
