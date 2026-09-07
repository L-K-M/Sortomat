import Foundation

/// Accumulates what a step's actions decided. Templates are rendered only at
/// `build()`, so a terminal that a later `continue` chain overrides never
/// costs a render.
struct PlacementBuilder {
    let rule: Rule
    /// The first terminal wins: a step that says "move" and then "trash" moves.
    private var operation: Placement.Operation?
    private var template: String?
    private var rootName: String?
    private var reason: String = ""
    private var origin: PlannedAction.Origin = .step
    private var effects: [(ActionType, [String])] = []
    private var modelAnswer: ModelAnswer?
    /// The matched step's name, for `{step}` in a template. Set by the
    /// evaluator when a step claims the file — it was `private` and never
    /// written, so `{step}` rendered empty for every rule that used it.
    var stepName: String = ""

    var stopped = false
    var continueMatching = false

    var isTerminal: Bool { operation != nil }

    init(rule: Rule) {
        self.rule = rule
    }

    /// Apply one action. Returns a one-line description for the trace, or nil
    /// for an action that did nothing (already terminal, or unknown).
    mutating func apply(_ action: RuleAction) -> String? {
        switch action.type {
        case .stop:
            stopped = true
            return "stop"
        case .proceed:
            continueMatching = true
            return "continue"
        case .move, .copy, .rename, .quarantine, .trash, .skip, .sortIntoDatedFolder:
            guard !isTerminal else { return nil }
            operation = PlacementBuilder.operation(for: action.type,
                                                   copyByDefault: rule.copyInsteadOfMove)
            template = PlacementBuilder.template(for: action, rule: rule)
            rootName = action.root
            reason = action.template
            return "\(action.type.rawValue) → \(template ?? "")"
        case .addTags, .removeTags, .setComment, .setLabel, .notify, .reveal, .open, .runShortcut:
            effects.append((action.type, action.tags.isEmpty ? [action.template] : action.tags))
            return "\(action.type.rawValue) \(action.tags.isEmpty ? action.template : action.tags.joined(separator: ", "))"
        default:
            return nil
        }
    }

    /// The model answered. Its values become `{model.*}` tokens, and — when
    /// nothing later in the step places the file — the implicit terminal is a
    /// move to the path the model gave, which is what the app has always done.
    ///
    /// `claimsPlacement` is what makes the model usable as *part* of a
    /// destination rather than the whole of it. Ask for one word and put it in
    /// a template you wrote — `{model.folder}/{match.author} — {match.title}` —
    /// and the step's own `move` decides where the file goes; the model fills
    /// in the one slot nobody can write a pattern for. Before this, that move
    /// was silently dead: the implicit terminal claimed the placement first and
    /// every later action found the builder already terminal.
    ///
    /// A quarantine is the exception and still wins outright: the answer was
    /// refused by the taxonomy or the confidence valve, so it must not be used
    /// to build a destination at all.
    mutating func bindModel(_ answer: ModelAnswer, action: RuleAction?,
                            claimsPlacement: Bool = true) {
        modelAnswer = answer
        // Whether a model was involved, not who chose the folder — and it has
        // to be that question, because `UIModel.heat` reads `.step` as
        // «Exact match», meaning no guessing was involved. A step that places
        // the file itself with `{model.folder}` filling one slot is still
        // carrying a guess, so crediting the step here would promise a
        // certainty the destination does not have. A review round proposed
        // moving this below the `claimsPlacement` guard; it looks like a
        // provenance fix and is a confidence bug.
        origin = answer.quarantined ? .confidence : .model
        if answer.quarantined {
            operation = .quarantine
            template = rule.quarantineSubfolder.isEmpty
                ? "{name}"
                : "\(rule.quarantineSubfolder)/{name}"
            reason = answer.reason ?? ""
            return
        }
        guard claimsPlacement, !isTerminal else { return }
        operation = rule.copyInsteadOfMove ? .copy : .move
        template = "{model.path}"
        reason = answer.reason ?? ""
    }

    mutating func setTerminal(_ operation: Placement.Operation, reason: String,
                                     origin: PlannedAction.Origin) {
        guard !isTerminal else { return }
        self.operation = operation
        self.reason = reason
        self.origin = origin
        if operation == .quarantine {
            template = rule.quarantineSubfolder.isEmpty
                ? "{name}"
                : "\(rule.quarantineSubfolder)/{name}"
        }
    }

    func build(context: RuleEvaluator.Context, captures: CaptureStore,
                      trace: RuleTrace) -> Placement {
        let operation = self.operation ?? .skip
        var rendered: RenderedTemplate?
        if operation != .skip && operation != .trash, let template {
            let parsed = TokenTemplate(template)
            rendered = parsed.render(timeZone: context.timeZone) { token in
                TemplateResolver.value(for: token, facts: context.facts, captures: captures,
                                       model: modelAnswer, rule: rule, step: stepName,
                                       now: context.now)
            }
        }
        return Placement(
            operation: operation,
            relativePath: rendered,
            rootPath: resolvedRoot(operation: operation, context: context),
            sideEffects: renderedEffects(context: context, captures: captures),
            origin: origin,
            reason: reason.isEmpty ? trace.summary : reason,
            confidence: modelAnswer?.confidence
        )
    }

    private func resolvedRoot(operation: Placement.Operation,
                              context: RuleEvaluator.Context) -> String? {
        // A rename never leaves the folder the file is already in.
        if operation == .rename { return context.facts.url.deletingLastPathComponent().path }
        if let rootName, let root = rule.destinationRoots.first(where: { $0.name == rootName }) {
            return (root.path as NSString).expandingTildeInPath
        }
        return (rule.targetPath as NSString).expandingTildeInPath
    }

    private func renderedEffects(context: RuleEvaluator.Context,
                                 captures: CaptureStore) -> [SideEffect] {
        effects.map { effect in
            SideEffect(type: effect.0, values: effect.1.map { value in
                TokenTemplate(value).render(timeZone: context.timeZone) { token in
                    TemplateResolver.value(for: token, facts: context.facts, captures: captures,
                                           model: modelAnswer, rule: rule, step: stepName,
                                           now: context.now)
                }.string()
            })
        }
    }

    private static func operation(for type: ActionType,
                                  copyByDefault: Bool) -> Placement.Operation {
        switch type {
        case .copy: return .copy
        case .rename: return .rename
        case .trash: return .trash
        case .skip: return .skip
        case .quarantine: return .quarantine
        default: return copyByDefault ? .copy : .move
        }
    }

    private static func template(for action: RuleAction, rule: Rule) -> String {
        if action.type == .sortIntoDatedFolder {
            let format = action.template.isEmpty ? "yyyy/MM" : action.template
            return "{date|date:'\(format)'}/{name}"
        }
        if action.template.isEmpty { return "{name}" }
        return action.template
    }
}
