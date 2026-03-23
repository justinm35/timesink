import AppKit
import Foundation

/// The core activity tracking loop.
///
/// Polls the active application and window title every few seconds,
/// creating and closing `ActivityRecord`s as the user switches context.
/// Runs as an actor to ensure thread-safe state management.
actor ActivityMonitor {

    // MARK: - Dependencies

    private let database: AppDatabase
    private let browserTracker: BrowserTracker
    private let terminalTracker: TerminalTracker
    private let idleDetector: IdleDetector
    private let meetingDetector: MeetingDetector

    // MARK: - State

    private var currentRecord: ActivityRecord?
    private var pollTask: Task<Void, Never>?
    private var flushTask: Task<Void, Never>?
    private var isMonitoring = false
    var treatMeetingsAsActiveTime = true

    /// How often to poll (in seconds).
    var pollInterval: TimeInterval = 3

    /// How often to flush the current record to the DB (in seconds).
    private let flushInterval: TimeInterval = 30

    // MARK: - Known Browser Bundle IDs

    /// Bundle IDs for Chromium-based browsers.
    private static let browserBundleIds: Set<String> = [
        "company.thebrowser.dia",
        "com.google.Chrome",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "com.arc.browser",
        "org.chromium.Chromium",
        "org.mozilla.firefox",
        "com.apple.Safari",
    ]

    /// Bundle IDs for terminal emulators.
    private static let terminalBundleIds: Set<String> = [
        "net.kovidgoyal.kitty",
        "com.googlecode.iterm2",
        "com.apple.Terminal",
        "dev.warp.Warp-Stable",
    ]

    // MARK: - Init

    init(database: AppDatabase, browserTracker: BrowserTracker, terminalTracker: TerminalTracker, idleDetector: IdleDetector, meetingDetector: MeetingDetector) {
        self.database = database
        self.browserTracker = browserTracker
        self.terminalTracker = terminalTracker
        self.idleDetector = idleDetector
        self.meetingDetector = meetingDetector
    }

    // MARK: - Control

    /// Starts the activity monitoring loop.
    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.poll()
                try? await Task.sleep(for: .seconds(self.pollInterval))
            }
        }

        // Periodic flush of the current record to the DB
        flushTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(self.flushInterval))
                await self.flushCurrentRecord()
            }
        }
    }

    /// Stops the activity monitoring loop and closes the current record.
    func stopMonitoring() {
        isMonitoring = false
        pollTask?.cancel()
        pollTask = nil
        flushTask?.cancel()
        flushTask = nil
        closeCurrentRecord()
    }

    /// Returns the current active record (for UI display).
    func getCurrentRecord() -> ActivityRecord? {
        currentRecord
    }

    func setTreatMeetingsAsActiveTime(_ enabled: Bool) {
        treatMeetingsAsActiveTime = enabled
    }

    // MARK: - Core Poll

    private func poll() async {
        // Get frontmost application (must access on main thread)
        let appInfo = await MainActorHelper.frontmostAppInfo()

        guard let appInfo else { return }

        let appName = appInfo.name
        let bundleId = appInfo.bundleId
        let pid = appInfo.pid

        // Get window title via Accessibility API
        let windowTitle = AccessibilityHelper.windowTitle(for: pid) ?? ""

        // Parse detail based on app type
        let (detail, detailType) = parseDetail(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            pid: pid
        )

        let meetingContext = meetingDetector.detect(
            appName: appName,
            bundleId: bundleId,
            windowTitle: windowTitle,
            detail: detail
        )

        let shouldTreatAsIdle = idleDetector.isIdle && !(treatMeetingsAsActiveTime && meetingContext.isLikelyInMeeting)

        if shouldTreatAsIdle {
            if currentRecord != nil && currentRecord?.isIdle == false {
                // Transition to idle: close the current active record
                closeCurrentRecord()
                // Create an idle record
                startNewRecord(
                    appName: appName,
                    windowTitle: "",
                    detail: nil,
                    detailType: .app,
                    isIdle: true
                )
            }
            return
        }

        // If we were idle and now active again, close the idle record
        if currentRecord?.isIdle == true {
            closeCurrentRecord()
        }

        // Compare to current record
        if let current = currentRecord,
           current.appName == appName,
           current.detail == detail,
           current.isIdle == false
        {
            // Same activity — no-op (flush task will update endedAt periodically)
            return
        }

        // Different activity: close old, start new
        closeCurrentRecord()
        startNewRecord(
            appName: appName,
            windowTitle: windowTitle,
            detail: detail,
            detailType: detailType,
            isIdle: false
        )
    }

    // MARK: - Detail Parsing

    /// Determines the detail and detail type based on the app.
    private func parseDetail(
        appName: String,
        bundleId: String,
        windowTitle: String,
        pid: pid_t
    ) -> (String?, DetailType) {
        // Browser: parse page title from window title
        if Self.browserBundleIds.contains(bundleId) {
            let pageTitle = BrowserTracker.parsePageTitle(from: windowTitle, appName: appName)
            return (pageTitle, .url)
        }

        // Terminal: get active tmux pane info
        if Self.terminalBundleIds.contains(bundleId) {
            // Try to get terminal detail synchronously from cached data
            if let terminalDetail = terminalTracker.lastPaneInfo {
                return (terminalDetail, .terminalPane)
            }
            // Fallback to window title
            return (windowTitle, .terminalPane)
        }

        // Generic app
        return (nil, .app)
    }

    // MARK: - Record Management

    private func startNewRecord(
        appName: String,
        windowTitle: String,
        detail: String?,
        detailType: DetailType,
        isIdle: Bool
    ) {
        var record = ActivityRecord(
            appName: appName,
            windowTitle: windowTitle,
            detail: detail,
            detailType: detailType,
            startedAt: Date(),
            isIdle: isIdle
        )

        do {
            let id = try database.insertRecord(record)
            record.id = id
            try database.closeAllOpenRecords(exceptID: id)
            currentRecord = record
        } catch {
            print("Failed to insert activity record: \(error)")
        }
    }

    private func closeCurrentRecord() {
        guard let record = currentRecord, let id = record.id else {
            currentRecord = nil
            return
        }

        let now = Date()

        do {
            try database.closeRecord(id: id, endedAt: now)
        } catch {
            print("Failed to close activity record \(id): \(error)")
        }

        currentRecord = nil
    }

    /// Periodically flushes the current record's endedAt to the DB
    /// so we don't lose long sessions if the app crashes.
    private func flushCurrentRecord() {
        guard let record = currentRecord, let id = record.id else { return }

        do {
            try database.closeRecord(id: id, endedAt: Date())
            try database.closeAllOpenRecords(exceptID: id, endedAt: Date())
        } catch {
            print("Failed to flush activity record \(id): \(error)")
        }
    }
}

// MARK: - MainActor Helper

/// Helper to access MainActor-isolated APIs from the ActivityMonitor actor.
@MainActor
enum MainActorHelper {

    struct AppInfo: Sendable {
        let name: String
        let bundleId: String
        let pid: pid_t
    }

    /// Gets info about the frontmost application.
    static func frontmostAppInfo() -> AppInfo? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        return AppInfo(
            name: app.localizedName ?? "Unknown",
            bundleId: app.bundleIdentifier ?? "",
            pid: app.processIdentifier
        )
    }
}
