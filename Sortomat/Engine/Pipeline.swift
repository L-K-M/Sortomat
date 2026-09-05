import Foundation

/// Serializes and coordinates all file processing. Owns the persistent ledger,
/// enforces the per-scan model-call budget, and keeps the *decision* (plan)
/// separate from the *execution* (apply) so automatic sorting and the dry-run
/// preview run through exactly the same logic.
actor Pipeline {
    private static let partialExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "tmp", "!ut", "opdownload",
    ]

    private let ledger: Ledger
    /// Content-addressed decisions: identical bytes under the same rule never
    /// pay for a second classification.
    private let memo: DecisionMemo
    /// Files currently being planned/applied — guards against the same file being
    /// picked up twice by overlapping scans within this process.
    private var inFlight: Set<String> = []
    /// dry-run rules: (ruleID|fingerprint) already surfaced for review this
    /// session, so we don't re-classify (and re-pay) them every interval.
    private var previewed: Set<String> = []

    init(ledger: Ledger = Ledger(), memo: DecisionMemo = DecisionMemo()) {
        self.ledger = ledger
        self.memo = memo
    }

    func ledgerCount() -> Int { ledger.count }
    func persist() {
        ledger.prune()
        ledger.save()
        memo.save()
    }
    func forget(ruleID: UUID) {
        ledger.forget(ruleID: ruleID)
        memo.forget(ruleID: ruleID)
    }

    /// Drop the in-session preview memory for one rule (or for all rules when
    /// `ruleID` is nil) — a rule whose behavior just changed must re-plan its
    /// files instead of serving suggestions computed under the old settings.
    func forgetPreviews(ruleID: UUID? = nil) {
        guard let ruleID else {
            previewed.removeAll()
            memo.removeAll()
            return
        }
        // `decide` consults the memo *before* the model, so dropping only the
        // preview set would let the very next scan serve the verdict recorded
        // under the old prompt/taxonomy — for free, and therefore forever.
        previewed = previewed.filter { !$0.hasPrefix(ledger.keyPrefix(ruleID: ruleID)) }
        memo.forget(ruleID: ruleID)
    }

    #if DEBUG
    /// Record a verdict in the decision memo. Only used by tests: the memo is
    /// private to `decide`, and a test that has to reach through a real model
    /// call to fill it would be testing the network, not the persistence.
    func rememberForTesting(ruleID: UUID, model: String, ext: String, digest: String,
                            action: String, relativePath: String?) {
        memo.record(ruleID: ruleID, model: model, ext: ext, digest: digest, action: action,
                    relativePath: relativePath, reason: nil, confidence: nil)
    }
    #endif

    /// After an undo restores a file into a watched folder, remember it as
    /// skipped for the rule that moved it — otherwise the very next scan
    /// re-classifies (re-pays for) the file and moves it right back,
    /// structurally defeating undo.
    func markUndone(ruleID: UUID, sourcePath: String) {
        let fingerprint = Ledger.fingerprint(URL(fileURLWithPath: sourcePath))
        ledger.record(ruleID: ruleID, fingerprint: fingerprint, status: .skipped)
    }

    // MARK: - Scanning

    /// Scan one rule. `forcePreview` makes even a non-dry-run rule only plan
    /// (used by the preview window). `batchID` groups every journaled move of
    /// one pass so it can be undone together. Returns entries + plans + usage.
    func scan(rule: Rule, config: Config, apiKey: String, forcePreview: Bool = false,
              batchID: UUID = UUID()) async -> ScanResult {
        guard rule.enabled else { return ScanResult() }
        let watch = URL(fileURLWithPath: (rule.watchPath as NSString).expandingTildeInPath)
        let target = URL(fileURLWithPath: (rule.targetPath as NSString).expandingTildeInPath)
        guard !rule.watchPath.isEmpty, !rule.targetPath.isEmpty else { return ScanResult() }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: watch.path, isDirectory: &isDir),
              isDir.boolValue else {
            return ScanResult(entries: [
                ActivityEntry(ok: false,
                              message: L10n.t("activity.missingWatch", rule.name, watch.path),
                              kind: .watchMissing)
            ], ruleID: rule.id, watchMissing: true)
        }

        let previewing = forcePreview || rule.dryRun
        // Without a key (when the provider needs one), deterministic pre-rules
        // still run — free, predictable sorting isn't held hostage by the key
        // field. Only files that would need the model are deferred.
        let llmAvailable = !(config.providerRequiresKey && apiKey.isEmpty)
        let candidates = candidateFiles(in: watch, target: target, rule: rule)

        var budgetRemaining = config.perScanBudget > 0 ? config.perScanBudget : Int.max
        var result = ScanResult()
        result.ruleID = rule.id

        // Bounded concurrency: cap the number of in-flight `process` calls. Each
        // one runs on this actor and only suspends at the network await, so shared
        // state stays race-free while several classifications overlap.
        let cap = max(1, min(config.maxConcurrentClassifications, 8))
        var index = 0
        var budgetHit = false
        var keyDeferred = 0

        while index < candidates.count {
            let batch = candidates[index..<min(index + cap, candidates.count)]
            index += cap
            // Budget correctness without serialization: batches keep their full
            // width, but at most `budgetRemaining` members may call the model —
            // the rest run pre-rules only and defer if they'd need the LLM.
            // (Shrinking the whole batch to the remaining budget — the previous
            // approach — processed large backlogs one file at a time once the
            // budget ran low, stability probe and all.)
            // Slots are granted by position: a file resolved by a pre-rule, by
            // the memo, or rejected by the stability probe still consumes one
            // even though it never calls the model. That only ever *under*-uses
            // the budget, and the file is retried on the next pass.
            var llmSlots = llmAvailable ? budgetRemaining : 0
            var outcomes: [FileOutcome] = []
            await withTaskGroup(of: FileOutcome?.self) { group in
                for file in batch {
                    let allowLLM = llmSlots > 0
                    if allowLLM { llmSlots -= 1 }
                    group.addTask { [self] in
                        await process(file: file, rule: rule, target: target, config: config,
                                      apiKey: apiKey, previewing: previewing, allowLLM: allowLLM,
                                      batchID: batchID)
                    }
                }
                for await outcome in group {
                    if let outcome { outcomes.append(outcome) }
                }
            }
            for outcome in outcomes {
                if outcome.usedLLM { budgetRemaining -= 1 }
                if outcome.unstable { result.unstableCount += 1 }
                if outcome.budgetDeferred {
                    if llmAvailable { budgetHit = true } else { keyDeferred += 1 }
                }
                if let entry = outcome.entry { result.entries.append(entry) }
                if let plan = outcome.pending { result.pending.append(plan) }
                result.usage = result.usage + outcome.usage
            }
            if llmAvailable, budgetRemaining <= 0, index < candidates.count {
                budgetHit = true
                break
            }
        }

        if budgetHit {
            result.entries.append(ActivityEntry(
                ok: true,
                message: L10n.t("activity.budgetReached", rule.name, config.perScanBudget)
            ))
        }
        if keyDeferred > 0 {
            result.entries.append(ActivityEntry(
                ok: true,
                message: L10n.plural("activity.keyDeferred", keyDeferred, rule.name)
            ))
        }
        return result
    }

    private struct FileOutcome {
        var entry: ActivityEntry?
        var pending: PlannedAction?
        var usage = TokenUsage()
        var usedLLM = false
        var budgetDeferred = false
        /// Rejected by the stability probe — a follow-up pass should retry soon.
        var unstable = false
    }

    // MARK: - Per-file processing

    private func process(
        file: URL, rule: Rule, target: URL, config: Config,
        apiKey: String, previewing: Bool, allowLLM: Bool, batchID: UUID
    ) async -> FileOutcome? {
        let fingerprint = Ledger.fingerprint(file)
        let ledgerKey = ledger.key(ruleID: rule.id, fingerprint: fingerprint)

        // Skip files this rule has already accounted for (persisted across launches).
        guard ledger.shouldProcess(ruleID: rule.id, fingerprint: fingerprint) else { return nil }
        if previewing, previewed.contains(ledgerKey) { return nil }
        // Reserve so overlapping scans don't double-handle the same file.
        guard !inFlight.contains(ledgerKey) else { return nil }
        inFlight.insert(ledgerKey)
        defer { inFlight.remove(ledgerKey) }

        guard await isStable(file) else {
            var outcome = FileOutcome()
            outcome.unstable = true
            return outcome
        }

        var outcome = FileOutcome()
        do {
            let decision = try await decide(
                file: file, rule: rule, target: target, config: config,
                apiKey: apiKey, allowLLM: allowLLM
            )
            outcome.usage = decision.usage
            outcome.usedLLM = decision.usedLLM
            guard var plan = decision.plan else {
                outcome.budgetDeferred = true
                return outcome
            }
            // Stamp what the decision was *about*, so apply can refuse if the
            // file changes between preview and approval.
            plan.fingerprint = fingerprint

            if previewing {
                // Surface for review; remember so we don't re-classify next interval.
                previewed.insert(ledgerKey)
                outcome.pending = plan
                outcome.entry = ActivityEntry(ok: true, message: previewMessage(plan, target: target, rule: rule))
                return outcome
            }

            outcome.entry = apply(plan: plan, rule: rule, fingerprint: fingerprint,
                                  target: target, batchID: batchID)
            return outcome
        } catch {
            ledger.record(ruleID: rule.id, fingerprint: fingerprint, status: .failed)
            // A request that reached the model and failed (HTTP error, bad
            // body, network) still counts against the per-check budget —
            // otherwise a backlog against a rate-limited endpoint fires one
            // paid request per file with no cap at all.
            if error is LLMError || error is URLError { outcome.usedLLM = true }
            outcome.entry = ActivityEntry(
                ok: false,
                message: L10n.t("activity.error", rule.name, file.lastPathComponent, error.localizedDescription)
            )
            return outcome
        }
    }

    /// Content hashing is the one piece of per-file work that never suspends,
    /// so running it inline would block the whole actor — and with it every
    /// other file in the pass — for as long as the read takes.
    private static func digestOffActor(_ file: URL) async -> String? {
        await Task.detached(priority: .utility) { DecisionMemo.digest(of: file) }.value
    }

    private struct DecideResult {
        var plan: PlannedAction?   // nil only when the budget is exhausted
        var usage = TokenUsage()
        var usedLLM = false
    }

    /// The pure decision: pre-rules → decision memo → (optional) model →
    /// taxonomy/confidence routing → a `PlannedAction`.
    private func decide(
        file: URL, rule: Rule, target: URL, config: Config,
        apiKey: String, allowLLM: Bool
    ) async throws -> DecideResult {
        let ext = file.pathExtension

        // 1. The rule's steps. Evaluation is pure: everything it can know
        //    arrives through `FileFacts`, which loads each cost tier at most
        //    once and only when a condition actually asks.
        let context = evaluationContext(file: file, rule: rule, target: target, allowModel: allowLLM)
        var resumeToken: ResumeToken?
        switch RuleEvaluator.evaluate(context) {
        case .decided(let placement, let trace):
            return try Self.plan(from: placement, trace: trace, file: file,
                                 rule: rule, target: target, ext: ext)
        case .deferred:
            // The model is needed and unavailable (no key, no budget). The
            // caller reports the deferral; nothing is decided.
            return DecideResult(plan: nil)
        case .needsModel(_, let token, _):
            resumeToken = token
        }

        // 2. Content-addressed memo: identical bytes under this rule get the
        //    identical decision — no network, no cost, no budget, no key.
        var digest: String?
        if !memo.isEmpty {
            digest = await Self.digestOffActor(file)
            if let digest,
               let hit = memo.lookup(ruleID: rule.id, model: config.model, ext: ext, digest: digest) {
                let remembered = Classification(
                    action: hit.action,
                    relativePath: hit.relativePath,
                    reason: hit.reason.map { L10n.t("memo.remembered", $0) }
                        ?? L10n.t("memo.rememberedBare"),
                    confidence: hit.confidence
                )
                return try route(remembered, file: file, rule: rule, target: target,
                                 ext: ext, usage: TokenUsage(), usedLLM: false)
            }
        }

        // 3. Budget.
        guard allowLLM else { return DecideResult(plan: nil) }

        // 4. Classify.
        guard let base = URL(string: config.apiBase) else { throw LLMError.badBaseURL }
        let client = LLMClient(apiKey: apiKey, model: config.model, baseURL: base)
        // Extraction can be real work now (OCR, office documents): run it off
        // the actor so other files keep flowing while one is being read.
        let privacyMode = rule.privacyMode
        let description = await Task.detached(priority: .utility) {
            FileContext.describe(url: file, privacyMode: privacyMode)
        }.value
        let result = try await client.classify(
            rulePrompt: rule.prompt, taxonomy: rule.taxonomy, fileDescription: description
        )
        let c = result.classification
        var decided = try route(c, file: file, rule: rule, target: target,
                                ext: ext, usage: result.usage, usedLLM: true)
        // The model is a *binding* action: its answer fills {model.*} and the
        // actions after it decide what to do with them. A rule whose askModel
        // is the last action behaves exactly as before.
        if let resumeToken, let resumed = try resumedPlan(
            resumeToken, classification: c, decided: decided, file: file,
            rule: rule, target: target, ext: ext, usage: result.usage, allowModel: allowLLM
        ) {
            decided = resumed
        }

        // Remember the verdict for these exact bytes — a re-download or a
        // renamed copy never pays again. Only answers that routed cleanly are
        // memoized: a malformed answer should get a fresh model call on retry.
        if digest == nil { digest = await Self.digestOffActor(file) }
        if let digest {
            memo.record(ruleID: rule.id, model: config.model, ext: ext, digest: digest, action: c.action,
                        relativePath: c.resolvedRelativePath(),
                        reason: c.reason, confidence: c.confidence)
        }
        return decided
    }

    /// What a rule *would* do with a file, with nothing written down: no
    /// ledger entry, no memo, no journal, no in-flight marking, and — unless
    /// asked — no model call and therefore no cost.
    ///
    /// This is the whole reason the evaluator is pure. Until now the only way
    /// to find out whether a rule matched anything was to enable it and watch.
    struct DryRun: Equatable, Sendable {
        var operation: Placement.Operation
        /// Relative to the rule's target folder, already rendered.
        var destination: String?
        var summary: String
        var needsModel: Bool
    }

    func dryDecide(file: URL, rule: Rule, allowModel: Bool = false) -> DryRun {
        let target = URL(fileURLWithPath: (rule.targetPath as NSString).expandingTildeInPath)
        let context = evaluationContext(file: file, rule: rule, target: target,
                                        allowModel: allowModel)
        switch RuleEvaluator.evaluate(context) {
        case .decided(let placement, let trace):
            return DryRun(
                operation: placement.operation,
                destination: placement.relativePath?.string(),
                summary: trace.summary,
                needsModel: false
            )
        case .needsModel(_, _, let trace), .deferred(let trace):
            return DryRun(operation: .skip, destination: nil,
                          summary: trace.summary, needsModel: true)
        }
    }

    /// How many of a rule's own watched files its steps claim right now,
    /// deterministically and without spending anything. Capped, because the
    /// answer is a reassurance, not a report.
    func matchCount(rule: Rule, limit: Int = 500) -> (matched: Int, scanned: Int, needsModel: Int) {
        let watch = URL(fileURLWithPath: (rule.watchPath as NSString).expandingTildeInPath)
        let target = URL(fileURLWithPath: (rule.targetPath as NSString).expandingTildeInPath)
        let candidates = candidateFiles(in: watch, target: target, rule: rule).prefix(limit)
        var matched = 0
        var needsModel = 0
        for file in candidates {
            let run = dryDecide(file: file, rule: rule)
            if run.needsModel { needsModel += 1 }
            else if run.operation != .skip { matched += 1 }
        }
        return (matched, candidates.count, needsModel)
    }

    /// The evaluation context for one file: the rule, the facts, and whether
    /// the model may be consulted at all right now.
    private func evaluationContext(file: URL, rule: Rule, target: URL,
                                   allowModel: Bool) -> RuleEvaluator.Context {
        let watchRoot = URL(fileURLWithPath: (rule.watchPath as NSString).expandingTildeInPath)
        // The target index is only built for a rule that actually asks "is
        // this already filed?" — otherwise every scan would enumerate the
        // target folder for nothing.
        let index = Self.mentions(.duplicateInTarget, in: rule) ? TargetIndex(root: target) : nil
        let source = LiveFactSource(url: file, targetPath: target.path, targetIndex: index)
        let facts = FileFacts(
            url: file, watchRoot: watchRoot, source: source,
            contentPolicy: rule.privacyMode == .metadataOnly ? .blocked : .allowed
        )
        return RuleEvaluator.Context(rule: rule, facts: facts, allowModel: allowModel)
    }

    static func mentions(_ attribute: Attribute, in rule: Rule) -> Bool {
        func walk(_ group: ConditionGroup) -> Bool {
            group.items.contains { item in
                switch item {
                case .test(let test): return test.attribute == attribute
                case .group(let nested): return walk(nested)
                }
            }
        }
        return rule.steps.contains { walk($0.when) }
    }

    /// A `Placement` becomes a `PlannedAction`. `Sanitizer` still builds and
    /// confines every path; the engine only ever says what and where.
    private static func plan(from placement: Placement, trace: RuleTrace, file: URL,
                             rule: Rule, target: URL, ext: String,
                             usage: TokenUsage = TokenUsage(),
                             usedLLM: Bool = false) throws -> DecideResult {
        let reason = placement.reason.isEmpty ? trace.summary : placement.reason
        func skipPlan() -> DecideResult {
            DecideResult(plan: PlannedAction(
                ruleID: rule.id, ruleName: rule.name, source: file, kind: .skip,
                destination: nil, origin: placement.origin, reason: reason,
                confidence: placement.confidence, copyInsteadOfMove: rule.copyInsteadOfMove
            ), usage: usage, usedLLM: usedLLM)
        }
        guard placement.operation != .skip, let rendered = placement.relativePath else {
            return skipPlan()
        }
        let relative = rendered.string()
        guard !relative.trimmingCharacters(in: .whitespaces).isEmpty else { return skipPlan() }

        let root = placement.rootPath.map { URL(fileURLWithPath: $0) } ?? target
        let destination = try Sanitizer.destination(
            target: root, relativePath: relative, originalExtension: ext
        )
        let kind: PlannedAction.Kind
        switch placement.operation {
        case .copy: kind = .copy
        case .quarantine: kind = .quarantine
        case .move, .rename, .trash: kind = .move
        case .skip: kind = .skip
        }
        return DecideResult(plan: PlannedAction(
            ruleID: rule.id, ruleName: rule.name, source: file, kind: kind,
            destination: destination, origin: placement.origin, reason: reason,
            confidence: placement.confidence,
            copyInsteadOfMove: placement.operation == .copy
        ), usage: usage, usedLLM: usedLLM)
    }

    /// Hand the model's answer back to the engine so the actions after
    /// `askModel` can use it. Returns nil when the answer produced no
    /// placement (a skip, or a valve that already decided), in which case the
    /// existing routing result stands.
    private func resumedPlan(_ token: ResumeToken, classification: Classification,
                             decided: DecideResult, file: URL, rule: Rule, target: URL,
                             ext: String, usage: TokenUsage,
                             allowModel: Bool) throws -> DecideResult? {
        guard let plan = decided.plan, plan.kind != .skip, !rule.steps.isEmpty else { return nil }
        let routing = try Self.routing(for: classification, rule: rule,
                                       fileName: file.lastPathComponent)
        guard let relativePath = routing.relativePath else { return nil }
        let answer = ModelAnswer(
            relativePath: relativePath,
            reason: routing.reason,
            confidence: classification.confidence,
            quarantined: routing.origin == .confidence || routing.origin == .taxonomy
        )
        let context = evaluationContext(file: file, rule: rule, target: target,
                                        allowModel: allowModel)
        guard case .decided(let placement, let trace) = RuleEvaluator.resume(
            token, answer: answer, context: context
        ) else { return nil }
        return try Self.plan(from: placement, trace: trace, file: file, rule: rule,
                             target: target, ext: ext, usage: usage, usedLLM: true)
    }

    /// The routing shared by a fresh model answer and a memo hit: skip
    /// handling, taxonomy enforcement, confidence quarantine, destination
    /// building. Re-running these steps on memo hits means a changed
    /// taxonomy, threshold or quarantine folder applies to remembered
    /// verdicts too.
    private func route(
        _ c: Classification, file: URL, rule: Rule, target: URL, ext: String,
        usage: TokenUsage, usedLLM: Bool
    ) throws -> DecideResult {
        let routing = try Self.routing(for: c, rule: rule, fileName: file.lastPathComponent)
        guard let relativePath = routing.relativePath else {
            return DecideResult(plan: PlannedAction(
                ruleID: rule.id, ruleName: rule.name, source: file, kind: .skip,
                destination: nil, origin: .model,
                reason: L10n.t("activity.skipped", rule.name, file.lastPathComponent, routing.reason),
                confidence: c.confidence, copyInsteadOfMove: rule.copyInsteadOfMove
            ), usage: usage, usedLLM: usedLLM)
        }
        let dest = try Sanitizer.destination(target: target, relativePath: relativePath, originalExtension: ext)
        return DecideResult(plan: PlannedAction(
            ruleID: rule.id, ruleName: rule.name, source: file, kind: routing.kind,
            destination: dest, origin: routing.origin, reason: routing.reason,
            confidence: c.confidence, copyInsteadOfMove: rule.copyInsteadOfMove
        ), usage: usage, usedLLM: usedLLM)
    }

    /// The safety valves applied to a model answer, as pure data so they can
    /// be unit-tested without a pipeline: skip handling, taxonomy enforcement
    /// and the confidence quarantine.
    struct Routing: Equatable {
        /// nil means skip.
        var relativePath: String?
        var kind: PlannedAction.Kind
        var origin: PlannedAction.Origin
        var reason: String
    }

    static func routing(for c: Classification, rule: Rule, fileName: String) throws -> Routing {
        guard c.isMove else {
            return Routing(relativePath: nil, kind: .skip, origin: .model,
                           reason: c.reason ?? L10n.t("reason.ruleDoesNotApply"))
        }
        guard let relative = c.resolvedRelativePath() else {
            throw LLMError.badResponse(L10n.t("error.missingPath"))
        }

        var origin: PlannedAction.Origin = .model
        var quarantine = false
        var reason = c.reason ?? ""

        // Taxonomy is checked against the path that will actually be applied
        // — not the `folder` field on its own, which a contradictory (or
        // prompt-injected) answer could set to an allowed name while
        // `relative_path` points elsewhere.
        if !rule.taxonomy.isEmpty {
            let top = Classification.topFolder(ofRelativePath: relative) ?? ""
            let allowed = rule.taxonomy.contains { $0.caseInsensitiveCompare(top) == .orderedSame }
            if !allowed {
                quarantine = true
                origin = .taxonomy
                reason = L10n.t("reason.notInTaxonomy", top)
            }
        }

        // Confidence threshold → quarantine low-confidence decisions. A
        // missing or unparseable confidence is *low*, not trusted: the
        // off-schema answers deserve the most suspicion, not the least.
        if !quarantine, rule.confidenceThreshold > 0 {
            if let confidence = c.confidence {
                if confidence < rule.confidenceThreshold {
                    quarantine = true
                    origin = .confidence
                    reason = L10n.t("reason.lowConfidence", Int((confidence * 100).rounded()))
                }
            } else {
                quarantine = true
                origin = .confidence
                reason = L10n.t("reason.noConfidence")
            }
        }

        if quarantine {
            // An emptied quarantine folder means "the target itself", not the
            // absolute "/name" the old string interpolation produced.
            let folder = rule.quarantineSubfolder.trimmingCharacters(in: .whitespaces)
            let path = folder.isEmpty ? fileName : "\(folder)/\(fileName)"
            return Routing(relativePath: path, kind: .quarantine, origin: origin, reason: reason)
        }
        return Routing(relativePath: relative, kind: rule.copyInsteadOfMove ? .copy : .move,
                       origin: origin, reason: reason)
    }

    // MARK: - Apply

    /// Execute a plan the caller already computed (auto-sort or approved preview).
    func apply(plan: PlannedAction, rule: Rule, fingerprint: String, target: URL,
               batchID: UUID = UUID()) -> ActivityEntry {
        let name = plan.source.lastPathComponent
        switch plan.kind {
        case .skip:
            ledger.record(ruleID: plan.ruleID, fingerprint: fingerprint, status: .skipped)
            return ActivityEntry(ok: true, message: plan.reason)
        case .duplicate:
            ledger.record(ruleID: plan.ruleID, fingerprint: fingerprint, status: .done)
            return ActivityEntry(ok: true, message: plan.reason)
        case .move, .copy, .quarantine:
            guard let destination = plan.destination else {
                return ActivityEntry(ok: false, message: L10n.t("error.missingPath"))
            }
            // The plan was computed for a specific file state; if the content
            // changed since (edited, replaced, re-downloaded), executing the
            // stale suggestion would file the *new* file under the *old*
            // decision. Leave it for the next scan to re-decide instead.
            if let expected = plan.fingerprint, expected != fingerprint {
                return ActivityEntry(
                    ok: false,
                    message: L10n.t("activity.stalePlan", rule.name, name)
                )
            }
            do {
                let outcome = try Mover.place(
                    source: plan.source, destination: destination, copy: plan.copyInsteadOfMove
                )
                switch outcome {
                case .placed(let url):
                    if plan.copyInsteadOfMove {
                        ledger.record(ruleID: plan.ruleID, fingerprint: fingerprint, status: .done)
                    }
                    Journal.record(JournalEntry(
                        ruleID: plan.ruleID, ruleName: plan.ruleName,
                        sourcePath: plan.source.path, destinationPath: url.path,
                        wasCopy: plan.copyInsteadOfMove, reason: plan.reason,
                        batchID: batchID, destinationStamp: Journal.stamp(of: url)
                    ))
                    return ActivityEntry(ok: true,
                                         message: filedMessage(plan, finalURL: url, target: target, name: name),
                                         kind: .filed)
                case .duplicate(let url):
                    ledger.record(ruleID: plan.ruleID, fingerprint: fingerprint, status: .done)
                    return ActivityEntry(ok: true, message: L10n.t("activity.duplicate", rule.name, name, url.lastPathComponent))
                }
            } catch {
                ledger.record(ruleID: plan.ruleID, fingerprint: fingerprint, status: .failed)
                return ActivityEntry(ok: false, message: L10n.t("activity.error", rule.name, name, error.localizedDescription))
            }
        }
    }

    /// Apply a batch of pre-computed plans (used when the user approves a preview).
    func applyApproved(_ plans: [PlannedAction], rules: [UUID: Rule]) -> [ActivityEntry] {
        let batchID = UUID() // one approval = one undoable batch
        return plans.compactMap { plan in
            guard let rule = rules[plan.ruleID] else { return nil }
            let target = URL(fileURLWithPath: (rule.targetPath as NSString).expandingTildeInPath)
            let fingerprint = Ledger.fingerprint(plan.source)
            return apply(plan: plan, rule: rule, fingerprint: fingerprint, target: target,
                         batchID: batchID)
        }
    }

    // MARK: - Messages

    private func filedMessage(_ plan: PlannedAction, finalURL: URL, target: URL, name: String) -> String {
        let relDest = plan.relativeDestinationOverride(finalURL: finalURL, target: target)
        if plan.origin == .taxonomy || plan.origin == .confidence {
            return L10n.t("activity.quarantined", plan.ruleName, name, relDest, plan.reason)
        }
        if plan.copyInsteadOfMove {
            return L10n.t("activity.copied", plan.ruleName, name, relDest)
        }
        return L10n.t("activity.moved", plan.ruleName, name, relDest)
    }

    private func previewMessage(_ plan: PlannedAction, target: URL, rule: Rule) -> String {
        let name = plan.source.lastPathComponent
        switch plan.kind {
        case .skip:
            return L10n.t("activity.wouldSkip", rule.name, name, plan.reason)
        default:
            return L10n.t("activity.wouldMove", rule.name, name, plan.relativeDestination(to: target))
        }
    }

    // MARK: - Candidate discovery & stability

    /// Document packages that Launch Services may not know on a Mac without
    /// the app that owns them — a Pages document must sort like a file even
    /// where Pages isn't installed.
    static let packageExtensions: Set<String> = [
        "pages", "numbers", "key", "rtfd", "textbundle", "sketch", "band", "bundle", "app",
    ]

    /// A regular file, or a package: a Pages/Numbers/Keynote document, an
    /// RTFD, a text bundle. Packages are folders on disk, so they used to be
    /// invisible to every rule ("document" kind included) — Hazel treats
    /// them as files, and so does Finder.
    static func isFileLike(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isPackageKey, .isDirectoryKey])
        else { return false }
        if values.isRegularFile == true { return true }
        guard values.isDirectory == true else { return false }
        return values.isPackage == true || packageExtensions.contains(url.pathExtension.lowercased())
    }

    private func candidateFiles(in watch: URL, target: URL, rule: Rule) -> [URL] {
        let fm = FileManager.default
        let targetPath = target.standardizedFileURL.path
        let keys: [URLResourceKey] = [.isRegularFileKey, .isPackageKey, .isDirectoryKey]

        func acceptable(_ url: URL) -> Bool {
            guard Self.isFileLike(url) else { return false }
            let ext = url.pathExtension.lowercased()
            if Self.partialExtensions.contains(ext) { return false }
            if url.lastPathComponent.hasPrefix(".") { return false }
            let path = url.standardizedFileURL.path
            if path == targetPath || path.hasPrefix(targetPath + "/") { return false }
            if !rule.extensions.isEmpty, !rule.extensions.contains(ext) { return false }
            return true
        }

        var urls: [URL] = []
        if rule.recursive {
            let options: FileManager.DirectoryEnumerationOptions = [.skipsHiddenFiles, .skipsPackageDescendants]
            guard let enumerator = fm.enumerator(
                at: watch, includingPropertiesForKeys: keys, options: options
            ) else { return [] }
            for case let url as URL in enumerator {
                // Don't descend into the target subtree at all — every file in
                // there would be enumerated only to be rejected one by one.
                if url.standardizedFileURL.path == targetPath {
                    enumerator.skipDescendants()
                    continue
                }
                if acceptable(url) {
                    urls.append(url)
                    // A package is one item; its innards are never candidates.
                    if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                        enumerator.skipDescendants()
                    }
                }
            }
        } else {
            guard let children = try? fm.contentsOfDirectory(
                at: watch, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
            ) else { return [] }
            urls = children.filter(acceptable)
        }
        return urls.sorted { $0.path < $1.path }
    }

    private func isStable(_ url: URL) async -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date
        else { return false }
        // abs(): a modification date in the *future* (bad camera clock, sloppy
        // stamping by a downloader) must not park the file forever — the size
        // probe below still catches files that are actively being written.
        guard abs(Date().timeIntervalSince(modified)) > 5 else { return false }
        let before = Self.sizeSignature(of: url)
        try? await Task.sleep(nanoseconds: 700_000_000)
        return before != nil && before == Self.sizeSignature(of: url)
    }

    /// The byte count of a file, or "item count|total bytes" for a package —
    /// a package still being written grows in either.
    static func sizeSignature(of url: URL) -> String? {
        let fm = FileManager.default
        guard let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]) else { return nil }
        if values.isDirectory != true {
            return values.fileSize.map { "\($0)" }
        }
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: []) else {
            return nil
        }
        var count = 0
        var bytes = 0
        for case let child as URL in enumerator {
            count += 1
            bytes += (try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        return "\(count)|\(bytes)"
    }
}

private extension PlannedAction {
    /// Like `relativeDestination(to:)` but for the *actual* final URL after
    /// collision resolution (which may differ from the planned destination).
    func relativeDestinationOverride(finalURL: URL, target: URL) -> String {
        let base = target.standardizedFileURL.path
        let full = finalURL.standardizedFileURL.path
        if full.hasPrefix(base + "/") { return String(full.dropFirst(base.count + 1)) }
        return finalURL.lastPathComponent
    }
}
