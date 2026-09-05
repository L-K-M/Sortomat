import Foundation

/// Something done to the file *after* it has been placed: a tag, a comment, a
/// notification. Kept separate from the placement so a failed move never
/// leaves a half-applied side effect behind.
public struct SideEffect: Equatable, Sendable {
    public var type: ActionType
    /// Already rendered.
    public var values: [String]

    public init(type: ActionType, values: [String]) {
        self.type = type
        self.values = values
    }
}

/// What the engine decided. Still relative and unsanitized: `Sanitizer` and
/// `Mover` remain the only things that turn this into an actual path and an
/// actual byte move.
public struct Placement: Equatable, Sendable {
    public enum Operation: String, Equatable, Sendable {
        case move, copy, rename, trash, skip, quarantine
    }

    public var operation: Operation
    /// Rendered, relative to `rootPath`. nil for skip and trash.
    public var relativePath: RenderedTemplate?
    /// The absolute root the relative path resolves against: the rule's target
    /// folder, one of `rule.destinationRoots`, or — for a rename — the file's
    /// own folder. `Sanitizer.destination` still confines the result inside it.
    public var rootPath: String?
    public var sideEffects: [SideEffect]
    public var origin: PlannedAction.Origin
    public var reason: String
    public var confidence: Double?

    public init(operation: Operation,
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
public struct CaptureStore: Equatable, Sendable {
    private var values: [String: String] = [:]

    public init() {}

    public mutating func record(_ captures: [String: String], label: String?) {
        for (key, value) in captures {
            values[key] = value
            if let label { values["\(label).\(key)"] = value }
        }
    }

    public func value(forKey key: String) -> String? { values[key] }

    public var isEmpty: Bool { values.isEmpty }
}
