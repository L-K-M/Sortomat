import Foundation
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var paused = false {
        didSet { if !paused { requestScan() } }
    }
    @Published var activity: [ActivityEntry] = []
    @Published var lastScan: Date?
    @Published var apiKeyMissing: Bool

    private let pipeline = Pipeline()
    private var watchers: [FolderWatcher] = []
    private var persistTask: Task<Void, Never>?
    private var scanRequested = false
    private var scanRunning = false
    private var timerTask: Task<Void, Never>?

    init() {
        config = ConfigStore.load()
        apiKeyMissing = (Keychain.apiKey() ?? "").isEmpty
        rebuildWatchers()
        startTimer()
        requestScan()
    }

    var enabledRuleCount: Int { config.rules.filter(\.enabled).count }

    // MARK: - Config persistence

    /// Debounced: saving on every keystroke of the settings form is fine for
    /// JSON, but watcher file descriptors shouldn't churn that fast.
    func persistAndApply() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            ConfigStore.save(self.config)
            self.rebuildWatchers()
        }
    }

    func saveAPIKey(_ key: String) {
        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines),
                     account: Keychain.apiKeyAccount)
        apiKeyMissing = (Keychain.apiKey() ?? "").isEmpty
        requestScan()
    }

    private func rebuildWatchers() {
        watchers = config.rules
            .filter { $0.enabled && !$0.watchPath.isEmpty }
            .compactMap { rule in
                FolderWatcher(path: rule.watchPath) { [weak self] in
                    Task { @MainActor in self?.requestScan() }
                }
            }
    }

    // MARK: - Scanning

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = await MainActor.run { self?.config.scanIntervalSeconds ?? 60 }
                try? await Task.sleep(nanoseconds: UInt64(max(interval, 10) * 1_000_000_000))
                await MainActor.run { self?.requestScan() }
            }
        }
    }

    /// Coalesces watcher events and timer ticks into single scan passes.
    func requestScan() {
        guard !paused else { return }
        scanRequested = true
        guard !scanRunning else { return }
        scanRunning = true
        Task { [weak self] in
            // Small debounce so a burst of file events becomes one scan.
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            await self?.runScans()
        }
    }

    private func runScans() async {
        defer { scanRunning = false }
        while scanRequested {
            scanRequested = false
            guard !paused, let apiKey = Keychain.apiKey(), !apiKey.isEmpty else { return }
            let snapshot = config
            for rule in snapshot.rules where rule.enabled {
                let entries = await pipeline.scan(
                    rule: rule, config: snapshot, apiKey: apiKey
                )
                if !entries.isEmpty {
                    activity.insert(contentsOf: entries.reversed(), at: 0)
                    activity = Array(activity.prefix(50))
                    entries.forEach { ConfigStore.appendLog($0.message) }
                }
            }
            lastScan = Date()
        }
    }
}
