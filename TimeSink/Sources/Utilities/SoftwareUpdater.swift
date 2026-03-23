import Foundation
import Sparkle

/// Wraps Sparkle's `SPUStandardUpdaterController` for use in SwiftUI.
///
/// Provides a simple interface to check for updates and exposes
/// observable state for UI bindings.
@MainActor
final class SoftwareUpdater: ObservableObject {
    private let updaterController: SPUStandardUpdaterController

    @Published var canCheckForUpdates = false
    @Published var automaticallyChecksForUpdates: Bool {
        didSet {
            updaterController.updater.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }
    }

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        automaticallyChecksForUpdates = updaterController.updater.automaticallyChecksForUpdates

        // Observe Sparkle's canCheckForUpdates KVO property
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    /// Presents the Sparkle update check UI.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// The date of the last update check, if any.
    var lastUpdateCheckDate: Date? {
        updaterController.updater.lastUpdateCheckDate
    }
}
