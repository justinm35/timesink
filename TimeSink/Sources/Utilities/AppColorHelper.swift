import SwiftUI

/// Provides stable, visually distinct colors for app names.
enum AppColorHelper {
    private static let palette: [Color] = [
        Color(red: 0.12, green: 0.44, blue: 0.85),
        Color(red: 0.86, green: 0.36, blue: 0.19),
        Color(red: 0.14, green: 0.65, blue: 0.44),
        Color(red: 0.55, green: 0.36, blue: 0.86),
        Color(red: 0.89, green: 0.20, blue: 0.33),
        Color(red: 0.95, green: 0.68, blue: 0.15),
        Color(red: 0.10, green: 0.68, blue: 0.75),
        Color(red: 0.73, green: 0.29, blue: 0.62),
        Color(red: 0.31, green: 0.53, blue: 0.17),
        Color(red: 0.20, green: 0.48, blue: 0.72),
        Color(red: 0.78, green: 0.42, blue: 0.12),
        Color(red: 0.40, green: 0.40, blue: 0.44),
    ]

    static func color(for appName: String, isIdle: Bool = false) -> Color {
        if isIdle {
            return Color.gray.opacity(0.45)
        }

        let normalized = appName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return palette[0] }
        let hash = abs(normalized.unicodeScalars.reduce(0) { ($0 &* 31) &+ Int($1.value) })
        return palette[hash % palette.count]
    }

    static func legendEntries(for records: [ActivityRecord]) -> [(appName: String, color: Color)] {
        let appNames = Array(Set(records.filter { !$0.isIdle }.map(\.appName))).sorted()
        return appNames.map { ($0, color(for: $0)) }
    }
}
