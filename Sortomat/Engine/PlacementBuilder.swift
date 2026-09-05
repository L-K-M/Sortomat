import Foundation

/// Accumulates what a step's actions decided. Templates are rendered only at
/// `build()`, so a terminal that a later `continue` chain overrides never
/// costs a render.
public struct PlacementBuilder {
    let rule: Rule
    /// The first terminal wins: a step that says "move" and then "trash" moves.
    private var operation: Placement.Operation?
    private var template: String?
    private var rootName: String?
    private var reason: String = ""
    private var origin: PlannedAction.Origin = .step
    private var effects: [(ActionType, [String])] = []
    private var modelAnswer: ModelAnswer?
    private var stepName: String = ""

    public var stopped = false
    public var continueMatching = false

    public var isTerminal: Bool { operation != nil }

    public init(rule: Rule) {
        self.rule = rule
    }

    /// Apply one action. Returns a one-line description for the trace, or nil
    /// for an action that did nothing (already terminal, or unknown).
    public mutating func apply(_ action: RuleAction) -> String? {
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

    /// The model answered. Its values become `{model.*}` tokens; if no later
    /// action places the file, the implicit terminal is a move to the path the
    /// model gave — exactly what the app does today.
    public mutating func bindModel(_ answer: ModelAnswer, action: RuleAction?) {
        modelAnswer = answer
        origin = answer.quarantined ? .confidence : .model
        if answer.quarantined {
            operation = .quarantine
            template = rule.quarantineSubfolder.isEmpty
                ? "{name}"
                : "\(rule.quarantineSubfolder)/{name}"
            reason = answer.reason ?? ""
            return
        }
        guard !isTerminal else { return }
        operation = rule.copyInsteadOfMove ? .copy : .move
        template = "{model.path}"
        reason = answer.reason ?? ""
    }

    public mutating func setTerminal(_ operation: Placement.Operation, reason: String,
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

    public func build(context: RuleEvaluator.Context, captures: CaptureStore,
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
        effects.map { type, values in
            SideEffect(type: type, values: values.map { value in
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
