import Combine
import Foundation
import SwiftUI

/// The shared, observable heart of the GUI: holds the config and activity, owns
/// the folder watchers and the periodic timer, coalesces scans, and runs plans
/// through the Pipeline actor. Kept on the main actor; the heavy lifting hops to
/// the Pipeline.
@MainActor
final class AppState: ObservableObject {
    @Published var config: Config
    @Published var paused = false {
        didSet { if !paused { requestScan() } }
    }
    @Published var activity: [ActivityEntry] = []
    @Published var pendingActions: [PlannedAction] = []
    @Published var lastScan: Date?
    @Published var apiKeyMissing: Bool
    @Published var usage = TokenUsage()
    /// The rule currently open in the editor. It is not executed while being
    /// edited, so a half-typed rule can't fire mid-edit. Derived from the three
    /// inputs below rather than set directly, so it's correct however the user
    /// leaves the editor (switch tab, switch rule, close the window).
    @Published private(set) var editingRuleID: UUID?
    private var settingsWindowOpen = false
    private var rulesTabActive = false
    private var selectedRuleID: UUID?

    private let pipeline = Pipeline()
    private var watchers: [FSEventsWatcher] = []
    private var persistTask: Task<Void, Never>?
    private var scanRequested = false
    private var scanRunning = false
    private var timerTask: Task<Void, Never>?

    init() {
        let loaded = ConfigStore.load()
        config = loaded
        apiKeyMissing = (Keychain.apiKey() ?? "").isEmpty && loaded.providerRequiresKey
        Notifier.requestAuthorization()
        rebuildWatchers()
        startTimer()
        requestScan()
    }

    var enabledRuleCount: Int { config.rules.filter(\.enabled).count }

    var estimatedSpend: Double {
        Double(usage.input) / 1_000_000 * config.inputPricePerMTok
            + Double(usage.output) / 1_000_000 * config.outputPricePerMTok
    }

    var estimatedSpendString: String {
        String(format: "$%.4f", estimatedSpend)
    }

    // MARK: - Config persistence

    /// Debounced: it's fine to save on every keystroke, but watcher lifetimes
    /// shouldn't churn that fast.
    func persistAndApply() {
        persistTask?.cancel()
        persistTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard let self, !Task.isCancelled else { return }
            ConfigStore.save(self.config)
            self.apiKeyMissing = (Keychain.apiKey() ?? "").isEmpty && self.config.providerRequiresKey
            self.rebuildWatchers()
        }
    }

    func saveAPIKey(_ key: String) {
        Keychain.set(key.trimmingCharacters(in: .whitespacesAndNewlines), account: Keychain.apiKeyAccount)
        apiKeyMissing = (Keychain.apiKey() ?? "").isEmpty && config.providerRequiresKey
        requestScan()
    }

    func addRule(from template: RuleTemplate) {
        var rule = template.makeRule()
        rule.name = uniqueName(rule.name)
        config.rules.append(rule)
        persistAndApply()
    }

    func duplicate(ruleID: UUID) {
        guard let rule = config.rules.first(where: { $0.id == ruleID }) else { return }
        var copy = rule
        copy.id = UUID()
        copy.name = uniqueName(rule.name)
        copy.enabled = false
        config.rules.append(copy)
        persistAndApply()
    }

    func remove(ruleID: UUID) {
        config.rules.removeAll { $0.id == ruleID }
        pendingActions.removeAll { $0.ruleID == ruleID }
        Task { await pipeline.forget(ruleID: ruleID) }
        persistAndApply()
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(config.rules.map(\.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    private func rebuildWatchers() {
        watchers = config.rules
            .filter { $0.enabled && !$0.watchPath.isEmpty }
            .compactMap { rule in
                FSEventsWatcher(path: rule.watchPath) { [weak self] in
                    Task { @MainActor in self?.requestScan() }
                }
            }
    }

    // MARK: - Editing lock

    /// A rule is "being edited" only while the Settings window is open AND the
    /// Rules tab is showing AND that rule is selected. Any of those changing
    /// recomputes the lock; when a rule is freed we kick a scan so it runs
    /// promptly rather than waiting for the next timer tick.
    func setSettingsWindowOpen(_ open: Bool) {
        settingsWindowOpen = open
        recomputeEditing()
    }

    func setRulesTabActive(_ active: Bool) {
        rulesTabActive = active
        recomputeEditing()
    }

    func setSelectedRule(_ id: UUID?) {
        selectedRuleID = id
        recomputeEditing()
    }

    private func recomputeEditing() {
        let newValue = (settingsWindowOpen && rulesTabActive) ? selectedRuleID : nil
        guard newValue != editingRuleID else { return }
        editingRuleID = newValue
        requestScan()
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
            try? await Task.sleep(nanoseconds: 2_000_000_000) // debounce a burst
            await self?.runScans()
        }
    }

    private func runScans() async {
        defer { scanRunning = false }
        while scanRequested {
            scanRequested = false
            guard !paused else { return }
            let apiKey = Keychain.apiKey() ?? ""
            if config.providerRequiresKey && apiKey.isEmpty { return }

            let snapshot = config
            for rule in snapshot.rules where rule.enabled {
                // Re-read per rule so selecting a rule to edit mid-pass takes
                // effect immediately (rather than one stale execution).
                if rule.id == editingRuleID { continue }
                let result = await pipeline.scan(rule: rule, config: snapshot, apiKey: apiKey)
                ingest(result)
            }
            await pipeline.persist()
            lastScan = Date()
        }
    }

    private func ingest(_ result: ScanResult) {
        usage = usage + result.usage
        for plan in result.pending where !pendingActions.contains(where: { $0.source == plan.source && $0.ruleID == plan.ruleID }) {
            pendingActions.append(plan)
        }
        if !result.entries.isEmpty {
            activity.insert(contentsOf: result.entries.reversed(), at: 0)
            activity = Array(activity.prefix(80))
            result.entries.forEach { ConfigStore.appendLog($0.message) }
            notify(result.entries)
        }
    }

    private func notify(_ entries: [ActivityEntry]) {
        guard config.notificationsEnabled else { return }
        let failures = entries.filter { !$0.ok }
        if let failure = failures.first {
            Notifier.post(title: "Sortomat", body: failure.message)
        }
    }

    // MARK: - Preview / apply

    /// Recompute the pending list for every enabled rule (preview button).
    func refreshPreview() async {
        let apiKey = Keychain.apiKey() ?? ""
        if config.providerRequiresKey && apiKey.isEmpty { return }
        let snapshot = config
        for rule in snapshot.rules where rule.enabled {
            let result = await pipeline.scan(
                rule: rule, config: snapshot, apiKey: apiKey, forcePreview: true
            )
            ingest(result)
        }
        lastScan = Date()
    }

    func apply(_ plans: [PlannedAction]) async {
        let rulesByID = Dictionary(uniqueKeysWithValues: config.rules.map { ($0.id, $0) })
        let entries = await pipeline.applyApproved(plans, rules: rulesByID)
        let appliedIDs = Set(plans.map(\.id))
        pendingActions.removeAll { appliedIDs.contains($0.id) }
        if !entries.isEmpty {
            activity.insert(contentsOf: entries.reversed(), at: 0)
            activity = Array(activity.prefix(80))
            entries.forEach { ConfigStore.appendLog($0.message) }
        }
        await pipeline.persist()
    }

    func dismiss(_ plan: PlannedAction) {
        pendingActions.removeAll { $0.id == plan.id }
    }
}
