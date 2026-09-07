import Foundation

/// Why a condition did or did not hold.
///
/// A named reason for every failure, rather than one `false`, is the difference
/// between "why didn't my photo rule fire?" being answerable at a glance and
/// being a support thread: a photo with no EXIF date and a photo taken in 2019
/// are not the same answer.
public enum Verdict: String, Codable, Equatable, Sendable {
    case pass
    case fail               // the fact exists and does not satisfy the operator
    case unavailable        // the fact does not exist for this file
    case blockedByPrivacy   // a content-tier fact under metadataOnly
    case tooExpensive       // over a size cap
    case invalidValue       // the value could not be coerced to the operator's type
    case invalidPattern     // a bad glob, or a regex the safety check rejects
    case unknownAttribute
    case unknownOperator
    case notEvaluated       // short-circuited away
    case needsModel

    public var passed: Bool { self == .pass }
}

/// The record of one decision: every condition that was evaluated, what value
/// was actually found, and what the engine did about it.
public struct RuleTrace: Codable, Equatable, Sendable {
    public struct TestOutcome: Codable, Equatable, Sendable {
        public var path: String
        public var attribute: String
        public var op: String
        public var expected: String
        /// The value actually found, truncated — the activity log must never
        /// become a copy of the user's documents.
        public var actual: String?
        public var verdict: Verdict
        public var cost: String

        public init(path: String, attribute: String, op: String, expected: String,
                    actual: String?, verdict: Verdict, cost: String) {
            self.path = path
            self.attribute = attribute
            self.op = op
            self.expected = expected
            self.actual = actual
            self.verdict = verdict
            self.cost = cost
        }
    }

    public struct StepOutcome: Codable, Equatable, Sendable {
        public var stepID: UUID
        public var index: Int
        public var name: String
        public var matched: Bool
        /// For a `none` group: which member was true, and therefore why the
        /// group failed. The one place a *passing* condition is the reason.
        public var culpritIndex: Int?
        public var tests: [TestOutcome]
        public var actions: [String]

        public init(stepID: UUID, index: Int, name: String, matched: Bool,
                    culpritIndex: Int? = nil, tests: [TestOutcome] = [],
                    actions: [String] = []) {
            self.stepID = stepID
            self.index = index
            self.name = name
            self.matched = matched
            self.culpritIndex = culpritIndex
            self.tests = tests
            self.actions = actions
        }
    }

    public var ruleID: UUID
    public var ruleName: String
    public var timeZone: String
    public var steps: [StepOutcome]
    public var fallbackUsed: Rule.Fallback?
    public var model: ModelTrace?
    /// `[[template, result], …]` — arrays rather than tuples, so it stays Codable.
    public var renderedTemplates: [[String]]
    public var summary: String

    public init(ruleID: UUID, ruleName: String, timeZone: String,
                steps: [StepOutcome] = [], fallbackUsed: Rule.Fallback? = nil,
                model: ModelTrace? = nil, renderedTemplates: [[String]] = [],
                summary: String = "") {
        self.ruleID = ruleID
        self.ruleName = ruleName
        self.timeZone = timeZone
        self.steps = steps
        self.fallbackUsed = fallbackUsed
        self.model = model
        self.renderedTemplates = renderedTemplates
        self.summary = summary
    }
}

/// What the model contributed. Never the prompt itself, and never the file's
/// text — `Log.swift`'s rule (never log file contents or the key) applies to
/// the trace too.
public struct ModelTrace: Codable, Equatable, Sendable {
    public var promptHash: String
    public var memoHit: Bool
    public var taxonomyEnforced: Bool
    public var confidence: Double?
    public var quarantined: Bool
    public var reason: String?

    public init(promptHash: String, memoHit: Bool = false, taxonomyEnforced: Bool = false,
                confidence: Double? = nil, quarantined: Bool = false, reason: String? = nil) {
        self.promptHash = promptHash
        self.memoHit = memoHit
        self.taxonomyEnforced = taxonomyEnforced
        self.confidence = confidence
        self.quarantined = quarantined
        self.reason = reason
    }
}
