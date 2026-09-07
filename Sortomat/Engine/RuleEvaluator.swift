import Foundation

/// What the model was asked, and what it answered. Both are plain values so
/// the evaluator stays pure — the pipeline does the talking.
struct ModelRequest: Equatable, Sendable {
    var ruleID: UUID
    var stepIndex: Int
    var actionIndex: Int
    var options: ModelStepOptions

    init(ruleID: UUID, stepIndex: Int, actionIndex: Int,
                options: ModelStepOptions = ModelStepOptions()) {
        self.ruleID = ruleID
        self.stepIndex = stepIndex
        self.actionIndex = actionIndex
        self.options = options
    }
}

struct ModelAnswer: Equatable, Sendable {
    var folder: String?
    var filename: String?
    var relativePath: String?
    var reason: String?
    var confidence: Double?
    /// Set when the pipeline's taxonomy or confidence valve redirected the
    /// answer; the engine then places into the unsure folder and stops.
    var quarantined: Bool

    init(folder: String? = nil, filename: String? = nil, relativePath: String? = nil,
                reason: String? = nil, confidence: Double? = nil, quarantined: Bool = false) {
        self.folder = folder
        self.filename = filename
        self.relativePath = relativePath
        self.reason = reason
        self.confidence = confidence
        self.quarantined = quarantined
    }
}

/// Where evaluation stopped, so it can pick up again once the model answered.
struct ResumeToken: Equatable, Sendable {
    var stepIndex: Int
    var actionIndex: Int
    var fromFallback: Bool

    init(stepIndex: Int, actionIndex: Int, fromFallback: Bool = false) {
        self.stepIndex = stepIndex
        self.actionIndex = actionIndex
        self.fromFallback = fromFallback
    }
}

/// The engine. A pure, synchronous function of `(Rule, FileFacts, now)` — no
/// I/O of its own, which is what makes "test this rule against a file" free
/// and the whole thing unit-testable with no file system at all.
enum RuleEvaluator {
    struct Context {
        var rule: Rule
        var facts: FileFacts
        var now: Date
        var timeZone: TimeZone
        var calendar: Calendar
        /// False in the editor's "test against a file" and whenever the
        /// pipeline has no budget and no key: `askModel` then defers instead
        /// of asking.
        var allowModel: Bool

        init(rule: Rule, facts: FileFacts, now: Date = Date(),
                    timeZone: TimeZone = .current,
                    calendar: Calendar = Calendar(identifier: .gregorian),
                    allowModel: Bool = true) {
            self.rule = rule
            self.facts = facts
            self.now = now
            self.timeZone = timeZone
            var gregorian = calendar
            gregorian.timeZone = timeZone
            self.calendar = gregorian
            self.allowModel = allowModel
        }
    }

    enum Outcome {
        case decided(Placement, RuleTrace)
        case needsModel(ModelRequest, ResumeToken, RuleTrace)
        /// The model is needed but not available right now: no key, no budget,
        /// or the editor asked for a free evaluation.
        case deferred(RuleTrace)
    }

    static func evaluate(_ context: Context) -> Outcome {
        var state = State(rule: context.rule, timeZone: context.timeZone)
        return walk(&state, from: 0, context: context)
    }

    /// Continue after the pipeline resolved a model request.
    static func resume(_ token: ResumeToken, answer: ModelAnswer,
                              context: Context) -> Outcome {
        var state = State(rule: context.rule, timeZone: context.timeZone)
        state.answer = answer
        // The steps before the one that asked already ran; re-running them is
        // free (facts are cached) and keeps the trace complete.
        return walk(&state, from: 0, context: context, resuming: token)
    }

    // MARK: - State

    struct State {
        var trace: RuleTrace
        var builder: PlacementBuilder
        var captures = CaptureStore()
        var answer: ModelAnswer?

        init(rule: Rule, timeZone: TimeZone) {
            trace = RuleTrace(ruleID: rule.id, ruleName: rule.name, timeZone: timeZone.identifier)
            builder = PlacementBuilder(rule: rule)
        }
    }

    // MARK: - The walk

    private static func walk(_ state: inout State, from startIndex: Int,
                             context: Context, resuming token: ResumeToken? = nil) -> Outcome {
        let rule = context.rule

        for (index, step) in rule.steps.enumerated() where index >= startIndex {
            guard step.enabled else { continue }

            let evaluation = evaluateGroup(step.when, path: "steps[\(index)].when",
                                           captures: &state.captures, context: context)
            state.trace.steps.append(
                RuleTrace.StepOutcome(stepID: step.id, index: index, name: step.name,
                                      matched: evaluation.matched,
                                      culpritIndex: evaluation.culpritIndex,
                                      tests: evaluation.tests)
            )
            guard evaluation.matched else { continue }
            // `{step}` resolves against this.
            state.builder.stepName = step.name

            var descriptions: [String] = []
            for (actionIndex, action) in step.then.enumerated() {
                // When resuming, the asking action is answered rather than
                // asked again. The actions *before* it run like any other:
                // the builder is fresh on every walk, so a tag added ahead of
                // the question would otherwise leave with the pass that asked
                // it. (They cannot include another `askModel` — the first
                // pass would have stopped there instead.)
                // The action's *type* as well as its position. A token carries
                // indices, the model round-trip is asynchronous, and `resume`
                // takes the rule from its caller — so a rule edited while the
                // answer was in flight could bind a stale answer to whatever
                // now sits at those indices. Tokens are only ever minted from
                // an `askModel`, so this is a no-op when nothing changed.
                if let token, token.fromFallback == false, let answer = state.answer,
                   index == token.stepIndex, actionIndex == token.actionIndex,
                   action.type == .askModel {
                    // If the step places the file itself further down, the
                    // model answered one *part* of a destination the user
                    // wrote — so it must not claim the placement here and
                    // leave that action dead.
                    let placesItself = step.then.dropFirst(actionIndex + 1)
                        .contains { ActionType.placements.contains($0.type) }
                    state.builder.bindModel(answer, action: action,
                                            claimsPlacement: !placesItself)
                    descriptions.append("askModel → \(answer.relativePath ?? answer.folder ?? "")")
                    continue
                }
                if action.type == .askModel {
                    guard context.allowModel else { return .deferred(finish(&state, context: context)) }
                    let request = ModelRequest(ruleID: rule.id, stepIndex: index,
                                               actionIndex: actionIndex,
                                               options: action.model ?? ModelStepOptions())
                    let resume = ResumeToken(stepIndex: index, actionIndex: actionIndex)
                    return .needsModel(request, resume, finish(&state, context: context))
                }
                if let description = state.builder.apply(action) {
                    descriptions.append(description)
                }
            }
            if let last = state.trace.steps.indices.last {
                state.trace.steps[last].actions = descriptions
            }

            if state.builder.stopped { break }
            if state.builder.isTerminal && !state.builder.continueMatching { break }
            // `continue` is per step, never sticky.
            state.builder.continueMatching = false
        }

        if !state.builder.isTerminal && !state.builder.stopped {
            state.trace.fallbackUsed = rule.fallback
            switch rule.fallback {
            case .skip:
                state.builder.setTerminal(.skip, reason: L10n.t("engine.reason.noStepMatched"),
                                          origin: .fallback)
            case .quarantine:
                state.builder.setTerminal(.quarantine, reason: L10n.t("engine.reason.noStepMatched"),
                                          origin: .fallback)
            case .askModel:
                if let answer = state.answer {
                    state.builder.bindModel(answer, action: nil)
                } else {
                    guard context.allowModel else { return .deferred(finish(&state, context: context)) }
                    let request = ModelRequest(ruleID: rule.id, stepIndex: -1, actionIndex: -1)
                    let resume = ResumeToken(stepIndex: -1, actionIndex: -1, fromFallback: true)
                    return .needsModel(request, resume, finish(&state, context: context))
                }
            }
        }

        let trace = finish(&state, context: context)
        return .decided(state.builder.build(context: context, captures: state.captures,
                                            trace: trace), trace)
    }

    private static func finish(_ state: inout State, context: Context) -> RuleTrace {
        state.trace.summary = Summary.line(for: state.trace)
        return state.trace
    }

    // MARK: - Groups

    struct GroupEvaluation {
        var matched: Bool
        var culpritIndex: Int?
        var tests: [RuleTrace.TestOutcome]
    }

    static func evaluateGroup(_ group: ConditionGroup, path: String,
                              captures: inout CaptureStore,
                              context: Context) -> GroupEvaluation {
        var outcomes: [RuleTrace.TestOutcome] = Array(
            repeating: RuleTrace.TestOutcome(path: path, attribute: "", op: "", expected: "",
                                             actual: nil, verdict: .notEvaluated, cost: "free"),
            count: group.items.count
        )
        var nested: [Int: GroupEvaluation] = [:]
        var decided: Bool?
        var culprit: Int?

        // Cheapest first, so a free name test rejects a file before an OCR
        // pass is ever considered — unless a condition captures, in which case
        // author order is what the user reasoned about.
        let order = group.items.contains(where: capturesSomething)
            ? Array(group.items.indices)
            : group.items.indices.sorted { cost(of: group.items[$0], context: context)
                                            < cost(of: group.items[$1], context: context) }

        for index in order {
            if decided != nil { break }
            let item = group.items[index]
            switch item {
            case .test(let test):
                let result = ConditionEvaluator.evaluate(test, facts: context.facts,
                                                         now: context.now,
                                                         calendar: context.calendar)
                if !result.captures.isEmpty {
                    captures.record(result.captures, label: test.captureAs)
                }
                outcomes[index] = RuleTrace.TestOutcome(
                    path: "\(path).\(group.mode.rawValue)[\(index)]",
                    attribute: test.attribute.rawValue,
                    op: test.op.rawValue,
                    expected: describe(test.value),
                    actual: result.actual,
                    verdict: result.verdict,
                    cost: context.facts.cost(of: test.attribute).name
                )
                decided = fold(mode: group.mode, passed: result.verdict.passed,
                               index: index, culprit: &culprit, current: decided)
            case .group(let child):
                let evaluation = evaluateGroup(child, path: "\(path).\(group.mode.rawValue)[\(index)]",
                                               captures: &captures, context: context)
                nested[index] = evaluation
                outcomes[index] = RuleTrace.TestOutcome(
                    path: "\(path).\(group.mode.rawValue)[\(index)]",
                    attribute: child.mode.rawValue,
                    op: "group",
                    expected: "\(child.items.count)",
                    actual: nil,
                    verdict: evaluation.matched ? .pass : .fail,
                    cost: "free"
                )
                decided = fold(mode: group.mode, passed: evaluation.matched,
                               index: index, culprit: &culprit, current: decided)
            }
        }

        // Nothing decided the group: `any` found no passing member, `all` and
        // `none` found no failing one. An empty `any` therefore never matches,
        // an empty `all`/`none` always does — which the validator warns about.
        let matched = decided ?? (group.mode != .any)
        var tests: [RuleTrace.TestOutcome] = []
        for index in group.items.indices {
            tests.append(outcomes[index])
            if let child = nested[index] { tests.append(contentsOf: child.tests) }
        }
        return GroupEvaluation(matched: matched, culpritIndex: culprit, tests: tests)
    }

    private static func fold(mode: ConditionGroup.Mode, passed: Bool, index: Int,
                             culprit: inout Int?, current: Bool?) -> Bool? {
        if current != nil { return current }
        switch mode {
        case .all: return passed ? nil : false
        case .any: return passed ? true : nil
        case .none:
            if passed { culprit = index; return false }
            return nil
        }
    }

    private static func capturesSomething(_ condition: Condition) -> Bool {
        switch condition {
        case .test(let test):
            return test.captureAs != nil || test.op == .matchesRegex
        case .group(let group):
            return group.items.contains(where: capturesSomething)
        }
    }

    private static func cost(of condition: Condition, context: Context) -> Int {
        switch condition {
        case .test(let test): return context.facts.cost(of: test.attribute).rawValue
        case .group(let group):
            return group.items.map { cost(of: $0, context: context) }.max() ?? 0
        }
    }

    private static func describe(_ value: ConditionValue) -> String {
        switch value {
        case .none: return ""
        case .text(let text): return text
        case .number(let number): return NumberText.canonical(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .list(let list): return list.joined(separator: ", ")
        }
    }
}
