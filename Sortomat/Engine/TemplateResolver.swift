import Foundation

/// Turns a template token into a value. The only place that knows the token
/// vocabulary, so the editor's token menu and the renderer can never drift.
enum TemplateResolver {
    /// The tokens that are not simply an attribute name. Kept beside the
    /// switch that resolves them so the editor's token menu, the validator and
    /// the renderer cannot drift apart.
    static let namedTokens: Set<String> = [
        "name", "stem", "ext", "parent", "subfolder", "relpath", "depth",
        "rule", "step", "now", "uuid", "counter",
        "tags.first", "authors.first", "subjects.first", "whereFrom.host",
        "date", "added", "created", "modified", "opened", "captured"
    ]

    /// Tokens that always produce something for any file that exists. A
    /// destination whose last component holds only tokens *outside* this set
    /// can render to nothing, which would leave the file with no name.
    static let alwaysRenders: Set<String> = [
        "name", "stem", "rule", "now", "uuid", "counter", "depth"
    ]

    static func value(for token: String, facts: FileFacts, captures: CaptureStore,
                      model: ModelAnswer?, rule: Rule, step: String,
                      now: Date) -> TemplateValue? {
        // Captures: {match.1}, {match.year}, {match.invoice.year}.
        if token.hasPrefix("match.") {
            let key = String(token.dropFirst("match.".count))
            return captures.value(forKey: key).map { TemplateValue.text($0) }
        }
        if token.hasPrefix("model.") {
            guard let model else { return nil }
            switch String(token.dropFirst("model.".count)) {
            case "folder": return model.folder.map { TemplateValue.text($0) }
            case "filename": return model.filename.map { TemplateValue.text($0) }
            case "path": return modelPath(model).map { TemplateValue.text($0) }
            case "reason": return model.reason.map { TemplateValue.text($0) }
            case "confidence": return model.confidence.map { TemplateValue.number($0) }
            default: return nil
            }
        }

        switch token {
        case "name": return .text(facts.name)
        case "stem": return .text(facts.stem)
        case "ext": return .text(facts.ext)
        case "parent": return .text(facts.parent)
        case "subfolder": return .text(facts.subfolder)
        case "relpath": return .text(facts.relativePath)
        case "depth": return .number(facts.depth)
        case "rule": return .text(rule.name)
        case "step": return .text(step)
        case "now": return .date(now)
        case "uuid": return .text(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())
        case "tags.first": return firstOf(facts, .tags)
        case "authors.first": return firstOf(facts, .authors)
        case "subjects.first": return firstOf(facts, .subjects)
        case "whereFrom.host": return simple(facts, .whereFromHost)
        case "date":
            // "The most meaningful date": when it was taken, else when it
            // arrived, else when it was made, else when it was last changed.
            for attribute in [Attribute.dateCaptured, .dateAdded, .dateCreated, .dateModified] {
                if let value = simple(facts, attribute) { return value }
            }
            return nil
        case "added": return simple(facts, .dateAdded)
        case "created": return simple(facts, .dateCreated)
        case "modified": return simple(facts, .dateModified)
        case "opened": return simple(facts, .dateOpened)
        case "captured": return simple(facts, .dateCaptured)
        // `counter` is in `namedTokens` but has no case here on purpose:
        // `TokenTemplate.render` intercepts it before `resolve` is ever
        // called and leaves it as a hole, so the pipeline can try 1, 2, 3…
        // against the file system. It never reaches this switch.
        default:
            return simple(facts, Attribute(token))
        }
    }

    /// The path the model asked for: an explicit relative path, else
    /// folder + filename, else just one of them.
    static func modelPath(_ model: ModelAnswer) -> String? {
        if let path = model.relativePath, !path.isEmpty { return path }
        switch (model.folder, model.filename) {
        case (.some(let folder), .some(let filename)) where !folder.isEmpty && !filename.isEmpty:
            return folder + "/" + filename
        case (.some(let folder), _) where !folder.isEmpty:
            return folder
        case (_, .some(let filename)) where !filename.isEmpty:
            return filename
        default:
            return nil
        }
    }

    private static func simple(_ facts: FileFacts, _ attribute: Attribute) -> TemplateValue? {
        guard case .available(let value) = facts.lookup(attribute) else { return nil }
        switch value {
        case .string(let text): return .text(text)
        case .strings(let list): return .list(list)
        case .number(let number): return .number(number)
        case .date(let date): return .date(date)
        case .bool(let flag): return .text(flag ? "true" : "false")
        case .kind(let kind): return .text(kind.rawValue)
        }
    }

    private static func firstOf(_ facts: FileFacts, _ attribute: Attribute) -> TemplateValue? {
        guard case .available(.strings(let list)) = facts.lookup(attribute),
              let first = list.first else { return nil }
        return .text(first)
    }
}

/// The one-line "why" that goes into the activity log and the journal's
/// `reason` field — the same field it carries today, so nothing downstream
/// changes shape.
enum Summary {
    static func line(for trace: RuleTrace) -> String {
        if let matched = trace.steps.last(where: { $0.matched }) {
            let name = matched.name.isEmpty
                ? L10n.t("engine.step.unnamed", "\(matched.index + 1)")
                : matched.name
            let reasons = matched.tests
                .filter { $0.verdict == .pass }
                .prefix(3)
                .map { "\($0.attribute) \($0.op) \($0.expected)" }
                .joined(separator: ", ")
            let actions = matched.actions.joined(separator: ", ")
            return L10n.t("engine.summary.matched", name, reasons, actions)
        }
        switch trace.fallbackUsed {
        case .skip?: return L10n.t("engine.summary.noMatchSkip")
        case .quarantine?: return L10n.t("engine.summary.noMatchQuarantine")
        case .askModel?: return L10n.t("engine.summary.noMatchModel")
        case nil: return L10n.t("engine.summary.noSteps")
        }
    }
}
