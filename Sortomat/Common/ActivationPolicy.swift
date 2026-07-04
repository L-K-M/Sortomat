import AppKit

/// The `.accessory` ↔ `.regular` dance a menu-bar agent performs when it shows a
/// real window (so the window can take focus and appear in the Dock) and then
/// drops back to `.accessory` once no ordinary windows remain open.
enum ActivationPolicy {
    static func showRegular() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Call from a window's `windowWillClose`. Reverts to `.accessory` unless
    /// another ordinary window is still open.
    static func revertToAccessoryIfNoOrdinaryWindows(excluding window: NSWindow?) {
        let stillOpen = NSApp.windows.contains { candidate in
            candidate != window
                && (candidate.isVisible || candidate.isMiniaturized)
                && candidate.canBecomeMain
        }
        if !stillOpen {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
