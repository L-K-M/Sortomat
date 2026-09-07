import Combine
import Foundation
import SwiftUI

/// The shared, observable heart of the GUI: holds the config and activity, owns
/// the folder watchers and the periodic timer, coalesces scans, and runs plans
/// through the Pipeline actor. Kept on the main actor; the heavy lifting hops to
/// the Pipeline.
@MainActor
final class AppState: ObservableObject {
    @Published var config: Config {
        // Two writable copies of one switch drift the moment anything writes
        // the config side — a settings toggle bound straight to it, a config
        // import, a restore. The guard in `paused.didSet` stops the loop.
        didSet { if config.paused != paused { paused = config.paused } }
    }
    /// The emergency brake. Written through to the config so it survives a
    /// relaunch — including the relaunch the update checker offers.
    @Published var paused: Bool {
        didSet {
            guard paused != config.paused else { return }
            config.paused = paused
            persistAndApply()
            if !paused { requestScan() }
        }
    }
    /// Why passes are being held right now, in the user's words, or nil when
    /// they aren't. A brake nobody can see is indistinguishable from a bug.
    @Published private(set) var holdReason: String?
    @Published var activity: [ActivityEntry] = []
    @Published var pendingActions: [PlannedAction] = []
    @Published var lastScan: Date?
    @Published var apiKeyMissing: Bool
    @Published var usage = TokenUsage()
    /// The rule currently open in the editor. It is not executed while being
    /// edited, so a half-typed rule can't fire mid-edit. The main window sets
    /// it from its sidebar selection and clears it when it closes, so there is
    /// one place that decides rather than three booleans to keep in agreement.
    @Published private(set) var editingRuleID: UUID?

    private let pipeline = Pipeline()
    private var watchers: [String: FSEventsWatcher] = [:]
    private var persistTask: Task<Void, Never>?
    private var scanRequested = false
    private var scanRunning = false
    private var timerTask: Task<Void, Never>?
    private var followUpScheduled = false
    /// Exclusive claim on the config directory for this process's lifetime.
    /// nil means another Sortomat process (usually a headless run) holds it;
    /// the GUI keeps working — the window is brief and the CLI side refuses
    /// to start while the GUI holds the lock — but the overlap is logged.
    private let processLock = ProcessLock.acquire()
    /// Rules whose missing watch folder was already announced — one alert per
    /// outage, not one per pass. Reset when the folder reappears.
    private var missingWatchNotified: Set<UUID> = []
    /// Each rule reduced to its decision-relevant fields, as last applied —
    /// compared on save to invalidate previews of rules whose behavior changed.
    private var decisionSignatures: [UUID: Rule] = [:]

    /// The month `usage` belongs to; when it rolls over mid-run the counter
    /// restarts instead of billing January's tokens to February.
    private var spendMonth = SpendStore.monthKey()

    init() {
        let loaded = ConfigStore.load()
        config = loaded
        paused = loaded.paused
        apiKeyMissing = (Keychain.apiKey() ?? "").isEmpty && loaded.providerRequiresKey
        if processLock == nil {
            ConfigStore.appendLog(L10n.t("process.lockWarning"))
        }
        decisionSignatures = Self.signatures(of: loaded.rules)
        let spend = SpendStore.load()
        spendMonth = spend.month
        usage = spend.usage
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
        Self.money(estimatedSpend, code: config.currencyCode)
    }

    /// Four decimals because a single classification costs fractions of a cent,
    /// and a meter that reads "0.00" for the first two hundred files teaches
    /// the user that it doesn't work.
    nonisolated static func money(_ amount: Double, code: String,
                                  locale: Locale = .current) -> String {
        moneyFormatter(code: code, locale: locale).string(from: NSNumber(value: amount))
            ?? String(format: "%.4f %@", amount, code)
    }

    /// Locale placement and separators, not a hardcoded leading "$" and a
    /// decimal point, for a German user paying a European provider in EUR.
    /// The locale is a parameter so a test can compare against the same
    /// formatter instead of against ASCII digits: a machine set to `ar_SA`
    /// renders `١٫٢٣٤٥`, and asserting on the literal "2345" would fail there
    /// while the code did exactly the right thing.
    nonisolated static func moneyFormatter(code: String, locale: Locale) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.minimumFractionDigits = 4
        formatter.maximumFractionDigits = 4
        return formatter
    }

    /// Whether an estimated spend is still under a ceiling. 0 = no ceiling.
    /// Pure, so the one comparison that stands between a misbehaving rule and
    /// a real bill can be tested without a running app. (`nonisolated` here and
    /// below: `AppState` is `@MainActor`, which isolates its statics too, and
    /// these touch nothing on the actor.)
    nonisolated static func withinBudget(spend: Double, ceiling: Double) -> Bool {
        ceiling <= 0 || spend < ceiling
    }

    /// `usage` is already scoped to the calendar month — `SpendStore.load`
    /// discards a record from another month and `accumulate` restarts the
    /// counter when the key rolls over — so `estimatedSpend` *is* this month's
    /// spend, and the ceiling lifts by itself on the first of the month.
    ///
    /// The ceiling is a soft one: it is re-read between rules, not between
    /// files, so one rule over a very large folder can overshoot before the
    /// next rule is held. `perScanBudget` is the hard cap on a single burst;
    /// this is the cap on the month.
    var withinMonthlyBudget: Bool {
        Self.withinBudget(spend: estimatedSpend, ceiling: config.monthlyBudget)
    }

    /// Why a pass may not run, given the settings and the machine's state, or
    /// nil when it may. Deliberately separate from `paused`: this one
    /// re-answers itself as the machine changes, so unplugging holds and
    /// plugging back in resumes without anyone touching a switch.
    nonisolated static func hold(for config: Config, lowPower: Bool, onBattery: Bool) -> String? {
        if config.pauseInLowPowerMode, lowPower { return L10n.t("hold.lowPower") }
        if config.onlyOnPower, onBattery { return L10n.t("hold.onBattery") }
        return nil
    }

    func scanHold() -> String? {
        Self.hold(for: config,
                  lowPower: PowerSource.isInLowPowerMode,
                  onBattery: PowerSource.isOnBattery)
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
            await self.invalidateStalePreviews()
        }
    }

    /// A rule whose prompt, paths, pre-rules, taxonomy or thresholds changed
    /// must not keep serving suggestions computed under the old settings —
    /// drop its queued plans and the pipeline's preview memory so the next
    /// refresh re-plans. (Renames, enable/disable, priority and preview-mode
    /// toggles don't affect what a rule *decides*, so they don't invalidate.)
    private func invalidateStalePreviews() async {
        let current = Self.signatures(of: config.rules)
        var changed: [UUID] = []
        for (id, signature) in current where decisionSignatures[id] != signature {
            changed.append(id)
        }
        changed.append(contentsOf: decisionSignatures.keys.filter { current[$0] == nil })
        decisionSignatures = current
        for id in changed {
            pendingActions.removeAll { $0.ruleID == id }
            await pipeline.forgetPreviews(ruleID: id)
        }
    }

    /// Keyed by rule id, tolerating a hand-edited config that repeats one:
    /// `uniqueKeysWithValues` would trap, and this runs at launch and after
    /// every save, so a duplicated JSON block would make the app unlaunchable.
    private static func signatures(of rules: [Rule]) -> [UUID: Rule] {
        Dictionary(rules.map { ($0.id, signature(of: $0)) }, uniquingKeysWith: { first, _ in first })
    }

    /// The rule with everything that does *not* influence its decisions
    /// normalized away.
    private static func signature(of rule: Rule) -> Rule {
        var s = rule
        s.name = ""
        s.enabled = true
        s.priority = 0
        s.dryRun = false
        return s
    }

    /// Store the key and report whether the Keychain actually accepted it —
    /// Keychain.set has returned this since #8, but nothing read it, so the
    /// UI could still claim "Saved" after a failed write.
    @discardableResult
    func saveAPIKey(_ key: String) -> Bool {
        let accepted = Keychain.set(
            key.trimmingCharacters(in: .whitespacesAndNewlines),
            account: Keychain.apiKeyAccount
        )
        apiKeyMissing = (Keychain.apiKey() ?? "").isEmpty && config.providerRequiresKey
        if accepted { requestScan() }
        return accepted
    }

    /// Returns the new rule's id, like `importRule` does. Reading it back as
    /// `config.rules.last` assumes an append that nothing enforces: the day
    /// this inserts or sorts instead, the editor would open a *different*
    /// existing rule while the user believed they were configuring the new one.
    @discardableResult
    func addRule(from template: RuleTemplate) -> UUID {
        var rule = template.makeRule()
        rule.name = uniqueName(rule.name)
        config.rules.append(rule)
        persistAndApply()
        return rule.id
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
        Task {
            await pipeline.forget(ruleID: ruleID)
            await pipeline.forgetPreviews(ruleID: ruleID)
        }
        persistAndApply()
    }

    /// Add an imported rule (already normalized to disabled + preview by the
    /// pack) under a unique name; returns its id so the UI can select it.
    @discardableResult
    func importRule(_ rule: Rule) -> UUID {
        var imported = rule
        // A pack exported from *this* config still carries its original id, so
        // re-importing it would put two rules with one id in config.json —
        // which every id-keyed dictionary in the app then has to survive.
        imported.id = UUID()
        imported.name = uniqueName(imported.name)
        config.rules.append(imported)
        persistAndApply()
        return imported.id
    }

    private func uniqueName(_ base: String) -> String {
        let names = Set(config.rules.map(\.name))
        guard names.contains(base) else { return base }
        var index = 2
        while names.contains("\(base) \(index)") { index += 1 }
        return "\(base) \(index)"
    }

    /// Diff the wanted set against live watchers: only paths that appeared or
    /// disappeared change anything. (Previously every debounced config save —
    /// i.e. every settled keystroke in the rule editor — tore down and
    /// recreated every FSEvents stream.)
    private func rebuildWatchers() {
        let wanted = Set(config.rules
            .filter { $0.enabled && !$0.watchPath.isEmpty }
            .map(\.watchPath))
        for (path, watcher) in watchers where !wanted.contains(path) {
            watcher.stop()
            watchers[path] = nil
        }
        for path in wanted where watchers[path] == nil {
            watchers[path] = FSEventsWatcher(path: path) { [weak self] in
                Task { @MainActor in self?.requestScan() }
            }
        }
    }

    // MARK: - Editing lock

    /// The rule the main window has open, or nil when it shows something else
    /// or isn't on screen at all. Freeing a rule kicks a check so it runs
    /// promptly rather than waiting out the timer.
    func setEditingRule(_ id: UUID?) {
        guard id != editingRuleID else { return }
        editingRuleID = id
        requestScan()
    }

    // MARK: - Scanning

    private func startTimer() {
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                let interval = await MainActor.run { self?.config.scanIntervalSeconds ?? 60 }
                // Clamp before converting: a hand-edited absurd interval must
                // not trap in the UInt64(Double) conversion at launch.
                let seconds = interval.isFinite ? min(max(interval, 10), 86_400) : 60
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
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
            // Re-checked every pass, not once at launch: the answer changes
            // when the user unplugs, and the timer keeps ticking so the hold
            // lifts by itself.
            let hold = scanHold()
            holdReason = hold
            guard hold == nil else { return }
            // No early bail on a missing key: the pipeline runs deterministic
            // pre-rules regardless and defers only the files that need the model.
            let apiKey = Keychain.apiKey() ?? ""

            let snapshot = config
            let batchID = UUID() // one pass = one undoable batch
            var passResults: [ScanResult] = []
            for rule in snapshot.rules.inExecutionOrder() {
                // Re-read per rule so selecting a rule to edit mid-pass takes
                // effect immediately (rather than one stale execution).
                if rule.id == editingRuleID { continue }
                // Re-read per rule so a ceiling reached mid-pass stops the
                // *next* rule rather than only the next pass.
                let result = await pipeline.scan(
                    rule: rule, config: snapshot, apiKey: apiKey, batchID: batchID,
                    modelAllowed: withinMonthlyBudget
                )
                ingest(result)
                passResults.append(result)
            }
            notify(pass: passResults)
            await pipeline.persist()
            pruneStalePending()
            persistSpend()
            lastScan = Date()
        }
    }

    /// Plans whose file has since vanished (filed by hand, deleted, renamed)
    /// could only fail on Apply — drop them so neither the list nor the
    /// menu-bar badge advertises work that no longer exists.
    private func pruneStalePending() {
        pendingActions.removeAll { !FileManager.default.fileExists(atPath: $0.source.path) }
    }

    private func persistSpend() {
        SpendStore(month: spendMonth, input: usage.input, output: usage.output).save()
    }

    private func accumulate(_ resultUsage: TokenUsage) {
        let month = SpendStore.monthKey()
        if month != spendMonth {
            spendMonth = month
            usage = resultUsage
        } else {
            usage = usage + resultUsage
        }
    }

    private func ingest(_ result: ScanResult) {
        accumulate(result.usage)
        // Re-arm the missing-folder alert as soon as the folder is back, even
        // on a pass that produced no entries at all — otherwise a second
        // outage of the same folder would be silent.
        if !result.watchMissing, let id = result.ruleID { missingWatchNotified.remove(id) }
        if result.unstableCount > 0 { scheduleFollowUpScan() }
        for plan in result.pending where !pendingActions.contains(where: { $0.source == plan.source && $0.ruleID == plan.ruleID }) {
            pendingActions.append(plan)
        }
        if !result.entries.isEmpty {
            activity.insert(contentsOf: result.entries.reversed(), at: 0)
            activity = Array(activity.prefix(80))
            result.entries.forEach { ConfigStore.appendLog($0.message) }
        }
    }

    /// A file the stability probe rejected as too young waits for the *next*
    /// pass — which used to mean the periodic timer, up to a minute away, even
    /// though FSEvents had just announced the file. One short follow-up pass
    /// picks it up as soon as it can possibly qualify (>5 s old).
    private func scheduleFollowUpScan() {
        guard !followUpScheduled else { return }
        followUpScheduled = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            guard let self else { return }
            self.followUpScheduled = false
            self.requestScan()
        }
    }

    /// What the notifications toggle promises: one summary of what a *pass*
    /// filed and what failed — not one banner per rule, which is what
    /// notifying from `ingest` produced once more than one rule was active.
    /// A missing watch folder alerts once per outage; the log still records
    /// every pass, and `ingest` re-arms the alert when the folder returns.
    private func notify(pass results: [ScanResult]) {
        guard config.notificationsEnabled else { return }
        let entries = results.flatMap(\.entries)

        let filed = entries.filter { $0.kind == .filed }.count
        if filed > 0 {
            Notifier.post(title: "Sortomat", body: L10n.plural("notify.filed", filed))
        }

        let failures = entries.filter { $0.kind == .failed }
        if let first = failures.first {
            let body = failures.count == 1
                ? first.message
                : L10n.plural("notify.failuresMore", failures.count - 1, first.message)
            Notifier.post(title: "Sortomat", body: body)
        }

        // Outages are their own bucket so a folder that stays missing doesn't
        // re-announce itself on every pass alongside the real failures.
        for result in results where result.watchMissing {
            guard let id = result.ruleID, !missingWatchNotified.contains(id) else { continue }
            missingWatchNotified.insert(id)
            if let entry = result.entries.first(where: { $0.kind == .watchMissing }) {
                Notifier.post(title: "Sortomat", body: entry.message)
            }
        }
    }

    // MARK: - Preview / apply

    /// Recompute the pending list for every enabled rule (preview button).
    func refreshPreview() async {
        let apiKey = Keychain.apiKey() ?? ""
        let snapshot = config
        var passResults: [ScanResult] = []
        for rule in snapshot.rules.inExecutionOrder() {
            let result = await pipeline.scan(
                rule: rule, config: snapshot, apiKey: apiKey, forcePreview: true,
                modelAllowed: withinMonthlyBudget
            )
            ingest(result)
            passResults.append(result)
        }
        notify(pass: passResults)
        pruneStalePending()
        // A preview can spend real tokens; without this the meter only reached
        // disk on the next scan pass or at quit.
        persistSpend()
        lastScan = Date()
    }


    /// Returns the batch this approval journaled, so the caller can undo
    /// exactly it. `undoLastBatch` reverses whatever is newest, and a scheduled
    /// pass — the watcher, the timer — can journal an automatic rule's work
    /// between the Apply and the Undo, making that the newest batch.
    @discardableResult
    func apply(_ plans: [PlannedAction]) async -> UUID {
        let batchID = UUID()
        let rulesByID = Dictionary(config.rules.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = await pipeline.applyApproved(plans, rules: rulesByID, batchID: batchID)
        let appliedIDs = Set(plans.map(\.id))
        pendingActions.removeAll { appliedIDs.contains($0.id) }
        if !entries.isEmpty {
            activity.insert(contentsOf: entries.reversed(), at: 0)
            activity = Array(activity.prefix(80))
            entries.forEach { ConfigStore.appendLog($0.message) }
        }
        await pipeline.persist()
        return batchID
    }

    func dismiss(_ plan: PlannedAction) {
        pendingActions.removeAll { $0.id == plan.id }
    }

    // MARK: - Termination

    /// Called from applicationWillTerminate: write the spend store and give
    /// the pipeline a bounded moment to persist its in-memory ledger records —
    /// paid verdicts from a pass that was still running must not be forgotten
    /// (and re-paid) because the user quit at the wrong moment.
    func flushOnTerminate() {
        // A quit inside the 800 ms persist debounce used to discard the last
        // rule edits (toggle a misbehaving rule off, ⌘Q, and it's back on at
        // next launch). Write the config synchronously here.
        if let persistTask, !persistTask.isCancelled {
            persistTask.cancel()
            ConfigStore.save(config)
        }
        persistSpend()
        // Every pass persists the ledger when it ends, so only a pass that is
        // still running can be holding unwritten records. Blocking the main
        // thread otherwise would just add up to two seconds to every quit.
        guard scanRunning else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached { [pipeline] in
            await pipeline.persist()
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    // MARK: - Undo

    /// Undo one *named* batch — the one an Apply just wrote, rather than
    /// whichever is newest by the time the user clicks.
    @discardableResult
    func undo(batch id: UUID) async -> (undone: Int, failed: Int) {
        let entries = await Task.detached { Journal.recent(limit: .max) }.value
        return await reverse(entries.filter { $0.batchID == id })
    }

    /// Undo a journaled placement *and* pin the restored file as skipped in
    /// the ledger, so the rule doesn't immediately re-classify and re-move it
    /// (the undo ping-pong). The undo itself runs off the main actor: for a
    /// copy it hashes the full content of both sides, which must not stall
    /// the UI on a large file.
    func undo(_ entry: JournalEntry) async throws {
        try await undo(entry, persisting: true)
    }

    private func undo(_ entry: JournalEntry, persisting: Bool) async throws {
        try await Task.detached { try Journal.undo(entry) }.value
        guard !entry.wasCopy else { return } // nothing returned to the watch folder
        await pipeline.markUndone(ruleID: entry.ruleID, sourcePath: entry.sourcePath)
        if persisting { await pipeline.persist() }
    }

    /// Undo the newest batch — one scan pass or one approved preview. Returns
    /// how many entries were reversed and how many refused.
    func undoLastBatch() async -> (undone: Int, failed: Int) {
        // The whole journal, not a 500-entry window: one pass over a big
        // folder can exceed it, and `lastBatch` would then reverse part of the
        // batch while reporting the whole thing undone.
        let entries = await Task.detached { Journal.recent(limit: .max) }.value
        return await reverse(Journal.lastBatch(in: entries))
    }

    private func reverse(_ entries: [JournalEntry]) async -> (undone: Int, failed: Int) {
        var undone = 0, failed = 0
        for entry in entries {
            do {
                try await undo(entry, persisting: false)
                undone += 1
            } catch {
                failed += 1
            }
        }
        await pipeline.persist() // once for the batch, not once per entry
        return (undone, failed)
    }
}
