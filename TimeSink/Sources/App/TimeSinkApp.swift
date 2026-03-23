import SwiftUI

@main
struct TimeSinkApp: App {
    @State private var appState = AppState()
    @StateObject private var softwareUpdater = SoftwareUpdater()

    var body: some Scene {
        MenuBarExtra("TimeSink", systemImage: "clock.fill") {
            MenuBarView()
                .environment(appState)
                .environmentObject(softwareUpdater)
                .frame(width: 320)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("TimeSink", id: "main") {
            ContentView()
                .environment(appState)
                .environmentObject(softwareUpdater)
                .frame(minWidth: 800, minHeight: 500)
        }
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Check for Updates...") {
                    softwareUpdater.checkForUpdates()
                }
                .disabled(!softwareUpdater.canCheckForUpdates)
            }
        }
    }
}
