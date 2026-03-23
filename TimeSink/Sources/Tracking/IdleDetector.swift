import CoreGraphics
import Foundation

/// Detects user idle state by checking time since last mouse/keyboard input.
///
/// Uses `CGEventSource.secondsSinceLastEventType` which requires either
/// Accessibility permission or running outside the sandbox.
struct IdleDetector: Sendable {

    /// The number of seconds of inactivity before considering the user idle.
    let idleThreshold: TimeInterval

    init(idleThreshold: TimeInterval = 120) {
        self.idleThreshold = idleThreshold
    }

    /// Whether the user is currently idle (no mouse or keyboard input for `idleThreshold` seconds).
    var isIdle: Bool {
        secondsSinceLastActivity > idleThreshold
    }

    /// Seconds since the last mouse movement.
    var secondsSinceLastMouseMove: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .mouseMoved)
    }

    /// Seconds since the last key press.
    var secondsSinceLastKeyDown: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: .keyDown)
    }

    /// Seconds since any user input (minimum of mouse and keyboard idle times).
    var secondsSinceLastActivity: TimeInterval {
        min(secondsSinceLastMouseMove, secondsSinceLastKeyDown)
    }
}
