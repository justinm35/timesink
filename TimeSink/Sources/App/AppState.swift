import AppKit
import Combine
import Foundation

/// Central application state that owns all managers and services.
///
/// Uses the Observation framework (`@Observable`) for SwiftUI integration.
/// Isolated to `@MainActor` since it drives UI updates.
@MainActor
@Observable
final class AppState {
    private static let hasCompletedOnboardingKey = "hasCompletedOnboarding"
    private static let selectedAIProviderKey = "selectedAIProvider"
    private static let treatMeetingsAsActiveTimeKey = "treatMeetingsAsActiveTime"

    // MARK: - Services

    let database: AppDatabase
    let activityMonitor: ActivityMonitor
    let browserTracker: BrowserTracker
    let terminalTracker: TerminalTracker
    let idleDetector: IdleDetector
    let meetingDetector: MeetingDetector
    let categorizationEngine: CategorizationEngine
    let categoryStore: CategoryStore

    // MARK: - UI State

    /// Whether the permissions onboarding should be shown.
    var showOnboarding: Bool = false

    /// Whether accessibility permission is granted.
    var isAccessibilityGranted: Bool = false

    /// Whether tracking is currently active (user can pause).
    var isTrackingActive: Bool = true

    /// The current activity record (for menu bar display).
    var currentActivity: ActivityRecord?

    /// Error message to display, if any.
    var errorMessage: String?

    /// Whether a categorization request is currently running.
    var isCategorizing: Bool = false

    /// User-visible status for the categorization pipeline.
    var categorizationStatusMessage: String?

    /// Whether the last categorization status represents success.
    var categorizationStatusSucceeded: Bool = false

    /// The currently selected AI provider for categorization.
    var selectedAIProvider: AIProvider

    // MARK: - Timers

    private var accessibilityCheckTask: Task<Void, Never>?
    private var categorizationTask: Task<Void, Never>?
    private var currentActivityPollTask: Task<Void, Never>?
    private var terminalPollTask: Task<Void, Never>?

    // MARK: - Settings

    /// How often (in minutes) to auto-categorize.
    var categorizationIntervalMinutes: Int = 30
    var treatMeetingsAsActiveTime: Bool {
        didSet {
            UserDefaults.standard.set(treatMeetingsAsActiveTime, forKey: Self.treatMeetingsAsActiveTimeKey)
            Task { await activityMonitor.setTreatMeetingsAsActiveTime(treatMeetingsAsActiveTime) }
        }
    }

    var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: Self.hasCompletedOnboardingKey)
    }

    // MARK: - Init

    init() {
        let providerRaw = UserDefaults.standard.string(forKey: Self.selectedAIProviderKey) ?? AIProvider.anthropic.rawValue
        selectedAIProvider = AIProvider(rawValue: providerRaw) ?? .anthropic
        treatMeetingsAsActiveTime = UserDefaults.standard.object(forKey: Self.treatMeetingsAsActiveTimeKey) as? Bool ?? true

        // Initialize the database
        do {
            database = try AppDatabase()
            try database.closeAllOpenRecords()
        } catch {
            fatalError("Failed to initialize database: \(error)")
        }

        // Initialize trackers
        idleDetector = IdleDetector()
        meetingDetector = MeetingDetector()
        browserTracker = BrowserTracker(database: database)
        terminalTracker = TerminalTracker()
        categorizationEngine = CategorizationEngine(database: database)
        categoryStore = CategoryStore(database: database)

        activityMonitor = ActivityMonitor(
            database: database,
            browserTracker: browserTracker,
            terminalTracker: terminalTracker,
            idleDetector: idleDetector,
            meetingDetector: meetingDetector
        )
        Task { await activityMonitor.setTreatMeetingsAsActiveTime(treatMeetingsAsActiveTime) }

        // Check initial permissions
        isAccessibilityGranted = AccessibilityHelper.isAccessibilityGranted
        showOnboarding = !hasCompletedOnboarding

        // Start background tasks
        startBackgroundTasks()

        // Start monitoring if permissions are granted
        if isAccessibilityGranted {
            startTracking()
        }

        // Listen for sleep/wake notifications
        setupSystemNotifications()
    }

    // MARK: - Tracking Control

    func startTracking() {
        guard isAccessibilityGranted else { return }
        isTrackingActive = true
        Task {
            await activityMonitor.startMonitoring()
        }
    }

    func stopTracking() {
        isTrackingActive = false
        Task {
            await activityMonitor.stopMonitoring()
        }
    }

    func toggleTracking() {
        if isTrackingActive {
            stopTracking()
        } else {
            startTracking()
        }
    }

    // MARK: - Categorization

    /// Manually triggers a categorization batch.
    func categorizeNow() async {
        if isCategorizing { return }

        isCategorizing = true
        categorizationStatusSucceeded = false
        defer { isCategorizing = false }

        do {
            let uncategorizedCount = try database.countUncategorizedRecords()

            guard uncategorizedCount > 0 else {
                categorizationStatusMessage = "No uncategorized records to send"
                categorizationStatusSucceeded = true
                return
            }

            categorizationStatusMessage = "Sending \(uncategorizedCount) record\(uncategorizedCount == 1 ? "" : "s") to \(selectedAIProvider.displayName)..."
            let count = try await categorizationEngine.categorizeBatch()
            categorizationStatusMessage = count > 0
                ? "Categorized \(count) record\(count == 1 ? "" : "s")"
                : "No records were categorized"
            categorizationStatusSucceeded = true
            print("Categorized \(count) records")
        } catch {
            errorMessage = error.localizedDescription
            categorizationStatusMessage = error.localizedDescription
            categorizationStatusSucceeded = false
            print("Categorization failed: \(error)")
        }
    }

    // MARK: - Background Tasks

    private func startBackgroundTasks() {
        // Poll accessibility status every 2 seconds
        accessibilityCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                let granted = AccessibilityHelper.isAccessibilityGranted
                if granted != self.isAccessibilityGranted {
                    self.isAccessibilityGranted = granted
                    if granted && self.hasCompletedOnboarding {
                        self.startTracking()
                    }
                }
            }
        }

        // Poll current activity for UI display every 3 seconds
        currentActivityPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                self.currentActivity = await self.activityMonitor.getCurrentRecord()
            }
        }

        // Poll terminal info every 3 seconds
        terminalPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(3))
                guard let self else { return }
                await self.terminalTracker.pollActivPane()
            }
        }

        // Auto-categorize periodically
        startCategorizationTimer()
    }

    private func startCategorizationTimer() {
        categorizationTask?.cancel()
        categorizationTask = Task { [weak self] in
            while !Task.isCancelled {
                let minutes = self?.categorizationIntervalMinutes ?? 30
                try? await Task.sleep(for: .seconds(minutes * 60))
                await self?.categorizeNow()
            }
        }
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.hasCompletedOnboardingKey)
        showOnboarding = false
        if isAccessibilityGranted {
            startTracking()
        }
    }

    /// Resets the app to a fresh state: stops tracking, wipes the database,
    /// clears all API keys from the Keychain, resets UserDefaults, and
    /// returns to the onboarding flow.
    func resetAllData() {
        // Stop tracking
        stopTracking()

        // Wipe the database (records, categories, logs — categories get re-seeded)
        do {
            try database.deleteAllData()
        } catch {
            print("Failed to wipe database: \(error)")
        }

        // Remove all API keys from the Keychain
        for provider in AIProvider.allCases {
            KeychainHelper.delete(key: provider.keychainKey)
        }

        // Reset UserDefaults
        UserDefaults.standard.removeObject(forKey: Self.hasCompletedOnboardingKey)
        UserDefaults.standard.removeObject(forKey: Self.selectedAIProviderKey)
        UserDefaults.standard.removeObject(forKey: Self.treatMeetingsAsActiveTimeKey)

        // Reset in-memory state
        selectedAIProvider = .anthropic
        treatMeetingsAsActiveTime = true
        currentActivity = nil
        errorMessage = nil
        categorizationStatusMessage = nil
        categorizationStatusSucceeded = false
        isCategorizing = false

        // Reload categories
        categoryStore.refreshCategories()

        // Show onboarding
        showOnboarding = true
    }

    func setSelectedAIProvider(_ provider: AIProvider) {
        selectedAIProvider = provider
        UserDefaults.standard.set(provider.rawValue, forKey: Self.selectedAIProviderKey)
    }

    // MARK: - System Notifications

    private func setupSystemNotifications() {
        let center = NSWorkspace.shared.notificationCenter

        center.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopTracking()
            }
        }

        center.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                // Brief delay to let the system settle
                try? await Task.sleep(for: .seconds(2))
                self?.startTracking()
            }
        }

        center.addObserver(
            forName: NSWorkspace.screensDidSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.stopTracking()
            }
        }

        center.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(1))
                self?.startTracking()
            }
        }
    }
}
