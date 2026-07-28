import UIKit

/// Keeps the device awake while one or more syncs are in flight. Ref-counted
/// so Local and WebDAV syncs (which run through independent controllers) can
/// overlap without one finishing and re-enabling the idle timer out from
/// under the other.
@MainActor
enum IdleTimerGuard {
    private static var activeCount = 0

    static func begin() {
        activeCount += 1
        UIApplication.shared.isIdleTimerDisabled = true
    }

    static func end() {
        activeCount = max(0, activeCount - 1)
        if activeCount == 0 {
            UIApplication.shared.isIdleTimerDisabled = false
        }
    }
}
