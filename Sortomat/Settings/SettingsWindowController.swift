import AppKit
import SwiftUI

/// Hosts `SettingsView`, flipping the agent to `.regular` while visible so the
/// window can take focus and show in the Dock, then back to `.accessory` on
/// close. Rules moved to the main window: this holds the things you set once.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func show() {
        if let window {
            present(window)
            return
        }
        let hosting = NSHostingController(rootView: SettingsView().environmentObject(state))
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.t("settings.window.title")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 860, height: 560))
        window.minSize = NSSize(width: 720, height: 460)
        window.delegate = self
        window.center()
        // Restore last position/size across launches (center() is the fallback
        // for the very first one).
        window.setFrameAutosaveName("SortomatSettingsWindow")
        self.window = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        ActivationPolicy.showRegular()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        ActivationPolicy.revertToAccessoryIfNoOrdinaryWindows(excluding: window)
    }
}
