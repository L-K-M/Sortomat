import AppKit
import Combine

/// The menu-bar item and its menu. The menu is rebuilt each time it opens so it
/// reflects the current status, recent activity and pending-review count.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let state: AppState
    private let onOpenSettings: () -> Void
    private let onOpenPreview: () -> Void
    private let onCheckForUpdates: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        state: AppState,
        onOpenSettings: @escaping () -> Void,
        onOpenPreview: @escaping () -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.state = state
        self.onOpenSettings = onOpenSettings
        self.onOpenPreview = onOpenPreview
        self.onCheckForUpdates = onCheckForUpdates
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()

        // Reflect pause / pending state in the icon as it changes.
        state.$paused.sink { [weak self] _ in Task { @MainActor in self?.updateIcon() } }
            .store(in: &cancellables)
        state.$pendingActions.sink { [weak self] _ in Task { @MainActor in self?.updateIcon() } }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let symbol = state.paused ? "tray" : "tray.full"
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Sortomat")
        button.image?.isTemplate = true
        button.appearsDisabled = state.paused
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(statusHeaderItem())
        if let last = state.lastScan {
            menu.addItem(disabled(L10n.t("app.lastScan", last.formatted(date: .omitted, time: .shortened))))
        }
        if state.estimatedSpend > 0 {
            menu.addItem(disabled(L10n.t("menu.spend", state.estimatedSpendString)))
        }

        menu.addItem(.separator())

        if !state.pendingActions.isEmpty {
            menu.addItem(BlockMenuItem(title: L10n.t("menu.pendingReview", state.pendingActions.count)) {
                [weak self] in self?.onOpenPreview()
            })
        }
        menu.addItem(BlockMenuItem(title: state.paused ? L10n.t("menu.resume") : L10n.t("menu.pause")) {
            [weak self] in self?.state.paused.toggle()
        })
        let scanItem = BlockMenuItem(title: L10n.t("menu.scanNow"), enabled: !state.paused) {
            [weak self] in self?.state.requestScan()
        }
        menu.addItem(scanItem)
        menu.addItem(BlockMenuItem(title: L10n.t("menu.previewNow")) { [weak self] in
            self?.onOpenPreview()
            Task { await self?.state.refreshPreview() }
        })

        menu.addItem(.separator())
        menu.addItem(activityItem())

        menu.addItem(.separator())
        let settings = BlockMenuItem(title: L10n.t("menu.settings"), keyEquivalent: ",") {
            [weak self] in self?.onOpenSettings()
        }
        menu.addItem(settings)
        menu.addItem(BlockMenuItem(title: "Check for Updates…") { [weak self] in
            self?.onCheckForUpdates()
        })
        menu.addItem(.separator())
        menu.addItem(BlockMenuItem(title: L10n.t("menu.quit"), keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
    }

    private func statusHeaderItem() -> NSMenuItem {
        let text: String
        if state.apiKeyMissing {
            text = L10n.t("app.status.noKey")
        } else if state.paused {
            text = L10n.t("app.status.paused")
        } else {
            text = L10n.t("app.status.active", state.enabledRuleCount)
        }
        return disabled(text)
    }

    private func activityItem() -> NSMenuItem {
        guard !state.activity.isEmpty else {
            return disabled(L10n.t("menu.noActivity"))
        }
        let parent = NSMenuItem(title: L10n.t("menu.recentActivity"), action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        for entry in state.activity.prefix(15) {
            submenu.addItem(disabled((entry.ok ? "" : "⚠️ ") + entry.message))
        }
        submenu.addItem(.separator())
        submenu.addItem(BlockMenuItem(title: L10n.t("menu.openLog")) {
            NSWorkspace.shared.open(ConfigStore.logFile)
        })
        parent.submenu = submenu
        return parent
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
