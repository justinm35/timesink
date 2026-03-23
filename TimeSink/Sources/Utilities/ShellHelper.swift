import Foundation

/// Executes shell commands asynchronously.
///
/// Designed for running tmux, kitty, and other CLI tools from the app.
/// Ensures `/opt/homebrew/bin` is in PATH since GUI apps don't inherit shell PATH.
enum ShellHelper {

    /// The default PATH to use, including Homebrew.
    private static let defaultPath = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

    /// Runs a shell command and returns its stdout as a string.
    ///
    /// - Parameters:
    ///   - command: The shell command to execute (passed to `/bin/zsh -c`).
    ///   - timeout: Maximum time to wait in seconds. Defaults to 5.
    /// - Returns: The trimmed stdout output.
    /// - Throws: `ShellError` if the command fails or times out.
    static func run(_ command: String, timeout: TimeInterval = 5) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = ["-c", command]
            process.environment = [
                "PATH": defaultPath,
                "HOME": NSHomeDirectory(),
                "LANG": "en_US.UTF-8",
            ]

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Timeout handling
            let timeoutWorkItem = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timeoutWorkItem)

            do {
                try process.run()
                process.waitUntilExit()
                timeoutWorkItem.cancel()

                let data = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                    let stderrOutput = String(data: stderrData, encoding: .utf8) ?? ""
                    continuation.resume(throwing: ShellError.nonZeroExit(
                        status: process.terminationStatus,
                        stderr: stderrOutput,
                        command: command
                    ))
                }
            } catch {
                timeoutWorkItem.cancel()
                continuation.resume(throwing: ShellError.launchFailed(error))
            }
        }
    }

    /// Runs a command and returns the output, or nil if it fails.
    /// Useful for best-effort queries like checking if tmux is running.
    static func runOptional(_ command: String, timeout: TimeInterval = 5) async -> String? {
        try? await run(command, timeout: timeout)
    }
}

// MARK: - ShellError

enum ShellError: LocalizedError, Sendable {
    case nonZeroExit(status: Int32, stderr: String, command: String)
    case launchFailed(Error)
    case timeout(command: String)

    var errorDescription: String? {
        switch self {
        case .nonZeroExit(let status, let stderr, let command):
            return "Command '\(command)' exited with status \(status): \(stderr)"
        case .launchFailed(let error):
            return "Failed to launch process: \(error.localizedDescription)"
        case .timeout(let command):
            return "Command '\(command)' timed out"
        }
    }
}
