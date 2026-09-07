import Foundation

/// Something done to the file *after* it has been placed: a tag, a comment, a
/// notification. Kept separate from the placement so a failed move never
/// leaves a half-applied side effect behind.
struct SideEffect: Equatable, Sendable {
    var type: ActionType
    /// Already rendered.
    var values: [String]

    init(type: ActionType, values: [String]) {
        self.type = type
        self.values = values
    }
}

/// What the engine decided. Still relative and unsanitized: `Sanitizer` and
/// `Mover` remain the only things that turn this into an actual path and an
/// actual byte move.
struct Placement: Equatable, Sendable {
    enum Operation: String, Equatable, Sendable {
        case move, copy, rename, trash, skip, quarantine
    }

    var operation: Operation
    /// Rendered, relative to `rootPath`. nil for skip and trash.
    var relativePath: RenderedTemplate?
    /// The absolute root the relative path resolves against: the rule's target
    /// folder, one of `rule.destinationRoots`, or — for a rename — the file's
    /// own folder. `Sanitizer.destination` still confines the result inside it.
    var rootPath: String?
    var sideEffects: [SideEffect]
    var origin: PlannedAction.Origin
    var reason: String
    var confidence: Double?

    init(operation: Operation,
                relativePath: RenderedTemplate? = nil,
                rootPath: String? = nil,
                sideEffects: [SideEffect] = [],
                origin: PlannedAction.Origin = .step,
                reason: String = "",
                confidence: Double? = nil) {
        self.operation = operation
        self.relativePath = relativePath
        self.rootPath = rootPath
        self.sideEffects = sideEffects
        self.origin = origin
        self.reason = reason
        self.confidence = confidence
    }
}

/// Captures harvested from matching conditions, so a destination can use what
/// a pattern found: `Finanzen/{match.year}/{match.vendor}`.
///
/// A condition with `captureAs: "invoice"` publishes `{match.invoice.1}` as
/// well as the unlabelled `{match.1}`, so two capturing conditions in one step
/// can never quietly overwrite each other.
struct CaptureStore: Equatable, Sendable {
    private var values: [String: String] = [:]

    init() {}

    mutating func record(_ captures: [String: String], label: String?) {
        for (key, value) in captures {
            values[key] = value
            if let label { values["\(label).\(key)"] = value }
        }
    }

    func value(forKey key: String) -> String? { values[key] }

    var isEmpty: Bool { values.isEmpty }
}
