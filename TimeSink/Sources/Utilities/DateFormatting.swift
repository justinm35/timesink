import Foundation

/// Date and time formatting utilities for TimeSink.
enum DateFormatting {

    // MARK: - Formatters

    /// Time-only formatter: "2:30 PM"
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        return f
    }()

    /// Date-only formatter: "Mar 18, 2026"
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .none
        return f
    }()

    /// Full date+time: "Mar 18, 2026 at 2:30 PM"
    static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    /// Relative date: "Today", "Yesterday", "2 days ago"
    static nonisolated(unsafe) let relativeDateFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        f.unitsStyle = .full
        return f
    }()

    // MARK: - Duration Formatting

    /// Formats a duration in seconds to a human-readable string.
    ///
    /// - Examples: "2h 15m", "45m", "30s", "0s"
    static func formatDuration(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60

        if hours > 0 {
            if minutes > 0 {
                return "\(hours)h \(minutes)m"
            }
            return "\(hours)h"
        }
        return "\(minutes)m"
    }

    /// Formats a duration as a compact string for menu bar display.
    ///
    /// - Examples: "2:15", "0:45", "0:00"
    static func formatDurationCompact(seconds: Int) -> String {
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return String(format: "%d:%02d", hours, minutes)
    }

    // MARK: - Date Ranges

    /// Returns the start and end of the given date's day.
    static func dayRange(for date: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        return (start, end)
    }

    /// Returns the start and end of the current week.
    static func thisWeekRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let daysFromMonday = (weekday + 5) % 7
        let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -daysFromMonday, to: now)!)
        let end = calendar.date(byAdding: .day, value: 7, to: start)!
        return (start, end)
    }

    /// Returns the start and end of the current month.
    static func thisMonthRange() -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        let start = calendar.date(from: components)!
        let end = calendar.date(byAdding: .month, value: 1, to: start)!
        return (start, end)
    }

    // MARK: - Chromium Timestamp Conversion

    /// Converts a Chromium/WebKit timestamp (microseconds since 1601-01-01) to a Date.
    ///
    /// Chromium stores timestamps as microseconds since the Windows epoch (Jan 1, 1601).
    /// To convert to Unix epoch: `(chromium_us / 1_000_000) - 11_644_473_600`
    static func dateFromChromiumTimestamp(_ timestamp: Int64) -> Date {
        let unixSeconds = Double(timestamp) / 1_000_000.0 - 11_644_473_600.0
        return Date(timeIntervalSince1970: unixSeconds)
    }

    // MARK: - Hour Grouping

    /// Returns the hour component (0-23) for a date, for grouping timeline entries.
    static func hourOfDay(for date: Date) -> Int {
        Calendar.current.component(.hour, from: date)
    }

    /// Formats an hour (0-23) to a display string: "2 PM", "12 AM", etc.
    static func formatHour(_ hour: Int) -> String {
        let period = hour >= 12 ? "PM" : "AM"
        let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        return "\(displayHour) \(period)"
    }

    /// Formats a selected day for the timeline header.
    static func timelineDayTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today, \(dateFormatter.string(from: date))"
        }
        if calendar.isDateInYesterday(date) {
            return "Yesterday, \(dateFormatter.string(from: date))"
        }

        let weekday = date.formatted(.dateTime.weekday(.wide))
        return "\(weekday), \(dateFormatter.string(from: date))"
    }
}
