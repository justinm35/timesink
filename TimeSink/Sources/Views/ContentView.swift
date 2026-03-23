import SwiftUI

/// Root content view for the main window.
///
/// Shows the permissions onboarding if needed, otherwise the main navigation.
struct ContentView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        Group {
            if appState.showOnboarding {
                PermissionsView()
            } else {
                MainNavigationView()
            }
        }
    }
}

/// The main navigation view with a sidebar and detail area.
struct MainNavigationView: View {
    @Environment(AppState.self) private var appState
    @State private var selectedTab: SidebarTab = .timeline

    var body: some View {
        NavigationSplitView {
            SidebarView(selectedTab: $selectedTab)
        } detail: {
            detailView(for: selectedTab)
        }
    }

    @ViewBuilder
    private func detailView(for tab: SidebarTab) -> some View {
        switch tab {
        case .timeline:
            TimelineView()
        case .byApp:
            AppBreakdownView()
        case .categories:
            CategoryEditorView()
        case .settings:
            SettingsView()
        }
    }
}
