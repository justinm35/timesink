import Foundation
import GRDB

/// Tracks browser activity by reading Chromium-based browser history databases
/// and parsing window titles.
///
/// Handles Dia (and other Chromium browsers) by:
/// 1. Real-time: Parsing the active window title to get the current page title.
/// 2. Periodic: Copying and reading the History SQLite DB to resolve actual URLs.
final class BrowserTracker: Sendable {

    private let database: AppDatabase

    /// Discovered browser profile paths.
    let profilePaths: [BrowserProfile]

    /// A browser profile with its history DB path.
    struct BrowserProfile: Sendable {
        let browserName: String
        let profileName: String
        let historyPath: String
    }

    /// A visit record from the browser history DB.
    struct BrowserVisit: Sendable {
        let url: String
        let title: String
        let visitTime: Date
    }

    init(database: AppDatabase) {
        self.database = database
        self.profilePaths = Self.discoverProfiles()
    }

    // MARK: - Window Title Parsing

    /// Extracts the page title from a browser window title.
    ///
    /// Chromium browsers use the format: "<page title> - <browser name>"
    /// e.g. "GitHub - Pull Request #482 - Dia"
    static func parsePageTitle(from windowTitle: String, appName: String) -> String? {
        let trimmedWindowTitle = windowTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedWindowTitle.isEmpty else { return nil }

        // Try stripping " - AppName" suffix
        let suffixes = [" - \(appName)", " — \(appName)"]
        var normalizedTitle = trimmedWindowTitle
        for suffix in suffixes {
            if normalizedTitle.hasSuffix(suffix) {
                normalizedTitle = String(normalizedTitle.dropLast(suffix.count))
                break
            }
        }

        normalizedTitle = normalizeChromiumStatusSuffixes(normalizedTitle)
        normalizedTitle = normalizedTitle.trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedTitle.isEmpty ? nil : normalizedTitle
    }

    private static func normalizeChromiumStatusSuffixes(_ title: String) -> String {
        var normalized = title
        let patterns = [
            #"\s+- High memory usage - .*?$"#,
            #"\s+- Playing audio$"#,
            #"\s+- Muted$"#,
            #"\s+- Picture-in-Picture$"#,
        ]

        for pattern in patterns {
            normalized = normalized.replacingOccurrences(
                of: pattern,
                with: "",
                options: .regularExpression
            )
        }

        return normalized
    }

    // MARK: - Profile Discovery

    /// Discovers all Chromium browser profiles on the system.
    private static func discoverProfiles() -> [BrowserProfile] {
        var profiles: [BrowserProfile] = []

        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        let appSupport = "\(homeDir)/Library/Application Support"

        // Known Chromium-based browsers and their directories
        let browsers: [(name: String, dir: String)] = [
            ("Dia", "\(appSupport)/Dia/User Data"),
            ("Chrome", "\(appSupport)/Google/Chrome"),
            ("Brave", "\(appSupport)/BraveSoftware/Brave-Browser"),
            ("Edge", "\(appSupport)/Microsoft Edge"),
        ]

        let fileManager = FileManager.default

        for browser in browsers {
            guard fileManager.fileExists(atPath: browser.dir) else { continue }

            do {
                let contents = try fileManager.contentsOfDirectory(atPath: browser.dir)
                for item in contents {
                    // Profile directories are "Default", "Profile 1", "Profile 2", etc.
                    if item == "Default" || item.hasPrefix("Profile ") {
                        let historyPath = "\(browser.dir)/\(item)/History"
                        if fileManager.fileExists(atPath: historyPath) {
                            profiles.append(BrowserProfile(
                                browserName: browser.name,
                                profileName: item,
                                historyPath: historyPath
                            ))
                        }
                    }
                }
            } catch {
                print("Failed to scan browser directory \(browser.dir): \(error)")
            }
        }

        return profiles
    }

    // MARK: - History Reading

    /// Reads recent browser history from all discovered profiles.
    ///
    /// Copies each History DB to a temp location first (browsers lock the file).
    /// Returns visits from the last `minutes` minutes.
    func readRecentHistory(minutes: Int = 30) -> [BrowserVisit] {
        var allVisits: [BrowserVisit] = []

        for profile in profilePaths {
            do {
                let visits = try readHistoryFromProfile(profile, minutes: minutes)
                allVisits.append(contentsOf: visits)
            } catch {
                print("Failed to read history from \(profile.browserName)/\(profile.profileName): \(error)")
            }
        }

        return allVisits.sorted { $0.visitTime > $1.visitTime }
    }

    /// Reads history from a single browser profile.
    private func readHistoryFromProfile(_ profile: BrowserProfile, minutes: Int) throws -> [BrowserVisit] {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory
        let tempPath = tempDir.appendingPathComponent(
            "timesink_\(profile.browserName)_\(profile.profileName)_history.sqlite"
        )

        // Remove old copy if exists
        try? fileManager.removeItem(at: tempPath)

        // Copy the locked DB to a temp location
        try fileManager.copyItem(
            atPath: profile.historyPath,
            toPath: tempPath.path
        )

        // Open the copy and query
        let dbQueue = try DatabaseQueue(path: tempPath.path)

        let cutoffDate = Date().addingTimeInterval(-Double(minutes * 60))
        // Chromium timestamps: microseconds since 1601-01-01
        let chromiumCutoff = Int64((cutoffDate.timeIntervalSince1970 + 11_644_473_600) * 1_000_000)

        let visits = try dbQueue.read { db -> [BrowserVisit] in
            let rows = try Row.fetchAll(db, sql: """
                SELECT u.url, u.title, v.visit_time
                FROM urls u
                JOIN visits v ON u.id = v.url
                WHERE v.visit_time > ?
                ORDER BY v.visit_time DESC
                LIMIT 200
                """, arguments: [chromiumCutoff])

            return rows.map { row in
                let url: String = row["url"]
                let title: String = row["title"] ?? ""
                let visitTime: Int64 = row["visit_time"]
                return BrowserVisit(
                    url: url,
                    title: title,
                    visitTime: DateFormatting.dateFromChromiumTimestamp(visitTime)
                )
            }
        }

        // Clean up temp file
        try? fileManager.removeItem(at: tempPath)

        return visits
    }

    // MARK: - URL Resolution

    /// Attempts to find the actual URL for a browser activity record by matching
    /// the page title against recent history visits.
    func resolveURL(forPageTitle pageTitle: String, around timestamp: Date) -> String? {
        let visits = readRecentHistory(minutes: 10)

        // Try exact title match first
        if let match = visits.first(where: { $0.title == pageTitle }) {
            return match.url
        }

        // Try partial title match
        if let match = visits.first(where: { $0.title.contains(pageTitle) || pageTitle.contains($0.title) }) {
            return match.url
        }

        return nil
    }
}
