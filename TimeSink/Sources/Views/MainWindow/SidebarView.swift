import SwiftUI

/// The tabs available in the sidebar navigation.
enum SidebarTab: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case byApp = "By App"
    case categories = "Categories"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .timeline: return "clock"
        case .byApp: return "square.grid.2x2"
        case .categories: return "tag"
        case .settings: return "gear"
        }
    }
}

/// Sidebar navigation for the main window.
struct SidebarView: View {
    @Binding var selectedTab: SidebarTab
    @Environment(AppState.self) private var appState

    var body: some View {
        List(SidebarTab.allCases, selection: $selectedTab) { tab in
            Label(tab.rawValue, systemImage: tab.icon)
                .tag(tab)
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 8) {
                Divider()

                // Tracking status
                HStack {
                    Circle()
                        .fill(appState.isTrackingActive ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(appState.isTrackingActive ? "Tracking" : "Paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(appState.isTrackingActive ? "Pause" : "Resume") {
                        appState.toggleTracking()
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.blue)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }
}
