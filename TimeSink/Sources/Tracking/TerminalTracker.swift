import Foundation

/// Tracks terminal activity by polling tmux and kitty.
///
/// When Kitty (or another terminal) is the active app, this tracker provides
/// detailed info about what's running: the command, working directory, and session.
final class TerminalTracker: @unchecked Sendable {

    /// Cached info about the last polled active pane.
    /// Used by ActivityMonitor synchronously during its poll cycle.
    private(set) var lastPaneInfo: String?

    /// Full path to tmux binary.
    private let tmuxPath: String

    /// Structured info about a tmux pane.
    struct PaneInfo: Sendable {
        let sessionName: String
        let windowIndex: Int
        let paneIndex: Int
        let command: String
        let currentPath: String

        /// Formatted display string: "nvim @ ~/projects/all-gravy"
        var displayString: String {
            let shortPath = currentPath.replacingOccurrences(
                of: FileManager.default.homeDirectoryForCurrentUser.path,
                with: "~"
            )
            return "\(command) @ \(shortPath)"
        }
    }

    init(tmuxPath: String = "/opt/homebrew/bin/tmux") {
        self.tmuxPath = tmuxPath
    }

    // MARK: - Active Pane Polling

    /// Polls tmux for the currently active pane's info and caches it.
    /// Call this periodically from the activity monitor's poll loop.
    func pollActivPane() async {
        // First try tmux
        if let paneInfo = await getActiveTmuxPane() {
            lastPaneInfo = paneInfo.displayString
            return
        }

        // Fallback: try kitty remote control
        if let kittyInfo = await getActiveKittyWindow() {
            lastPaneInfo = kittyInfo
            return
        }

        lastPaneInfo = nil
    }

    // MARK: - tmux

    /// Gets the active tmux pane info.
    private func getActiveTmuxPane() async -> PaneInfo? {
        guard let output = await ShellHelper.runOptional(
            "\(tmuxPath) display-message -p '#{session_name} #{window_index} #{pane_index} #{pane_current_command} #{pane_current_path}'"
        ) else {
            return nil
        }

        return parsePaneLine(output)
    }

    /// Lists all tmux panes across all sessions.
    func listAllPanes() async -> [PaneInfo] {
        guard let output = await ShellHelper.runOptional(
            "\(tmuxPath) list-panes -a -F '#{session_name} #{window_index} #{pane_index} #{pane_current_command} #{pane_current_path}'"
        ) else {
            return []
        }

        return output
            .components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { parsePaneLine($0) }
    }

    /// Parses a tmux format line into a PaneInfo.
    private func parsePaneLine(_ line: String) -> PaneInfo? {
        let parts = line.components(separatedBy: " ")
        guard parts.count >= 5 else { return nil }

        let sessionName = parts[0]
        let windowIndex = Int(parts[1]) ?? 0
        let paneIndex = Int(parts[2]) ?? 0
        let command = parts[3]
        let currentPath = parts[4...].joined(separator: " ") // path may contain spaces

        return PaneInfo(
            sessionName: sessionName,
            windowIndex: windowIndex,
            paneIndex: paneIndex,
            command: command,
            currentPath: currentPath
        )
    }

    // MARK: - Kitty

    /// Gets the active kitty window info using kitty's remote control.
    private func getActiveKittyWindow() async -> String? {
        guard let output = await ShellHelper.runOptional("kitty @ ls") else {
            return nil
        }

        // Parse the JSON output from kitty
        return parseKittyOutput(output)
    }

    /// Parses `kitty @ ls` JSON output to find the active window's title/cwd.
    private func parseKittyOutput(_ json: String) -> String? {
        guard let data = json.data(using: .utf8) else { return nil }

        do {
            // kitty @ ls returns an array of OS windows, each containing tabs,
            // each containing windows (kitty's internal windows, not OS windows)
            guard let osWindows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                return nil
            }

            for osWindow in osWindows {
                guard let isFocused = osWindow["is_focused"] as? Bool, isFocused,
                      let tabs = osWindow["tabs"] as? [[String: Any]]
                else { continue }

                for tab in tabs {
                    guard let isActiveTab = tab["is_focused"] as? Bool, isActiveTab,
                          let windows = tab["windows"] as? [[String: Any]]
                    else { continue }

                    for window in windows {
                        guard let isFocusedWindow = window["is_focused"] as? Bool, isFocusedWindow else { continue }

                        let title = window["title"] as? String ?? ""
                        let cwd = (window["cwd"] as? String)?.replacingOccurrences(
                            of: FileManager.default.homeDirectoryForCurrentUser.path,
                            with: "~"
                        ) ?? ""

                        // Extract the foreground process name
                        if let foregroundProcesses = window["foreground_processes"] as? [[String: Any]],
                           let firstProcess = foregroundProcesses.first,
                           let cmdline = firstProcess["cmdline"] as? [String],
                           let command = cmdline.first
                        {
                            let shortCommand = (command as NSString).lastPathComponent
                            return "\(shortCommand) @ \(cwd)"
                        }

                        return title.isEmpty ? cwd : "\(title) @ \(cwd)"
                    }
                }
            }
        } catch {
            print("Failed to parse kitty output: \(error)")
        }

        return nil
    }
}
