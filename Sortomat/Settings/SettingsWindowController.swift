import AppKit
import SwiftUI

/// Hosts `SettingsView`, flipping the agent to `.regular` while visible so the
/// window can take focus and show in the Dock, then back to `.accessory` on close.
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
        self.window = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        ActivationPolicy.showRegular()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        // Editing is over — let the rule run again and scan promptly.
        state.editingRuleID = nil
        state.requestScan()
        ActivationPolicy.revertToAccessoryIfNoOrdinaryWindows(excluding: window)
    }
}
