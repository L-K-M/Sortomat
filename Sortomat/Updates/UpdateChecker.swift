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

    private var lastCheckKey: String { "UpdateChecker.\(config.owner).\(config.repo).lastCheck" }
    private var skipVersionKey: String { "UpdateChecker.\(config.owner).\(config.repo).skip" }

    init(configuration: Configuration, defaults: UserDefaults = .standard) {
        self.config = configuration
        self.client = GitHubReleaseClient(owner: configuration.owner, repo: configuration.repo)
        self.defaults = defaults
    }

    func checkOnLaunch() {
        let last = defaults.object(forKey: lastCheckKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) >= config.minimumCheckInterval else { return }
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        defaults.set(Date(), forKey: lastCheckKey)

        do {
            let release = try await client.latestRelease(allowPrereleases: config.allowPrereleases)
            guard let latest = release.version,
                  let current = SemanticVersion(config.currentVersion) else {
                lastResult = "Couldn't parse version numbers."
                if userInitiated { presentUpToDate() }
                return
            }
            if latest > current {
                if !userInitiated, defaults.string(forKey: skipVersionKey) == release.tagName {
                    return
                }
                lastResult = "Update available: \(release.tagName)"
                present(release: release)
            } else {
                lastResult = "You're up to date (\(config.currentVersion))."
                if userInitiated { presentUpToDate() }
            }
        } catch {
            lastResult = error.localizedDescription
            if userInitiated { presentError(error) }
        }
    }

    // MARK: - Alerts

    private func present(release: GitHubRelease) {
        let alert = NSAlert()
        alert.messageText = "\(config.appName) \(release.tagName) is available"
        alert.informativeText = "You have \(config.currentVersion). Would you like to download the update?"
        alert.addButton(withTitle: "Download")
        alert.addButton(withTitle: "Remind Me Later")
        alert.addButton(withTitle: "Skip This Version")
        ActivationPolicy.showRegular()
        switch alert.runModal() {
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
        alert.messageText = "You're up to date"
        alert.informativeText = "\(config.appName) \(config.currentVersion) is the latest version."
        alert.addButton(withTitle: "OK")
        ActivationPolicy.showRegular()
        alert.runModal()
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn't check for updates"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        ActivationPolicy.showRegular()
        alert.runModal()
    }
}
