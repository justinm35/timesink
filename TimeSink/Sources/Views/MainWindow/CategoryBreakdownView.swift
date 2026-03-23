import Charts
import SwiftUI

/// Shows time breakdown by category with charts.
struct CategoryBreakdownView: View {
    @Environment(AppState.self) private var appState
    @State private var dateRange: DateRangeOption = .today
    @State private var breakdown: [AppDatabase.CategoryTimeSummary] = []
    @State private var totalSeconds: Int = 0

    enum DateRangeOption: String, CaseIterable {
        case today = "Today"
        case yesterday = "Yesterday"
        case thisWeek = "This Week"
        case thisMonth = "This Month"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("By Category")
                    .font(.title2)
                    .fontWeight(.semibold)

                Spacer()

                Picker("Range", selection: $dateRange) {
                    ForEach(DateRangeOption.allCases, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 400)
            }
            .padding()

            Divider()

            if breakdown.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        // Summary stats
                        HStack(spacing: 40) {
                            StatCard(title: "Total Tracked", value: DateFormatting.formatDuration(seconds: totalSeconds))
                            StatCard(title: "Productive", value: productivePercentage)
                            StatCard(title: "Categories", value: "\(breakdown.count)")
                        }
                        .padding()

                        // Donut chart
                        Chart(breakdown, id: \.categoryName) { item in
                            SectorMark(
                                angle: .value("Time", item.totalSeconds),
                                innerRadius: .ratio(0.5),
                                angularInset: 1
                            )
                            .foregroundStyle(Color(hex: item.categoryColor ?? "#888888"))
                            .annotation(position: .overlay) {
                                if Double(item.totalSeconds) / Double(max(totalSeconds, 1)) > 0.08 {
                                    Text(item.categoryName ?? "Uncategorized")
                                        .font(.caption2)
                                        .foregroundStyle(.white)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .frame(height: 250)
                        .padding(.horizontal)

                        Divider()
                            .padding(.horizontal)

                        // Category list
                        VStack(spacing: 4) {
                            ForEach(breakdown, id: \.categoryName) { item in
                                CategorySummaryRow(
                                    item: item,
                                    totalSeconds: totalSeconds
                                )
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom)
                }
            }
        }
        .onChange(of: dateRange) { _, _ in
            loadData()
        }
        .onAppear {
            loadData()
        }
    }

    // MARK: - Computed

    private var productivePercentage: String {
        let productive = breakdown.filter { $0.isProductive == true }.reduce(0) { $0 + $1.totalSeconds }
        let total = max(totalSeconds, 1)
        let pct = Int(Double(productive) / Double(total) * 100)
        return "\(pct)%"
    }

    // MARK: - Data Loading

    private func loadData() {
        let (start, end) = dateRangeForOption(dateRange)
        do {
            breakdown = try appState.database.fetchCategoryBreakdown(from: start, to: end)
            totalSeconds = try appState.database.fetchTotalTrackedSeconds(from: start, to: end)
        } catch {
            print("Failed to load category breakdown: \(error)")
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

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "chart.pie")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No categorized data")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Categories will appear here after AI categorization runs.")
                .font(.body)
                .foregroundStyle(.tertiary)

            Button("Categorize Now") {
                Task {
                    await appState.categorizeNow()
                    loadData()
                }
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stat Card

private struct StatCard: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title)
                .fontWeight(.bold)
                .monospacedDigit()
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Category Summary Row

private struct CategorySummaryRow: View {
    let item: AppDatabase.CategoryTimeSummary
    let totalSeconds: Int

    private var percentage: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(item.totalSeconds) / Double(totalSeconds)
    }

    var body: some View {
        HStack(spacing: 12) {
            // Color indicator
            Circle()
                .fill(Color(hex: item.categoryColor ?? "#888888"))
                .frame(width: 12, height: 12)

            // Name
            Text(item.categoryName ?? "Uncategorized")
                .font(.body)

            // Productive badge
            if let isProductive = item.isProductive {
                Text(isProductive ? "Productive" : "Unproductive")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isProductive ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
                    .foregroundStyle(isProductive ? .green : .red)
                    .clipShape(Capsule())
            }

            Spacer()

            // Progress bar
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: item.categoryColor ?? "#888888").opacity(0.3))
                    .frame(width: geo.size.width)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(hex: item.categoryColor ?? "#888888"))
                            .frame(width: geo.size.width * percentage)
                    }
            }
            .frame(width: 100, height: 8)

            // Time and percentage
            Text(DateFormatting.formatDuration(seconds: item.totalSeconds))
                .font(.body)
                .fontWeight(.medium)
                .monospacedDigit()
                .frame(width: 60, alignment: .trailing)

            Text("\(Int(percentage * 100))%")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 35, alignment: .trailing)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
    }
}
