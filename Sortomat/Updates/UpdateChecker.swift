import AppKit
import Foundation

/// Checks GitHub Releases for a newer build on launch (throttled to once a day)
/// and on demand from the menu. Dependency-free; the release page opens in the
/// browser for the user to download the signed/unsigned DMG.
@MainActor
final class UpdateChecker: ObservableObject {
    struct Configuration {
        var owner: String
        var repo: String
        var appName: String
        var currentVersion: String
        var allowPrereleases: Bool = false
        var minimumCheckInterval: TimeInterval = 60 * 60 * 24
    }

    @Published private(set) var isChecking = false
    @Published private(set) var lastResult: String?

    private let config: Configuration
    private let client: GitHubReleaseClient
    private let defaults: UserDefaults
    private var periodicTask: Task<Void, Never>?

    private var lastCheckKey: String { "UpdateChecker.\(config.owner).\(config.repo).lastCheck" }
    private var skipVersionKey: String { "UpdateChecker.\(config.owner).\(config.repo).skip" }

    init(configuration: Configuration, defaults: UserDefaults = .standard) {
        self.config = configuration
        self.client = GitHubReleaseClient(owner: configuration.owner, repo: configuration.repo)
        self.defaults = defaults
    }

    deinit { periodicTask?.cancel() }

    func checkOnLaunch() {
        let last = defaults.object(forKey: lastCheckKey) as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= config.minimumCheckInterval {
            Task { await check(userInitiated: false) }
        }
        startPeriodicChecks()
    }

    /// A menu-bar agent can stay up for weeks; checking only at launch means it
    /// never re-checks. Re-evaluate a few times a day — the actual network call
    /// still happens at most once per `minimumCheckInterval`.
    private func startPeriodicChecks() {
        guard periodicTask == nil else { return }
        periodicTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6 * 3_600 * 1_000_000_000)
                guard let self, !Task.isCancelled else { return }
                let last = self.defaults.object(forKey: self.lastCheckKey) as? Date ?? .distantPast
                if Date().timeIntervalSince(last) >= self.config.minimumCheckInterval {
                    await self.check(userInitiated: false)
                }
            }
        }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let release = try await client.latestRelease(allowPrereleases: config.allowPrereleases)
            // Stamp only after a *successful* fetch: stamping up front meant a
            // failed launch-time check (offline Mac waking up) suppressed any
            // retry for a full day.
            defaults.set(Date(), forKey: lastCheckKey)
            guard let latest = release.version,
                  let current = SemanticVersion(config.currentVersion) else {
                lastResult = L10n.t("updates.parseFailed")
                if userInitiated { presentCheckFailed(L10n.t("updates.parseFailed")) }
                return
            }
            if latest > current {
                if !userInitiated, defaults.string(forKey: skipVersionKey) == release.tagName {
                    return
                }
                lastResult = L10n.t("updates.lastResult.available", release.tagName)
                present(release: release)
            } else {
                lastResult = L10n.t("updates.lastResult.upToDate", config.currentVersion)
                if userInitiated { presentUpToDate() }
            }
        } catch {
            lastResult = error.localizedDescription
            if userInitiated { presentError(error) }
        }
    }

    // MARK: - Alerts

    /// Run an alert with the `.accessory` ↔ `.regular` dance: without the
    /// revert after `runModal`, "Check for Updates…" left a permanent Dock
    /// icon on a menu-bar-only app.
    private func runModalAsRegularApp(_ alert: NSAlert) -> NSApplication.ModalResponse {
        ActivationPolicy.showRegular()
        defer { ActivationPolicy.revertToAccessoryIfNoOrdinaryWindows(excluding: nil) }
        return alert.runModal()
    }

    private func present(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = L10n.t("updates.available.title", config.appName, release.tagName)
        alert.informativeText = L10n.t("updates.available.body", config.currentVersion)
        alert.addButton(withTitle: L10n.t("updates.available.download"))
        alert.addButton(withTitle: L10n.t("updates.available.later"))
        alert.addButton(withTitle: L10n.t("updates.available.skip"))
        switch runModalAsRegularApp(alert) {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(release.preferredAsset?.browserDownloadURL ?? release.htmlURL)
        case .alertThirdButtonReturn:
            defaults.set(release.tagName, forKey: skipVersionKey)
        default:
            break
        }
    }

    private func presentUpToDate() {
        let alert = NSAlert()
        alert.messageText = L10n.t("updates.upToDate.title")
        alert.informativeText = L10n.t("updates.upToDate.body", config.appName, config.currentVersion)
        alert.addButton(withTitle: L10n.t("updates.ok"))
        _ = runModalAsRegularApp(alert)
    }

    private func presentCheckFailed(_ message: String) {
        let alert = NSAlert()
        alert.messageText = L10n.t("updates.failed.title")
        alert.informativeText = message
        alert.addButton(withTitle: L10n.t("updates.ok"))
        _ = runModalAsRegularApp(alert)
    }

    private func presentError(_ error: Error) {
        presentCheckFailed(error.localizedDescription)
    }
}
