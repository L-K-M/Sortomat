import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var statusItem: StatusItemController!
    private var settingsWindow: SettingsWindowController!
    private var mainWindow: MainWindowController!
    private var updateChecker: UpdateChecker!

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// macOS delivers the response to a click that *launched* the app as soon
    /// as launching finishes, and drops it if no notification delegate exists
    /// by then. Registering it here rather than in `didFinishLaunching` is what
    /// makes Undo work on a banner left over from a previous session.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Notifier.prepareForLaunch()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't boot the full app under XCTest — the test host stays quiet.
        guard !Self.isRunningTests else { return }

        state = AppState()
        updateChecker = UpdateChecker(configuration: .init(
            owner: AppInfo.repoOwner,
            repo: AppInfo.repoName,
            appName: "Sortomat",
            currentVersion: AppInfo.shortVersion
        ))
        settingsWindow = SettingsWindowController(state: state)
        mainWindow = MainWindowController(state: state)
        statusItem = StatusItemController(
            state: state,
            onOpenSettings: { [weak self] in self?.settingsWindow.show() },
            onOpenMain: { [weak self] selection in self?.mainWindow.show(selection) },
            onCheckForUpdates: { [weak self] in Task { await self?.updateChecker.check(userInitiated: true) } }
        )

        // What the buttons on a notification do. Installed before the first
        // pass can post one.
        Notifier.handler = { [weak self] action in
            guard let self else { return }
            switch action {
            case .undo(let batch):
                // Only this case needs the state. Requiring it up front made
                // "Show in Finder" and "Open log" — neither of which touches
                // the app's state — inert in any situation where it were nil.
                guard let state = self.state else { return }
                Task { await state.undo(batch: batch, announcing: true) }
            case .reveal(let url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .openLog:
                NSWorkspace.shared.open(ConfigStore.logFile)
            case .open:
                // The Preview window this used to open is gone; the Inbox is
                // where a pending decision lives now.
                self.mainWindow.show(.inbox)
            }
        }

        // A real Edit menu so ⌘X/⌘C/⌘V/⌘A/⌘Z work in text fields, and ⌘0 to
        // bring the main window back once it has been closed. Built after the
        // window controller exists, because ⌘0 needs something to open.
        NSApp.mainMenu = MainMenu.build(onOpenMain: { [weak self] in self?.mainWindow.show() })

        // A menu-bar-only app that opens nothing on its first launch is
        // indistinguishable from one that didn't launch: there is no window, no
        // Dock icon, and the funnel in the menu bar is 18 points of monochrome
        // among twenty others. Show the window once, the first time.
        if !UserDefaults.standard.bool(forKey: Self.didShowMainWindowKey) {
            UserDefaults.standard.set(true, forKey: Self.didShowMainWindowKey)
            mainWindow.show(.inbox)
        }

        updateChecker.checkOnLaunch()
    }

    static let didShowMainWindowKey = "SortomatDidShowMainWindow"

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        // Quit mid-scan used to drop every in-memory ledger record of the
        // running pass (skips the model was just paid for) and the session's
        // token usage.
        state?.flushOnTerminate()
    }
}
