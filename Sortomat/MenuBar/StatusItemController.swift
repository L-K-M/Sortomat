import AppKit
import Combine

/// The menu-bar item and its menu. The menu is rebuilt each time it opens so it
/// reflects the current status, recent activity and pending-review count.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let state: AppState
    private let onOpenSettings: () -> Void
    private let onOpenMain: (SidebarSelection) -> Void
    private let onCheckForUpdates: () -> Void
    private var cancellables: Set<AnyCancellable> = []

    init(
        state: AppState,
        onOpenSettings: @escaping () -> Void,
        onOpenMain: @escaping (SidebarSelection) -> Void,
        onCheckForUpdates: @escaping () -> Void
    ) {
        self.state = state
        self.onOpenSettings = onOpenSettings
        self.onOpenMain = onOpenMain
        self.onCheckForUpdates = onCheckForUpdates
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        let menu = NSMenu()
        menu.delegate = self
        // Our items carry explicit `isEnabled` state; with auto-enabling on,
        // AppKit re-enables anything whose target responds to its action, so a
        // deliberately disabled "Check now" (while paused) looked clickable.
        menu.autoenablesItems = false
        statusItem.menu = menu
        updateIcon()

        // Reflect pause / pending state in the icon as it changes.
        state.$paused.sink { [weak self] _ in Task { @MainActor in self?.updateIcon() } }
            .store(in: &cancellables)
        state.$pendingActions.sink { [weak self] _ in Task { @MainActor in self?.updateIcon() } }
            .store(in: &cancellables)
        state.$holdReason.sink { [weak self] _ in Task { @MainActor in self?.updateIcon() } }
            .store(in: &cancellables)
        state.$usage.sink { [weak self] _ in Task { @MainActor in self?.updateIcon() } }
            .store(in: &cancellables)
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        button.image = Self.funnelImage()
        // Greyed while held as well as while paused: the icon is the only
        // thing on screen, so it has to carry "not running right now".
        button.appearsDisabled = state.paused || state.holdReason != nil
            || !state.withinMonthlyBudget
        // Surface pending reviews right in the menu bar: a small count next to
        // the funnel. Without it, queued suggestions were invisible until the
        // menu was opened (the $pendingActions subscription existed but the
        // icon never used it).
        let pending = state.pendingActions.count
        button.imagePosition = pending > 0 ? .imageLeft : .imageOnly
        button.title = pending > 0 ? " \(pending)" : ""
    }

    /// Sortomat's monochrome mark — a sorting funnel — drawn as a template image
    /// so it tints correctly for light and dark menu bars.
    ///
    /// It is deliberately *not* the app icon. The icon is a photographic render
    /// of the machine; flattened to one colour at 18 points it would be a
    /// smudge. A menu-bar item wants a silhouette, and this is Sortomat's.
    ///
    /// The inset is deliberate too: the glyph used to span 0.10–0.90 of an
    /// 18-point square as a *solid* fill, which puts far more ink on screen
    /// than the stroked system symbols beside it and made Sortomat's funnel
    /// the heaviest thing in the menu bar. Smaller is what "the same weight as
    /// its neighbours" looks like for a filled glyph.
    static func funnelImage(width: CGFloat = 18) -> NSImage {
        let size = NSSize(width: width, height: width)
        let image = NSImage(size: size, flipped: false) { rect in
            let w = rect.width, h = rect.height
            // y measured from the top (converted to AppKit's bottom-left origin).
            func p(_ x: CGFloat, _ topY: CGFloat) -> NSPoint {
                NSPoint(x: rect.minX + x * w, y: rect.minY + (1 - topY) * h)
            }
            let path = NSBezierPath()
            path.move(to: p(0.170, 0.22))
            path.line(to: p(0.830, 0.22))
            path.line(to: p(0.605, 0.50))
            path.line(to: p(0.605, 0.78))
            path.line(to: p(0.395, 0.78))
            path.line(to: p(0.395, 0.50))
            path.close()
            NSColor.black.setFill()
            path.fill()
            return true
        }
        image.isTemplate = true
        return image
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

        menu.addItem(BlockMenuItem(
            title: state.pendingActions.isEmpty
                ? L10n.t("menu.openMain")
                : L10n.plural("menu.pendingReview", state.pendingActions.count)
        ) { [weak self] in self?.onOpenMain(.inbox) })
        menu.addItem(BlockMenuItem(title: L10n.t("menu.openHistory")) { [weak self] in
            self?.onOpenMain(.history)
        })
        menu.addItem(BlockMenuItem(title: state.paused ? L10n.t("menu.resume") : L10n.t("menu.pause")) {
            [weak self] in self?.state.paused.toggle()
        })
        let scanItem = BlockMenuItem(title: L10n.t("menu.scanNow"), enabled: !state.paused) {
            [weak self] in self?.state.requestScan()
        }
        menu.addItem(scanItem)
        menu.addItem(BlockMenuItem(title: L10n.t("menu.previewNow")) { [weak self] in
            self?.onOpenMain(.inbox)
            Task { await self?.state.refreshPreview() }
        })

        menu.addItem(.separator())
        menu.addItem(activityItem())

        menu.addItem(.separator())
        let settings = BlockMenuItem(title: L10n.t("menu.settings"), keyEquivalent: ",") {
            [weak self] in self?.onOpenSettings()
        }
        menu.addItem(settings)
        menu.addItem(BlockMenuItem(title: L10n.t("menu.checkUpdates")) { [weak self] in
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
        } else if !state.withinMonthlyBudget {
            // The same principle as the power holds: model-bound files pile up
            // deferred while the menu says "Active — 3 rules", and the only
            // other signal is a caption inside Settings.
            text = L10n.t("hold.budget")
        } else if let hold = state.holdReason {
            // A hold nobody can see is indistinguishable from a broken app:
            // the funnel sits there, nothing gets filed, and the menu says
            // "Active".
            text = hold
        } else {
            text = L10n.plural("app.status.active", state.enabledRuleCount)
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
