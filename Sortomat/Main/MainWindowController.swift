import AppKit
import Combine
import SwiftUI

/// Hosts the main window and owns the sidebar selection, so the menu bar can
/// open the window straight onto the Inbox or a particular rule.
///
/// The selection lives here rather than in `MainView`'s `@State` because it
/// outlives the view: closing and reopening the window should land where the
/// user left off, and "show me this rule" has to be answerable from outside.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate, ObservableObject {
    @Published var selection: SidebarSelection = .inbox {
        // A rule open in the editor must not also be executing: a half-typed
        // instruction would otherwise fire on the next pass.
        didSet { state.setEditingRule(selection.ruleID) }
    }

    private var window: NSWindow?
    private let state: AppState

    init(state: AppState) {
        self.state = state
    }

    func show(_ selection: SidebarSelection? = nil) {
        if let selection { self.selection = selection }
        if let window {
            present(window)
            return
        }
        let hosting = NSHostingController(
            rootView: MainWindowRoot(controller: self).environmentObject(state)
        )
        let window = NSWindow(contentViewController: hosting)
        window.title = L10n.t("main.window.title")
        window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 940, height: 600))
        window.minSize = NSSize(width: 820, height: 520)
        window.delegate = self
        window.center()
        // Restore last position/size across launches (center() is the fallback
        // for the very first one).
        window.setFrameAutosaveName("SortomatMainWindow")
        self.window = window
        present(window)
    }

    private func present(_ window: NSWindow) {
        ActivationPolicy.showRegular()
        window.makeKeyAndOrderFront(nil)
        state.setEditingRule(selection.ruleID)
    }

    func windowWillClose(_ notification: Notification) {
        // Editing is over — let the rule run again (and kick a check).
        state.setEditingRule(nil)
        ActivationPolicy.revertToAccessoryIfNoOrdinaryWindows(excluding: window)
    }
}

/// A thin observing wrapper: `MainView` binds to the controller's selection, so
/// AppKit and SwiftUI agree on which pane is showing.
private struct MainWindowRoot: View {
    @ObservedObject var controller: MainWindowController

    var body: some View {
        MainView(selection: Binding(
            get: { controller.selection },
            set: { controller.selection = $0 }
        ))
    }
}
