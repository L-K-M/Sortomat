import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var state: AppState!
    private var statusItem: StatusItemController!
    private var settingsWindow: SettingsWindowController!
    private var previewWindow: PreviewWindowController!
    private var updateChecker: UpdateChecker!

    static var isRunningTests: Bool {
        NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Don't boot the full app under XCTest — the test host stays quiet.
        guard !Self.isRunningTests else { return }

        // A real Edit menu so ⌘X/⌘C/⌘V/⌘A/⌘Z work in text fields.
        NSApp.mainMenu = MainMenu.build()

        state = AppState()
        updateChecker = UpdateChecker(configuration: .init(
            owner: AppInfo.repoOwner,
            repo: AppInfo.repoName,
            appName: "Sortomat",
            currentVersion: AppInfo.shortVersion
        ))
        settingsWindow = SettingsWindowController(state: state)
        previewWindow = PreviewWindowController(state: state)
        statusItem = StatusItemController(
            state: state,
            onOpenSettings: { [weak self] in self?.settingsWindow.show() },
            onOpenPreview: { [weak self] in self?.previewWindow.show() },
            onCheckForUpdates: { [weak self] in Task { await self?.updateChecker.check(userInitiated: true) } }
        )

        // What the buttons on a notification do. Installed before the first
        // pass can post one.
        Notifier.handler = { [weak self] action in
            guard let self, let state = self.state else { return }
            switch action {
            case .undo(let batch):
                Task { await state.undo(batch: batch) }
            case .reveal(let url):
                NSWorkspace.shared.activateFileViewerSelecting([url])
            case .openLog:
                NSWorkspace.shared.open(ConfigStore.logFile)
            case .open:
                self.previewWindow.show()
            }
        }

        updateChecker.checkOnLaunch()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        // Quit mid-scan used to drop every in-memory ledger record of the
        // running pass (skips the model was just paid for) and the session's
        // token usage.
        state?.flushOnTerminate()
    }
}
