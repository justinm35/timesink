import AppKit
import Charts
import SwiftUI

struct CategoryEditorView: View {
    @Environment(AppState.self) private var appState
    @Namespace private var categoryModeNamespace

    @State private var dateRange: DateRangeOption = .today
    @State private var selectedRealmFilter: RealmFilter = .all
    @State private var breakdown: [AppDatabase.CategoryTimeSummary] = []
    @State private var activityCounts: [Int64?: Int] = [:]
    @State private var appInsights: [Int64: [AppDatabase.CategoryAppSummary]] = [:]
    @State private var activityInsights: [Int64: [AppDatabase.CategoryDetailSummary]] = [:]
    @State private var selectedCategoryID: Int64?
    @State private var showingEditor = false
    @State private var editingDraft: EditableCategoryDraft?
    @State private var pendingDeleteCategory: Category?
    @State private var showResetConfirmation = false
    @State private var animateChart = false
    @State private var animateBars = false

    enum DateRangeOption: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
    }

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
        ZStack {
            if showingEditor {
                editorPage
                    .transition(editorTransition)
            } else {
                analyticsPage
                    .transition(overviewTransition)
            }
        }
        .animation(.spring(response: 0.36, dampingFraction: 0.88), value: showingEditor)
        .onAppear { loadData(animated: false) }
        .onChange(of: appState.categoryStore.hasRealmCategories) { _, hasRealms in
            if !hasRealms {
                selectedRealmFilter = .all
                loadData(animated: true)
            }
        }
        .onChange(of: dateRange) { _, _ in loadData(animated: true) }
        .onChange(of: selectedRealmFilter) { _, _ in loadData(animated: true) }
        .alert(item: $pendingDeleteCategory) { category in
            Alert(
                title: Text("Delete \(category.name)?"),
                message: Text("Activities assigned to this category will become uncategorized."),
                primaryButton: .destructive(Text("Delete")) {
                    if let id = category.id {
                        if selectedCategoryID == id {
                            selectedCategoryID = nil
                            editingDraft = nil
                        }
                        appState.categoryStore.deleteCategory(id: id)
                        loadData(animated: true)
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Reset categories to defaults?", isPresented: $showResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                editingDraft = nil
                selectedCategoryID = nil
                appState.categoryStore.resetToDefaults()
                loadData(animated: true)
            }
        } message: {
            Text("This will restore the original category set and remove your custom edits.")
        }
    }

    private var analyticsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                headerView
                summarySurface
                categoriesList
                detailPanel
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var editorPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button {
                            showingEditor = false
                            editingDraft = nil
                        } label: {
                            Label("Back to Categories", systemImage: "chevron.left")
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)

                        Text("Edit Categories")
                            .font(.title2)
                            .fontWeight(.bold)
                            .padding(.top, 8)

                        Text("Manage names, descriptions, colors, and whether each category counts as productive.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        beginCreatingCategory()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                }

                LazyVStack(spacing: 14) {
                    ForEach(editorCategories) { category in
                        LegacyCategoryCard(
                            category: category,
                            isEditing: editingDraft?.id == category.id,
                            draft: editingDraft?.id == category.id ? editingDraft : nil,
                            onEdit: { beginEditing(category) },
                            onCancel: cancelEditingDraft,
                            onSave: saveDraft,
                            onDelete: { pendingDeleteCategory = category },
                            onDraftChange: { editingDraft = $0 },
                            onToggleProductive: { toggleProductive(for: category) }
                        )
                    }

                    if isCreatingCategoryDraft {
                        LegacyCategoryCard(
                            category: nil,
                            isEditing: true,
                            draft: editingDraft,
                            onEdit: {},
                            onCancel: cancelEditingDraft,
                            onSave: saveDraft,
                            onDelete: {},
                            onDraftChange: { editingDraft = $0 },
                            onToggleProductive: nil
                        )
                    }
                }

                footerView
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private var sortedCategories: [Category] {
        let sourceCategories = appState.categoryStore.hasRealmCategories && selectedRealmFilter.realmValue != nil
            ? appState.categoryStore.categories.filter { $0.realm == selectedRealmFilter.realmValue }
            : appState.categoryStore.categories

        let byId = Dictionary(uniqueKeysWithValues: sourceCategories.compactMap { category in
            category.id.map { ($0, category) }
        })
        let ranked = breakdown.compactMap { item -> (Category, Int)? in
            guard let id = item.categoryId, let category = byId[id] else { return nil }
            return (category, item.totalSeconds)
        }
        let existingIds = Set(ranked.compactMap { $0.0.id })
        let unused = sourceCategories.filter { !existingIds.contains($0.id ?? -1) }
        return ranked.map(\.0) + unused.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var selectedCategory: Category? {
        if let selectedCategoryID {
            return appState.categoryStore.categories.first { $0.id == selectedCategoryID }
        }
        return sortedCategories.first
    }

    private var selectedSummary: AppDatabase.CategoryTimeSummary? {
        guard let selectedCategoryID else { return nil }
        return breakdown.first { $0.categoryId == selectedCategoryID }
    }

    private var totalSeconds: Int {
        breakdown.reduce(0) { $0 + $1.totalSeconds }
    }

    private var productivePercentage: Int {
        let productive = breakdown.filter { $0.isProductive == true }.reduce(0) { $0 + $1.totalSeconds }
        guard totalSeconds > 0 else { return 0 }
        return Int((Double(productive) / Double(totalSeconds)) * 100)
    }

    private var realmBreakdown: AppDatabase.RealmBreakdown {
        let filteredRealm = selectedRealmFilter.realmValue
        if filteredRealm == nil {
            let work = breakdown.filter { $0.realm == "work" }.reduce(0) { $0 + $1.totalSeconds }
            let personal = breakdown.filter { $0.realm == "personal" }.reduce(0) { $0 + $1.totalSeconds }
            return .init(workSeconds: work, personalSeconds: personal)
        }
        if filteredRealm == "work" {
            return .init(workSeconds: totalSeconds, personalSeconds: 0)
        }
        return .init(workSeconds: 0, personalSeconds: totalSeconds)
    }

    private var headerView: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Categories")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Understand how your categories are performing, then refine them only when you need to.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

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

                Picker("Range", selection: $dateRange) {
                    ForEach(DateRangeOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 320)

                Button {
                    showingEditor = true
                } label: {
                    Label("Edit", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var summarySurface: some View {
        HStack(alignment: .center, spacing: 20) {
            donutView
                .frame(width: 132, height: 132)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    AppStatChip(title: "Categories", value: "\(appState.categoryStore.categories.count)")
                    AppStatChip(title: "Productive", value: "\(productivePercentage)%")
                    AppStatChip(title: "Tracked", value: DateFormatting.formatDuration(seconds: totalSeconds))
                    if appState.categoryStore.hasRealmCategories {
                        AppStatChip(title: "Work", value: DateFormatting.formatDuration(seconds: realmBreakdown.workSeconds))
                        AppStatChip(title: "Personal", value: DateFormatting.formatDuration(seconds: realmBreakdown.personalSeconds))
                    }
                }

                if appState.categoryStore.hasRealmCategories {
                    Text("Use Work and Personal to split your categories into two high-level buckets. Views across the app will automatically pick that up.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 10) {
                    ForEach(Array(breakdown.prefix(5).enumerated()), id: \.element.categoryId) { index, item in
                        CategoryOverviewRow(item: item, totalSeconds: totalSeconds, isAnimated: animateBars, order: index)
                    }
                }
            }

            Spacer()
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [Color.primary.opacity(0.05), Color.primary.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    private var donutView: some View {
        ZStack {
            Chart(chartData, id: \.categoryId) { item in
                SectorMark(
                    angle: .value("Time", item.displaySeconds),
                    innerRadius: .ratio(0.62),
                    angularInset: 1
                )
                .foregroundStyle(Color(hex: item.categoryColor ?? "#888888"))
            }
            .chartLegend(.hidden)

            VStack(spacing: 2) {
                Text("\(productivePercentage)%")
                    .font(.title3)
                    .fontWeight(.bold)
                Text("productive")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var chartData: [AnimatedCategorySlice] {
        breakdown.filter { $0.totalSeconds > 0 }.map { item in
            AnimatedCategorySlice(
                categoryId: item.categoryId,
                categoryColor: item.categoryColor,
                totalSeconds: item.totalSeconds,
                animationProgress: animateChart ? 1 : 0
            )
        }
    }

    private var categoriesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(sortedCategories.enumerated()), id: \.element.id) { index, category in
                let summary = breakdown.first { $0.categoryId == category.id }
                let seconds = summary?.totalSeconds ?? 0
                let percentage = totalSeconds > 0 ? Int((Double(seconds) / Double(totalSeconds)) * 100) : 0

                Button {
                    selectedCategoryID = category.id
                    editingDraft = nil
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(hex: category.color))
                            .frame(width: 8, height: 8)

                        Text(category.name)
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)
                            .frame(width: 180, alignment: .leading)

                        if let realm = category.realm {
                            RealmBadge(realm: realm, compact: true)
                                .frame(width: 70, alignment: .leading)
                        } else {
                            Spacer()
                                .frame(width: 70)
                        }

                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.07))

                                Capsule()
                                    .fill(Color(hex: category.color))
                                    .frame(width: animateBars ? geometry.size.width * CGFloat(percentage) / 100 : 0)
                            }
                            .animation(.spring(response: 0.5, dampingFraction: 0.84).delay(Double(index) * 0.03), value: animateBars)
                        }
                        .frame(height: 9)

                        Text(seconds > 0 ? DateFormatting.formatDuration(seconds: seconds) : "-")
                            .font(.body)
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .frame(width: 72, alignment: .trailing)

                        Text("\(percentage)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(rowBackground(for: category))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if category.id != sortedCategories.last?.id {
                    Divider()
                        .padding(.leading, 14)
                }
            }
        }
        .background(Color.primary.opacity(0.025))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var detailPanel: some View {
        Group {
            if let category = selectedCategory {
                if let editingDraft, editingDraft.id == category.id || (editingDraft.id == nil && category.id == selectedCategoryID) {
                    CategoryDetailEditor(
                        draft: editingDraft,
                        onChange: { self.editingDraft = $0 },
                        onCancel: { self.editingDraft = nil },
                        onSave: saveDraft,
                        onDelete: { pendingDeleteCategory = category }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else {
                    CategoryInsightsPanel(
                        category: category,
                        summary: selectedSummary,
                        activityCount: activityCounts[category.id] ?? 0,
                        appBreakdown: category.id.flatMap { appInsights[$0] } ?? [],
                        activityBreakdown: category.id.flatMap { activityInsights[$0] } ?? []
                    )
                    .transition(.opacity)
                }
            } else if let editingDraft {
                CategoryDetailEditor(
                    draft: editingDraft,
                    onChange: { self.editingDraft = $0 },
                    onCancel: { self.editingDraft = nil },
                    onSave: saveDraft,
                    onDelete: {}
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "tag")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("Select a category above")
                        .font(.headline)
                    Text("See how it's performing, then edit it only when you need to.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 42)
                .background(Color.primary.opacity(0.03))
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.86), value: selectedCategoryID)
        .animation(.easeInOut(duration: 0.18), value: editingDraft?.id)
    }

    private var footerView: some View {
        HStack {
            Spacer()
            Button("Reset to defaults") {
                showResetConfirmation = true
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
    }

    private var editorCategories: [Category] {
        appState.categoryStore.categories.sorted { $0.sortOrder < $1.sortOrder }
    }

    private var isCreatingCategoryDraft: Bool {
        editingDraft?.id == nil && editingDraft != nil
    }

    private func rowBackground(for category: Category) -> some View {
        Group {
            if selectedCategoryID == category.id {
                Color(hex: category.color).opacity(0.10)
            } else {
                Color.clear
            }
        }
    }

    private func loadData(animated: Bool) {
        let (start, end) = dateRangeForOption(dateRange)
        let shouldApplyRealmFilter = appState.categoryStore.hasRealmCategories && selectedRealmFilter != .all
        do {
            let nextBreakdown: [AppDatabase.CategoryTimeSummary]
            let counts: [AppDatabase.CategoryActivityCount]
            if shouldApplyRealmFilter, let realm = selectedRealmFilter.realmValue {
                nextBreakdown = try appState.database.fetchCategoryBreakdown(from: start, to: end, realm: realm)
                counts = try appState.database.fetchCategoryActivityCounts(from: start, to: end, realm: realm)
            } else {
                nextBreakdown = try appState.database.fetchCategoryBreakdown(from: start, to: end)
                counts = try appState.database.fetchCategoryActivityCounts(from: start, to: end)
            }
            let nextCounts = Dictionary(uniqueKeysWithValues: counts.map { ($0.categoryId, $0.activityCount) })
            var nextAppInsights: [Int64: [AppDatabase.CategoryAppSummary]] = [:]
            var nextActivityInsights: [Int64: [AppDatabase.CategoryDetailSummary]] = [:]

            let insightCategories = !shouldApplyRealmFilter
                ? appState.categoryStore.categories
                : appState.categoryStore.categories.filter { $0.realm == selectedRealmFilter.realmValue }

            for category in insightCategories {
                guard let id = category.id else { continue }
                nextAppInsights[id] = try appState.database.fetchAppBreakdownForCategory(id, from: start, to: end)
                nextActivityInsights[id] = try appState.database.fetchDetailBreakdownForCategory(id, from: start, to: end)
            }

            let apply = {
                breakdown = nextBreakdown
                activityCounts = nextCounts
                appInsights = nextAppInsights
                activityInsights = nextActivityInsights
                if selectedCategoryID == nil {
                    selectedCategoryID = sortedCategories.first?.id
                } else if let selectedCategoryID, !appState.categoryStore.categories.contains(where: { $0.id == selectedCategoryID }) {
                    self.selectedCategoryID = sortedCategories.first?.id
                }
                animateChart = false
                animateBars = false
            }

            if animated {
                withAnimation(.easeInOut(duration: 0.22)) { apply() }
            } else {
                apply()
            }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.easeInOut(duration: 0.6)) { animateChart = true }
                withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { animateBars = true }
            }
        } catch {
            print("Failed to load category data: \(error)")
        }
    }

    private func dateRangeForOption(_ option: DateRangeOption) -> (Date, Date) {
        switch option {
        case .today:
            return DateFormatting.dayRange(for: Date())
        case .yesterday:
            let yesterday = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
            return DateFormatting.dayRange(for: yesterday)
        case .thisWeek:
            return DateFormatting.thisWeekRange()
        case .thisMonth:
            return DateFormatting.thisMonthRange()
        }
    }

    private func beginEditing(_ category: Category) {
        selectedCategoryID = category.id
        editingDraft = EditableCategoryDraft(category: category)
    }

    private func beginCreatingCategory() {
        let nextSortOrder = (appState.categoryStore.categories.last?.sortOrder ?? -1) + 1
        let newDraft = EditableCategoryDraft(
            id: nil,
            name: "",
            description: "",
            color: CategoryColorPalette.defaultColor.hex,
            isProductive: true,
            realm: nil,
            sortOrder: nextSortOrder
        )
        editingDraft = newDraft
        selectedCategoryID = nil
    }

    private func cancelEditingDraft() {
        editingDraft = nil
    }

    private func toggleProductive(for category: Category) {
        var updated = category
        updated.isProductive.toggle()
        appState.categoryStore.updateCategory(updated)
        loadData(animated: true)
    }

    private func saveDraft() {
        guard var draft = editingDraft else { return }
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.description = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !draft.name.isEmpty else { return }

        let category = draft.asCategory()
        if category.id == nil {
            appState.categoryStore.addCategory(
                name: category.name,
                description: category.description,
                color: category.color,
                isProductive: category.isProductive,
                realm: category.realm
            )
        } else {
            appState.categoryStore.updateCategory(category)
        }
        selectedCategoryID = category.id ?? appState.categoryStore.categories.last?.id
        editingDraft = nil
        loadData(animated: true)
    }

    private var editorTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.985, anchor: .trailing)),
            removal: .move(edge: .leading).combined(with: .opacity)
        )
    }

    private var overviewTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.985, anchor: .leading)),
            removal: .move(edge: .trailing).combined(with: .opacity)
        )
    }
}

private struct AnimatedCategorySlice: Identifiable {
    let categoryId: Int64?
    let categoryColor: String?
    let totalSeconds: Int
    let animationProgress: Double

    var id: Int64 { categoryId ?? -1 }
    var displaySeconds: Double { Double(totalSeconds) * animationProgress }
}

private struct CategoryOverviewRow: View {
    let item: AppDatabase.CategoryTimeSummary
    let totalSeconds: Int
    let isAnimated: Bool
    let order: Int

    private var percentage: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(item.totalSeconds) / Double(totalSeconds)
    }

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: item.categoryColor ?? "#888888"))
                .frame(width: 8, height: 8)

            Text(item.categoryName ?? "Uncategorized")
                .font(.subheadline)
                .frame(width: 120, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.07))
                    Capsule()
                        .fill(Color(hex: item.categoryColor ?? "#888888"))
                        .frame(width: isAnimated ? geometry.size.width * percentage : 0)
                }
                .animation(.spring(response: 0.5, dampingFraction: 0.84).delay(Double(order) * 0.03), value: isAnimated)
            }
            .frame(height: 8)

            Text(DateFormatting.formatDuration(seconds: item.totalSeconds))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)

            Text("\(Int(percentage * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
    }
}

private struct CategoryInsightsPanel: View {
    let category: Category
    let summary: AppDatabase.CategoryTimeSummary?
    let activityCount: Int
    let appBreakdown: [AppDatabase.CategoryAppSummary]
    let activityBreakdown: [AppDatabase.CategoryDetailSummary]

    @State private var showAllActivities = false

    private var totalSeconds: Int {
        summary?.totalSeconds ?? 0
    }

    private var visibleActivities: [AppDatabase.CategoryDetailSummary] {
        showAllActivities ? activityBreakdown : Array(activityBreakdown.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(category.name)
                        .font(.title3)
                        .fontWeight(.semibold)

                    HStack(spacing: 10) {
                        ProductiveBadge(isProductive: category.isProductive)
                        if let realm = category.realm {
                            RealmBadge(realm: realm)
                        }

                        Text("\(activityCount) activities")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text(DateFormatting.formatDuration(seconds: totalSeconds))
                        .font(.title3)
                        .fontWeight(.bold)
                        .monospacedDigit()

                    if let summary {
                        Text("\(summary.categoryName ?? category.name) · selected range")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !appBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Apps in this category")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(spacing: 10) {
                        ForEach(appBreakdown, id: \.id) { app in
                            CategoryAppInsightRow(app: app, categoryColor: Color(hex: category.color), totalSeconds: max(totalSeconds, 1))
                        }
                    }
                }
            }

            if !activityBreakdown.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top activities")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    VStack(spacing: 10) {
                        ForEach(visibleActivities, id: \.id) { item in
                            CategoryActivityInsightRow(item: item, categoryColor: Color(hex: category.color), totalSeconds: max(totalSeconds, 1))
                        }
                    }

                    if activityBreakdown.count > 5 {
                        Button(showAllActivities ? "Show less" : "Show all \(activityBreakdown.count) activities") {
                            withAnimation(.snappy(duration: 0.2)) {
                                showAllActivities.toggle()
                            }
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(Color(hex: category.color))
                    }
                }
            }
        }
        .padding(20)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.07), lineWidth: 1)
        }
    }
}

private struct CategoryAppInsightRow: View {
    let app: AppDatabase.CategoryAppSummary
    let categoryColor: Color
    let totalSeconds: Int
    @State private var animateBar = false

    private var percentage: Double {
        Double(app.totalSeconds) / Double(max(totalSeconds, 1))
    }

    var body: some View {
        HStack(spacing: 10) {
            CompactAppIconView(appName: app.appName, accentColor: categoryColor)

            Text(app.appName)
                .font(.subheadline)
                .lineLimit(1)
                .frame(width: 140, alignment: .leading)

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(categoryColor.opacity(0.12))
                    Capsule()
                        .fill(categoryColor.opacity(0.9))
                        .frame(width: animateBar ? max(8, geometry.size.width * percentage) : 0)
                }
            }
            .frame(height: 7)

            Text(DateFormatting.formatDuration(seconds: app.totalSeconds))
                .font(.caption)
                .fontWeight(.semibold)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)

            Text("\(Int(percentage * 100))%")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
        }
        .onAppear {
            animateBar = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                animateBar = true
            }
        }
    }
}

private struct CategoryActivityInsightRow: View {
    let item: AppDatabase.CategoryDetailSummary
    let categoryColor: Color
    let totalSeconds: Int
    @State private var animateBar = false

    private var percentage: Double {
        Double(item.totalSeconds) / Double(max(totalSeconds, 1))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.displayTitle)
                    .font(.subheadline)
                    .lineLimit(2)

                Spacer(minLength: 12)

                Text("\(item.sessionCount) sessions")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text(DateFormatting.formatDuration(seconds: item.totalSeconds))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(categoryColor.opacity(0.12))
                    Capsule()
                        .fill(categoryColor.opacity(0.9))
                        .frame(width: animateBar ? max(8, geometry.size.width * percentage) : 0)
                }
            }
            .frame(height: 7)
        }
        .onAppear {
            animateBar = false
            withAnimation(.spring(response: 0.42, dampingFraction: 0.86)) {
                animateBar = true
            }
        }
    }
}

private struct CompactAppIconView: View {
    let appName: String
    let accentColor: Color

    var body: some View {
        Group {
            if let nsImage = AppIconResolver.icon(for: appName) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(accentColor.opacity(0.14))
                    .overlay {
                        Image(systemName: fallbackSymbol)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(accentColor)
                    }
            }
        }
        .frame(width: 24, height: 24)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var fallbackSymbol: String {
        switch appName.lowercased() {
        case let name where name.contains("chrome"), let name where name.contains("dia"), let name where name.contains("safari"), let name where name.contains("firefox"):
            return "globe"
        case let name where name.contains("kitty"), let name where name.contains("terminal"), let name where name.contains("iterm"):
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
            image.size = NSSize(width: 32, height: 32)
            return image
        }

        let aliases = [
            appName,
            appName + ".app",
            appName.replacingOccurrences(of: "Google Chrome", with: "Chrome"),
        ]
        for alias in aliases where !alias.isEmpty {
            if let path = workspace.fullPath(forApplication: alias) {
                let image = workspace.icon(forFile: path)
                image.size = NSSize(width: 32, height: 32)
                return image
            }
        }
        return nil
    }
}

private struct CategoryDetailEditor: View {
    let draft: EditableCategoryDraft?
    let onChange: (EditableCategoryDraft) -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if var draft {
                TextField("Category name", text: Binding(
                    get: { draft.name },
                    set: {
                        draft.name = $0
                        onChange(draft)
                    }
                ))
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: Binding(
                        get: { draft.description },
                        set: {
                            draft.description = $0
                            onChange(draft)
                        }
                    ))
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 92)
                    .padding(8)
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    CategoryPaletteRow(selectedHex: draft.color) { hex in
                        var nextDraft = draft
                        nextDraft.color = hex
                        onChange(nextDraft)
                    }
                }

                HStack {
                    ProductiveBadge(isProductive: draft.isProductive)
                        .onTapGesture {
                            var nextDraft = draft
                            nextDraft.isProductive.toggle()
                            onChange(nextDraft)
                        }

                    RealmMenu(selectedRealm: draft.realm) { realm in
                        var nextDraft = draft
                        nextDraft.realm = realm
                        onChange(nextDraft)
                    }

                    HStack(spacing: 8) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        CategoryBadge(category: draft.asCategory())
                    }

                    Spacer()

                    Button("Cancel", action: onCancel)
                        .buttonStyle(.bordered)
                    Button(draft.id == nil ? "Add Category" : "Save Changes", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .disabled(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .padding(20)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}

private struct LegacyCategoryCard: View {
    let category: Category?
    let isEditing: Bool
    let draft: EditableCategoryDraft?
    let onEdit: () -> Void
    let onCancel: () -> Void
    let onSave: () -> Void
    let onDelete: () -> Void
    let onDraftChange: (EditableCategoryDraft) -> Void
    let onToggleProductive: (() -> Void)?

    private var displayName: String {
        if isEditing { return draft?.name.isEmpty == false ? draft?.name ?? "" : "New Category" }
        return category?.name ?? ""
    }

    private var displayDescription: String {
        if isEditing {
            return draft?.description.isEmpty == false ? draft?.description ?? "" : "Describe the kind of work or browsing this category should capture."
        }
        return category?.description ?? ""
    }

    private var displayColorHex: String {
        if isEditing { return draft?.color ?? CategoryColorPalette.defaultColor.hex }
        return category?.color ?? CategoryColorPalette.defaultColor.hex
    }

    private var displayIsProductive: Bool {
        if isEditing { return draft?.isProductive ?? true }
        return category?.isProductive ?? true
    }

    private var displayRealm: String? {
        if isEditing { return draft?.realm }
        return category?.realm
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color(hex: displayColorHex))
                    .frame(width: 5, height: 48)

                VStack(alignment: .leading, spacing: 8) {
                    if isEditing, var draft {
                        TextField("Category name", text: Binding(
                            get: { draft.name },
                            set: {
                                draft.name = $0
                                onDraftChange(draft)
                            }
                        ))
                        .textFieldStyle(.plain)
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color.primary.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        Text(displayName)
                            .font(.title3)
                            .fontWeight(.semibold)
                    }

                    if isEditing, var draft {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Description")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            TextEditor(text: Binding(
                                get: { draft.description },
                                set: {
                                    draft.description = $0
                                    onDraftChange(draft)
                                }
                            ))
                            .font(.body)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 88)
                            .padding(8)
                            .background(Color.primary.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                    } else {
                        Text(displayDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    HStack(spacing: 8) {
                        ProductiveBadge(isProductive: displayIsProductive)
                        if let realm = displayRealm, !isEditing {
                            RealmBadge(realm: realm)
                        }
                    }

                    if !isEditing {
                        HStack(spacing: 8) {
                            Button(action: {
                                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                                    onEdit()
                                }
                            }) {
                                Label("Edit", systemImage: "pencil")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(role: .destructive, action: onDelete) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            if isEditing {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Color")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let draft {
                        CategoryPaletteRow(selectedHex: draft.color) { hex in
                            var nextDraft = draft
                            nextDraft.color = hex
                            onDraftChange(nextDraft)
                        }
                    }
                }

                HStack(spacing: 12) {
                    ProductiveBadge(isProductive: displayIsProductive)
                        .onTapGesture {
                            if var draft {
                                draft.isProductive.toggle()
                                onDraftChange(draft)
                            }
                        }

                    RealmMenu(selectedRealm: displayRealm) { realm in
                        if var draft {
                            draft.realm = realm
                            onDraftChange(draft)
                        }
                    }

                    HStack(spacing: 8) {
                        Text("Preview")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        CategoryBadge(
                            category: Category(
                                id: category?.id,
                                name: displayName.isEmpty ? "Category" : displayName,
                                description: displayDescription,
                                color: displayColorHex,
                                isProductive: displayIsProductive,
                                realm: displayRealm,
                                sortOrder: category?.sortOrder ?? draft?.sortOrder ?? 0
                            )
                        )
                    }

                    Spacer()

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                onCancel()
                            }
                        }
                            .buttonStyle(.bordered)

                        Button(category == nil ? "Add Category" : "Save Changes") {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                                onSave()
                            }
                        }
                            .buttonStyle(.borderedProminent)
                            .disabled((draft?.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true))
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .top).combined(with: .opacity), removal: .opacity))
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
                .stroke(Color.primary.opacity(isEditing ? 0.14 : 0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(isEditing ? 0.06 : 0.03), radius: 10, y: 4)
        .animation(.spring(response: 0.34, dampingFraction: 0.84), value: isEditing)
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .onTapGesture {
            if !isEditing {
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    onEdit()
                }
            }
        }
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

private struct ProductiveBadge: View {
    let isProductive: Bool

    var body: some View {
        Text(isProductive ? "Productive" : "Unproductive")
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(isProductive ? Color.green.opacity(0.16) : Color.orange.opacity(0.18))
            .foregroundStyle(isProductive ? Color.green : Color.orange)
            .clipShape(Capsule())
    }
}

private struct EditableCategoryDraft {
    var id: Int64?
    var name: String
    var description: String
    var color: String
    var isProductive: Bool
    var realm: String?
    var sortOrder: Int

    init(category: Category) {
        self.id = category.id
        self.name = category.name
        self.description = category.description
        self.color = category.color
        self.isProductive = category.isProductive
        self.realm = category.realm
        self.sortOrder = category.sortOrder
    }

    init(id: Int64?, name: String, description: String, color: String, isProductive: Bool, realm: String?, sortOrder: Int) {
        self.id = id
        self.name = name
        self.description = description
        self.color = color
        self.isProductive = isProductive
        self.realm = realm
        self.sortOrder = sortOrder
    }

    func asCategory() -> Category {
        Category(id: id, name: name, description: description, color: color, isProductive: isProductive, realm: realm, sortOrder: sortOrder)
    }
}

private struct RealmMenu: View {
    let selectedRealm: String?
    let onSelect: (String?) -> Void

    var body: some View {
        Menu {
            Button("None") { onSelect(nil) }
            Button("Work") { onSelect("work") }
            Button("Personal") { onSelect("personal") }
        } label: {
            HStack(spacing: 6) {
                Text(selectedRealm.map { $0.capitalized } ?? "Realm")
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
        }
        .menuStyle(.borderlessButton)
    }
}

private struct RealmBadge: View {
    let realm: String
    var compact: Bool = false

    var body: some View {
        Text(realm.capitalized)
            .font(compact ? .caption2 : .caption)
            .fontWeight(.medium)
            .padding(.horizontal, compact ? 8 : 10)
            .padding(.vertical, compact ? 4 : 6)
            .background(Color.primary.opacity(0.06))
            .clipShape(Capsule())
    }
}

private struct CategoryPaletteColor: Identifiable {
    let name: String
    let hex: String
    var id: String { hex }
}

private enum CategoryColorPalette {
    static let all: [CategoryPaletteColor] = [
        .init(name: "Blue", hex: "#4A90D9"),
        .init(name: "Indigo", hex: "#5856D6"),
        .init(name: "Purple", hex: "#7B68EE"),
        .init(name: "Plum", hex: "#AF52DE"),
        .init(name: "Pink", hex: "#FF2D55"),
        .init(name: "Red", hex: "#FF6B6B"),
        .init(name: "Orange", hex: "#F5A623"),
        .init(name: "Amber", hex: "#FFAB00"),
        .init(name: "Green", hex: "#50C878"),
        .init(name: "Teal", hex: "#30B0C7"),
        .init(name: "Mint", hex: "#00C7BE"),
        .init(name: "Cyan", hex: "#32ADE6"),
        .init(name: "Slate", hex: "#8E8E93"),
        .init(name: "Graphite", hex: "#636366"),
        .init(name: "Brown", hex: "#A2845E"),
        .init(name: "Olive", hex: "#6D7740"),
    ]

    static let defaultColor = all[0]
}

private struct CategoryPaletteRow: View {
    let selectedHex: String
    let onSelect: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 10), count: 8), alignment: .leading, spacing: 10) {
            ForEach(CategoryColorPalette.all) { color in
                Button {
                    onSelect(color.hex)
                } label: {
                    Circle()
                        .fill(Color(hex: color.hex))
                        .frame(width: 24, height: 24)
                        .overlay {
                            if selectedHex.lowercased() == color.hex.lowercased() {
                                Circle()
                                    .stroke(Color.white.opacity(0.95), lineWidth: 2.5)
                                    .padding(2)
                            }
                        }
                        .overlay {
                            if selectedHex.lowercased() == color.hex.lowercased() {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
                .help(color.name)
            }
        }
    }
}
