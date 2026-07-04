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

        updateChecker.checkOnLaunch()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
