import Foundation

/// Turns pre-rules into steps, and steps back into pre-rules.
///
/// Both directions matter. Upgrading has to be lossless *and* faithful: a
/// migrated rule must do exactly what it did yesterday, including the parts
/// that were arguably wrong (age means the modification date), because
/// changing behaviour behind someone's back is worse than the wrong default.
/// The editor offers the fix; the migration never takes it.
///
/// Downgrading has to be *safe*: an older build reading a config written here
/// runs the projected pre-rules, and a rule it cannot represent is projected
/// as a single catch-all skip — doing nothing is the only acceptable failure
/// mode for a tool that moves files.
enum LegacyMigration {
    struct Upgraded {
        var steps: [RuleStep]
        var fallback: Rule.Fallback
        var summary: [String]
    }

    /// The five characters the new glob language gave meaning to. A legacy
    /// pattern like `Rechnung [2024].pdf` has to keep meaning what it meant.
    static let newGlobMetacharacters: Set<Character> = ["[", "]", "{", "}", "\\"]

    static func upgrade(preRules: [PreRule], copyInsteadOfMove: Bool) -> Upgraded {
        var steps: [RuleStep] = []
        var summary: [String] = []
        var sawAgeCondition = false

        for preRule in preRules {
            let group = condition(for: preRule)
            let actions = actions(for: preRule, copyInsteadOfMove: copyInsteadOfMove)
            if preRule.match == .olderThanDays || preRule.match == .newerThanDays {
                sawAgeCondition = true
            }
            steps.append(RuleStep(
                id: preRule.id,     // identity is preserved: traces and previews still line up
                name: preRule.name.isEmpty ? preRule.pattern : preRule.name,
                enabled: true,
                when: group,
                then: actions
            ))
        }

        if !preRules.isEmpty {
            summary.append(L10n.t("migration.stepsFromPreRules", "\(preRules.count)"))
        }
        if sawAgeCondition {
            summary.append(L10n.t("migration.ageUsesModified"))
        }
        // Today a file no pre-rule claimed goes to the model. That stays true.
        return Upgraded(steps: steps, fallback: .askModel, summary: summary)
    }

    // MARK: - Conditions

    static func condition(for preRule: PreRule) -> ConditionGroup {
        switch preRule.match {
        case .glob:
            return single(ConditionTest(attribute: .name, op: .matchesGlob,
                                        value: .text(escapeLegacyGlob(preRule.pattern))))
        case .regex:
            return single(ConditionTest(attribute: .name, op: .matchesRegex,
                                        value: .text(preRule.pattern)))
        case .kind:
            // Pinned to the old resolver: an extensionless file that the new
            // UTType path would now call an image must not start matching a
            // rule the user wrote years ago.
            return single(ConditionTest(attribute: .kind, op: .equals,
                                        value: .text(preRule.pattern.lowercased()),
                                        kindSource: .extensionTable))
        case .olderThanDays, .newerThanDays:
            guard let days = Double(preRule.pattern.trimmingCharacters(in: .whitespaces)) else {
                // Today an unparsable day count makes the pre-rule never match.
                // An empty `any` group is exactly that — and the validator now
                // says so out loud instead of leaving a dead rule in place.
                return ConditionGroup(mode: .any, items: [])
            }
            return single(ConditionTest(
                attribute: .dateModified,
                op: preRule.match == .olderThanDays ? .olderThan : .newerThan,
                value: .text("\(NumberText.canonical(days))d")
            ))
        }
    }

    private static func single(_ test: ConditionTest) -> ConditionGroup {
        ConditionGroup(mode: .all, items: [.test(test)])
    }

    /// Escapes the characters the new glob language added, so an old pattern
    /// keeps its literal meaning.
    static func escapeLegacyGlob(_ pattern: String) -> String {
        var escaped = ""
        for character in pattern {
            if newGlobMetacharacters.contains(character) { escaped.append("\\") }
            escaped.append(character)
        }
        return escaped
    }

    // MARK: - Actions

    static func actions(for preRule: PreRule, copyInsteadOfMove: Bool) -> [RuleAction] {
        switch preRule.action {
        case .skip:
            return [RuleAction(type: .skip)]
        case .useLLM:
            // Every ModelStepOptions field nil means "use the rule's own
            // prompt, taxonomy, privacy mode and threshold" — today's path.
            return [RuleAction(type: .askModel)]
        case .route:
            return [RuleAction(type: copyInsteadOfMove ? .copy : .move,
                               template: route(preRule.routePath))]
        }
    }

    /// Reproduces `DeterministicEngine.expandRoute`, including its data-safety
    /// fixes, as a v2 template.
    static func route(_ template: String) -> String {
        var text = template.trimmingCharacters(in: .whitespaces)
        // An empty route means "the target folder itself" — it used to expand
        // to the absolute path "/{name}" and fail forever.
        if text.isEmpty { text = "{name}" }
        if !text.contains("{name}") {
            text += text.hasSuffix("/") ? "{name}" : "/{name}"
        }
        text = escapeNonLegacyBraces(text)
        // Fixed order, longest token first: a file literally named
        // "receipt {year}.pdf" must not route differently between launches.
        text = text.replacingOccurrences(of: "{month}", with: "{modified|date:'MM'}")
        text = text.replacingOccurrences(of: "{year}", with: "{modified|date:'yyyy'}")
        text = text.replacingOccurrences(of: "{day}", with: "{modified|date:'dd'}")
        // The legacy {name} token is the *stem*; v2's {name} includes the
        // extension, and `Sanitizer` supplies the extension either way.
        text = text.replacingOccurrences(of: "{name}", with: "{stem}")
        return text
    }

    /// Braces that are not one of the five legacy tokens were literal text;
    /// in a language where braces are placeholders they have to be escaped.
    static func escapeNonLegacyBraces(_ template: String) -> String {
        let legacy = ["{name}", "{ext}", "{year}", "{month}", "{day}"]
        var result = ""
        var index = template.startIndex
        outer: while index < template.endIndex {
            if template[index] == "{" {
                for token in legacy where template[index...].hasPrefix(token) {
                    result += token
                    index = template.index(index, offsetBy: token.count)
                    continue outer
                }
                result += "{{"
                index = template.index(after: index)
                continue
            }
            if template[index] == "}" {
                result += "}}"
                index = template.index(after: index)
                continue
            }
            result.append(template[index])
            index = template.index(after: index)
        }
        return result
    }

    // MARK: - Downgrade projection

    /// Steps projected back to pre-rules, so an older build reading this config
    /// still does something sane. A step that cannot be represented is dropped
    /// and the whole projection is prefixed with a catch-all skip: an old build
    /// then does *nothing* for that rule rather than something its author never
    /// asked for.
    static func project(steps: [RuleStep], copyInsteadOfMove: Bool) -> [PreRule] {
        var projected: [PreRule] = []
        var lostSomething = false

        for step in steps {
            guard step.enabled, let preRule = projectOne(step, copyInsteadOfMove: copyInsteadOfMove) else {
                lostSomething = true
                continue
            }
            projected.append(preRule)
        }
        guard lostSomething else { return projected }
        return [PreRule(name: L10n.t("migration.downgradeGuard"), match: .glob,
                        pattern: "*", action: .skip)] + projected
    }

    private static func projectOne(_ step: RuleStep, copyInsteadOfMove: Bool) -> PreRule? {
        guard step.when.mode == .all, step.when.items.count == 1,
              case .test(let test) = step.when.items[0],
              step.then.count == 1 else { return nil }
        let action = step.then[0]

        let match: PreRule.Match
        let pattern: String
        switch (test.attribute, test.op) {
        case (.name, .matchesGlob):
            match = .glob
            pattern = unescapeLegacyGlob(ValueCoercion.string(test.value) ?? "")
        case (.name, .matchesRegex):
            match = .regex
            pattern = ValueCoercion.string(test.value) ?? ""
        case (.kind, .equals):
            match = .kind
            pattern = ValueCoercion.string(test.value) ?? ""
        case (.dateModified, .olderThan), (.dateModified, .newerThan):
            guard let span = ValueCoercion.timeSpan(test.value), span.unit == .days else { return nil }
            match = test.op == .olderThan ? .olderThanDays : .newerThanDays
            pattern = NumberText.canonical(span.amount)
        default:
            return nil
        }

        let legacyAction: PreRule.Action
        var routePath = ""
        switch action.type {
        case .skip: legacyAction = .skip
        case .askModel:
            // An askModel that overrides the rule's prompt or taxonomy has no
            // legacy equivalent, so the rule projects to the catch-all skip.
            guard action.model == nil else { return nil }
            legacyAction = .useLLM
        case .move, .copy:
            guard (action.type == .copy) == copyInsteadOfMove,
                  let legacy = legacyRoute(action.template) else { return nil }
            legacyAction = .route
            routePath = legacy
        default:
            return nil
        }

        return PreRule(id: step.id, name: step.name, match: match, pattern: pattern,
                       action: legacyAction, routePath: routePath)
    }

    static func unescapeLegacyGlob(_ pattern: String) -> String {
        var result = ""
        var escaped = false
        for character in pattern {
            if escaped {
                result.append(character)
                escaped = false
                continue
            }
            if character == "\\" { escaped = true; continue }
            result.append(character)
        }
        return result
    }

    /// A v2 template written back as a legacy one, or nil when it uses
    /// anything the old engine could not express.
    static func legacyRoute(_ template: String) -> String? {
        var text = template
        text = text.replacingOccurrences(of: "{modified|date:'yyyy'}", with: "{year}")
        text = text.replacingOccurrences(of: "{modified|date:'MM'}", with: "{month}")
        text = text.replacingOccurrences(of: "{modified|date:'dd'}", with: "{day}")
        text = text.replacingOccurrences(of: "{stem}", with: "{name}")
        text = text.replacingOccurrences(of: "{{", with: "\u{0001}")
        text = text.replacingOccurrences(of: "}}", with: "\u{0002}")
        // Anything left that looks like a placeholder is not expressible.
        let remaining = TokenTemplate(text).tokens
        let legacyTokens: Set<String> = ["name", "ext", "year", "month", "day"]
        guard remaining.allSatisfy({ legacyTokens.contains($0) }) else { return nil }
        text = text.replacingOccurrences(of: "\u{0001}", with: "{")
        text = text.replacingOccurrences(of: "\u{0002}", with: "}")
        return text
    }
}
