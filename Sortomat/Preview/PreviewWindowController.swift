import AppKit
import SwiftUI

/// Hosts the dry-run review + history window.
@MainActor
final class PreviewWindowController: NSObject, NSWindowDelegate {
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
        let hosting = NSHostingController(rootView: PreviewView().environmentObject(state))
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.t("preview.title")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 820, height: 520))
        window.minSize = NSSize(width: 640, height: 380)
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
        ActivationPolicy.revertToAccessoryIfNoOrdinaryWindows(excluding: window)
    }
}
