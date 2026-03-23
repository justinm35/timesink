import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Swift wrapper around the macOS Accessibility (AX) API.
///
/// Provides clean interfaces for checking permissions and reading window titles
/// from the otherwise verbose C-style CoreFoundation APIs.
enum AccessibilityHelper {

    // MARK: - Permissions

    /// Whether the app has been granted Accessibility access.
    static var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility access (shows the system dialog).
    /// Only shows once per launch; subsequent calls are no-ops unless the user restarts.
    static func requestAccessibility() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue()
        let options = [key: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Opens System Settings directly to Accessibility privacy pane.
    @MainActor
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Window Title

    /// Reads the title of the focused window for the given process.
    ///
    /// - Parameter pid: The process identifier of the target application.
    /// - Returns: The window title string, or nil if unavailable.
    static func windowTitle(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        // Get the focused window
        var focusedWindowValue: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard windowResult == .success,
              let focusedWindow = focusedWindowValue
        else {
            // Fallback: try to get the title from the app element itself
            return attributeString(from: appElement, attribute: kAXTitleAttribute)
        }

        // Get the title from the focused window
        let windowElement = focusedWindow as! AXUIElement
        return attributeString(from: windowElement, attribute: kAXTitleAttribute)
    }

    /// Reads the document/URL from the focused window (some apps expose this).
    static func windowDocument(for pid: pid_t) -> String? {
        let appElement = AXUIElementCreateApplication(pid)

        var focusedWindowValue: CFTypeRef?
        let windowResult = AXUIElementCopyAttributeValue(
            appElement,
            kAXFocusedWindowAttribute as CFString,
            &focusedWindowValue
        )

        guard windowResult == .success, let focusedWindow = focusedWindowValue else {
            return nil
        }

        let windowElement = focusedWindow as! AXUIElement
        return attributeString(from: windowElement, attribute: kAXDocumentAttribute)
    }

    // MARK: - Private

    /// Extracts a string attribute from an AXUIElement.
    private static func attributeString(from element: AXUIElement, attribute: String) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let stringValue = value as? String else {
            return nil
        }
        return stringValue
    }
}
