import Foundation

/// Everything a rule can be wrong about that can be found *without running it*.
///
/// The editor is the customer. Each finding names the exact step, condition or
/// action it belongs to, so a warning is drawn where the mistake is rather than
/// in a list at the bottom that nobody reads. Nothing here touches the disk,
/// asks the model, or costs anything: it is a pure function of the rule, which
/// is what makes it safe to run on every keystroke.
///
/// Two rules of thumb kept it honest:
///
/// * **An error is a rule that cannot do what it says.** A condition that can
///   never be true, an action that will never run, a template that would leave
///   a file with no name. A warning is a rule that works but probably surprises
///   its author.
/// * **No finding may be wrong.** A validator that cries wolf is turned off, so
///   anything that merely *looks* suspicious — an unusual operator, an
///   unfamiliar token — stays silent unless the engine really would reject it.
enum RuleValidator {
    struct Finding: Equatable, Identifiable, Sendable {
        enum Severity: Int, Comparable, Sendable {
            case warning
            case error

            static func < (lhs: Severity, rhs: Severity) -> Bool {
                lhs.rawValue < rhs.rawValue
            }
        }

        /// Where the editor should draw it.
        enum Site: Equatable, Sendable {
            case rule
            case step(UUID)
            case condition(step: UUID, test: UUID)
            case action(step: UUID, action: UUID)
        }

        /// A stable, English, greppable identifier. The message is localized
        /// and may be rewritten; this is what a test asserts on.
        var code: String
        var severity: Severity
        var message: String
        var site: Site

        var id: String { "\(code)|\(siteKey)|\(message)" }

        /// The step a finding belongs to, so the editor can badge the card.
        var stepID: UUID? {
            switch site {
            case .rule: return nil
            case .step(let id): return id
            case .condition(let step, _): return step
            case .action(let step, _): return step
            }
        }

        /// The condition row this finding belongs to, so the editor can draw
        /// it against the condition rather than in a list at the bottom.
        var conditionID: UUID? {
            if case .condition(_, let test) = site { return test }
            return nil
        }

        /// The action row this finding belongs to.
        var actionID: UUID? {
            if case .action(_, let action) = site { return action }
            return nil
        }

        /// About the step as a whole rather than one of its rows.
        var isAboutStepItself: Bool {
            if case .step = site { return true }
            return false
        }

        private var siteKey: String {
            switch site {
            case .rule: return "rule"
            case .step(let id): return "step:\(id.uuidString)"
            case .condition(let step, let test):
                return "condition:\(step.uuidString):\(test.uuidString)"
            case .action(let step, let action):
                return "action:\(step.uuidString):\(action.uuidString)"
            }
        }
    }

    // MARK: - Entry point

    static func findings(for rule: Rule) -> [Finding] {
        var findings = ruleFindings(rule)
        // A step whose `when` is empty in `all`/`none` mode matches every file,
        // so nothing after it can ever run — unless it hands the file on with
        // `continue`. The first such step is the horizon.
        var horizon: Int?
        let steps = rule.steps
        for (index, step) in steps.enumerated() {
            if let horizon, index > horizon {
                findings.append(Finding(
                    code: "step.unreachable", severity: .warning,
                    message: L10n.t("validate.step.unreachable", "\(horizon + 1)"),
                    site: .step(step.id)
                ))
            }
            findings.append(contentsOf: stepFindings(step, rule: rule))
            if horizon == nil, step.enabled, alwaysMatches(step.when), !handsOn(step) {
                horizon = index
            }
        }
        return findings.sorted { left, right in
            left.severity == right.severity ? left.code < right.code
                                            : left.severity > right.severity
        }
    }

    /// The one-line answer for a header badge: nothing, "2 problems", "1 note".
    static func headline(_ findings: [Finding]) -> String? {
        let errors = findings.filter { $0.severity == .error }.count
        let warnings = findings.count - errors
        if errors > 0 { return L10n.plural("validate.errors", errors) }
        if warnings > 0 { return L10n.plural("validate.warnings", warnings) }
        return nil
    }

    // MARK: - The rule itself

    private static func ruleFindings(_ rule: Rule) -> [Finding] {
        var findings: [Finding] = []
        func add(_ code: String, _ severity: Finding.Severity, _ message: String) {
            findings.append(Finding(code: code, severity: severity,
                                    message: message, site: .rule))
        }

        if rule.watchPath.trimmingCharacters(in: .whitespaces).isEmpty {
            add("rule.noWatchFolder", .error, L10n.t("validate.rule.noWatchFolder"))
        }
        if rule.targetPath.trimmingCharacters(in: .whitespaces).isEmpty {
            add("rule.noTargetFolder", .error, L10n.t("validate.rule.noTargetFolder"))
        }
        // A rule with no steps and a `skip` fallback is inert. It is the state
        // every new rule starts in, so it is a note rather than a problem.
        if rule.steps.isEmpty && rule.fallback == .skip {
            add("rule.doesNothing", .warning, L10n.t("validate.rule.doesNothing"))
        }
        // The model with no instruction is the one mistake that costs money:
        // every unclaimed file is a paid call that can only guess.
        if rule.fallback == .askModel,
           rule.prompt.trimmingCharacters(in: .whitespaces).isEmpty {
            add("rule.modelWithoutPrompt", .error, L10n.t("validate.rule.modelWithoutPrompt"))
        }
        var seenRoots: Set<String> = []
        for root in rule.destinationRoots {
            let name = root.name.trimmingCharacters(in: .whitespaces)
            if name.isEmpty || root.path.trimmingCharacters(in: .whitespaces).isEmpty {
                add("rule.incompleteRoot", .error, L10n.t("validate.rule.incompleteRoot"))
                continue
            }
            if !seenRoots.insert(name.lowercased()).inserted {
                add("rule.duplicateRoot", .error, L10n.t("validate.rule.duplicateRoot", name))
            }
        }
        return findings
    }

    // MARK: - One step

    private static func stepFindings(_ step: RuleStep, rule: Rule) -> [Finding] {
        var findings: [Finding] = []

        if step.then.isEmpty {
            findings.append(Finding(
                code: "step.noActions", severity: .error,
                message: L10n.t("validate.step.noActions"), site: .step(step.id)
            ))
        }
        let placements = step.then.filter { ActionType.placements.contains($0.type) }
        if placements.count > 1 {
            findings.append(Finding(
                code: "step.twoPlacements", severity: .error,
                message: L10n.t("validate.step.twoPlacements",
                                placements[0].type.rawValue, placements[1].type.rawValue),
                site: .step(step.id)
            ))
        }
        // An empty `any` is the opposite of an empty `all`: it can never be
        // satisfied, so the step is dead rather than greedy.
        if step.when.mode == .any && step.when.items.isEmpty {
            findings.append(Finding(
                code: "step.neverMatches", severity: .error,
                message: L10n.t("validate.step.neverMatches"), site: .step(step.id)
            ))
        }
        findings.append(contentsOf: groupFindings(step.when, step: step, rule: rule))
        for action in step.then {
            findings.append(contentsOf: actionFindings(action, step: step, rule: rule))
        }
        return findings
    }

    private static func groupFindings(_ group: ConditionGroup, step: RuleStep,
                                      rule: Rule) -> [Finding] {
        var findings: [Finding] = []
        for item in group.items {
            switch item {
            case .group(let nested):
                if nested.items.isEmpty {
                    findings.append(Finding(
                        code: "condition.emptyGroup", severity: .warning,
                        message: L10n.t("validate.condition.emptyGroup"),
                        site: .step(step.id)
                    ))
                }
                findings.append(contentsOf: groupFindings(nested, step: step, rule: rule))
            case .test(let test):
                findings.append(contentsOf: testFindings(test, step: step, rule: rule))
            }
        }
        return findings
    }

    // MARK: - One condition

    private static func testFindings(_ test: ConditionTest, step: RuleStep,
                                     rule: Rule) -> [Finding] {
        var findings: [Finding] = []
        func add(_ code: String, _ severity: Finding.Severity, _ message: String) {
            findings.append(Finding(code: code, severity: severity, message: message,
                                    site: .condition(step: step.id, test: test.id)))
        }

        guard Attribute.all.contains(test.attribute) else {
            add("condition.unknownAttribute", .error,
                L10n.t("validate.condition.unknownAttribute", test.attribute.rawValue))
            return findings
        }
        guard Operator.all.contains(test.op) else {
            add("condition.unknownOperator", .error,
                L10n.t("validate.condition.unknownOperator", test.op.rawValue))
            return findings
        }
        if !Operator.valueless.contains(test.op) && test.value.isEmpty {
            add("condition.noValue", .error,
                L10n.t("validate.condition.noValue", test.op.rawValue))
        }
        if test.op == .between, case .list(let items) = test.value, items.count != 2 {
            add("condition.betweenNeedsTwo", .error, L10n.t("validate.condition.betweenNeedsTwo"))
        }
        // A rule that never reads contents cannot test them, and the engine
        // says so at run time with `blockedByPrivacy` — one file at a time,
        // in a log. Here it is one line in the editor, before it ever runs.
        //
        // Which attributes those are is asked of `FileFacts`, not of the cost
        // table. Reading `cost(of:) >= .content` as "opens the file" was wrong
        // twice over: it made `duplicateInTarget` — a `probe` that reads a
        // directory index and never opens anything — a red error on a rule
        // that works, which is exactly the crying wolf this validator was
        // written to avoid; and it called `title` impossible when Spotlight
        // answers it for most files without the rule reading a byte.
        if rule.privacyMode == .metadataOnly {
            if FileFacts.alwaysNeedsContent.contains(test.attribute) {
                add("condition.blockedByPrivacy", .error,
                    L10n.t("validate.condition.blockedByPrivacy", test.attribute.rawValue))
            } else if FileFacts.prefersMetadata.contains(test.attribute) {
                add("condition.metadataOnlyValue", .warning,
                    L10n.t("validate.condition.metadataOnlyValue", test.attribute.rawValue))
            }
        }
        if Operator.regexes.contains(test.op), case .text(let pattern) = test.value,
           !pattern.isEmpty {
            if !DeterministicEngine.isSafeRegex(pattern) {
                add("condition.unsafeRegex", .error, L10n.t("validate.condition.unsafeRegex"))
            } else if RegexCache.regex(pattern, caseSensitive: true) == nil {
                add("condition.badRegex", .error, L10n.t("validate.condition.badRegex"))
            }
        }
        // Capturing on anything but a positive regex records nothing, so a
        // `{match.…}` written against it renders empty.
        if test.captureAs != nil, test.op != .matchesRegex {
            add("condition.captureWithoutRegex", .warning,
                L10n.t("validate.condition.captureWithoutRegex"))
        }
        // Asking the model *inside a condition* is declared but not wired:
        // the fact lookup answers `needsModel`, and only a `pass` passes, so
        // the test is quietly never true. Better said here than discovered
        // after a week of a rule that silently matched nothing.
        if test.attribute == .modelSays {
            add("condition.modelNotSupported", .error,
                L10n.t("validate.condition.modelNotSupported"))
        }
        return findings
    }

    // MARK: - One action

    private static func actionFindings(_ action: RuleAction, step: RuleStep,
                                       rule: Rule) -> [Finding] {
        var findings: [Finding] = []
        func add(_ code: String, _ severity: Finding.Severity, _ message: String) {
            findings.append(Finding(code: code, severity: severity, message: message,
                                    site: .action(step: step.id, action: action.id)))
        }

        guard ActionType.known.contains(action.type) else {
            add("action.unknownType", .error,
                L10n.t("validate.action.unknownType", action.type.rawValue))
            return findings
        }
        if let root = action.root, !root.isEmpty,
           !rule.destinationRoots.contains(where: { $0.name == root }) {
            add("action.unknownRoot", .error, L10n.t("validate.action.unknownRoot", root))
        }
        if action.type == .addTags || action.type == .removeTags {
            if action.tags.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                add("action.noTags", .error, L10n.t("validate.action.noTags"))
            }
        }
        // Declared, recorded, and not carried out by this build. Said here
        // rather than left to be discovered from a tag that never appears.
        if ActionType.sideEffects.contains(action.type),
           !ActionExecutor.supported.contains(action.type) {
            add("action.notAppliedYet", .warning,
                L10n.t("validate.action.notAppliedYet", action.type.rawValue))
        }
        // `trash` is accepted by the builder, but `Placement.relativePath` is
        // nil for it, so `plan(from:)` turns it into a skip: the file is left
        // exactly where it is. Safe, and not what the rule says — which is why
        // the warning has to state it, and state it accurately.
        if action.type == .trash {
            add("action.trashMoves", .warning, L10n.t("validate.action.trashMoves"))
        }
        if action.type == .runShortcut && action.template.isEmpty {
            add("action.noShortcut", .error, L10n.t("validate.action.noShortcut"))
        }
        if action.type == .askModel {
            var instruction = rule.prompt
            if let own = action.model?.prompt, !own.isEmpty { instruction = own }
            if instruction.trimmingCharacters(in: .whitespaces).isEmpty {
                add("action.modelWithoutPrompt", .error,
                    L10n.t("validate.rule.modelWithoutPrompt"))
            }
        }

        guard !action.template.isEmpty else { return findings }
        // `sortIntoDatedFolder` reads its template as a date format, not as a
        // token template — `yyyy/MM` has no placeholders and is not an error.
        guard action.type != .sortIntoDatedFolder else { return findings }
        let template = TokenTemplate(action.template)
        for error in template.errors {
            add("action.badTemplate", .error,
                L10n.t("validate.action.badTemplate", error.message))
        }
        for token in template.tokens where !isKnownToken(token) {
            add("action.unknownToken", .warning,
                L10n.t("validate.action.unknownToken", token))
        }
        if template.tokens.contains(where: { $0.hasPrefix("match.") }),
           !rule.steps.contains(where: { $0.when.captures }) {
            add("action.captureWithoutSource", .warning,
                L10n.t("validate.action.captureWithoutSource"))
        }
        if ActionType.placements.contains(action.type), lastComponentCanBeEmpty(template) {
            add("action.nameCanBeEmpty", .warning, L10n.t("validate.action.nameCanBeEmpty"))
        }
        return findings
    }

    // MARK: - Helpers

    /// A group that is true for every file: `all` or `none` with nothing in it.
    private static func alwaysMatches(_ group: ConditionGroup) -> Bool {
        group.items.isEmpty && group.mode != .any
    }

    /// Whether a step lets the file fall through to the next one.
    private static func handsOn(_ step: RuleStep) -> Bool {
        step.then.contains { $0.type == .proceed }
    }

    private static func isKnownToken(_ token: String) -> Bool {
        if token.hasPrefix("match.") { return true }
        if token.hasPrefix("model.") {
            return ["folder", "filename", "path", "reason", "confidence"]
                .contains(String(token.dropFirst("model.".count)))
        }
        if TemplateResolver.namedTokens.contains(token) { return true }
        return Attribute.all.contains(Attribute(token))
    }

    /// The file's own name is the last component of the destination. If every
    /// token in it can render empty and there is no literal text to fall back
    /// on, the file would arrive with no name at all — `Sanitizer` catches it,
    /// but by then the user has already been surprised.
    private static func lastComponentCanBeEmpty(_ template: TokenTemplate) -> Bool {
        var component: [TokenTemplate.Node] = []
        for node in template.nodes {
            switch node {
            case .literal(let text):
                guard let slash = text.lastIndex(of: "/") else {
                    component.append(node)
                    continue
                }
                let tail = String(text[text.index(after: slash)...])
                component = tail.isEmpty ? [] : [TokenTemplate.Node.literal(tail)]
            case .placeholder:
                component.append(node)
            }
        }
        var sawPlaceholder = false
        for node in component {
            switch node {
            case .literal(let text):
                if !text.trimmingCharacters(in: .whitespaces).isEmpty { return false }
            case .placeholder(let token, _):
                if TemplateResolver.alwaysRenders.contains(token) { return false }
                sawPlaceholder = true
            }
        }
        return sawPlaceholder
    }
}

private extension ConditionGroup {
    /// Whether anything in this group records a capture.
    var captures: Bool {
        items.contains { item in
            switch item {
            case .test(let test): return test.op == .matchesRegex
            case .group(let nested): return nested.captures
            }
        }
    }
}
