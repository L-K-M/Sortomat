import Foundation

// MARK: - Condition values

/// Whatever the JSON held. The *operator* decides what type a test wants, and
/// `ValueCoercion` converts on demand — so a hand-written config can say
/// `"pdf"`, `25`, `["a","b"]`, `"30d"` or `"500MB"` and stay readable. A
/// failed coercion makes the test false with `verdict: .invalidValue`; nothing
/// throws, ever.
public enum ConditionValue: Equatable, Sendable, Codable {
    case none
    case text(String)
    case number(Double)
    case bool(Bool)
    case list([String])

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.singleValueContainer() {
            // Bool before String/Double, and String before Double, so that
            // "30d" stays text and "5" stays text rather than becoming 5.0.
            if container.decodeNil() { self = .none; return }
            if let value = try? container.decode(Bool.self) { self = .bool(value); return }
            if let value = try? container.decode(String.self) { self = .text(value); return }
            if let value = try? container.decode(Double.self) { self = .number(value); return }
            if let value = try? container.decode([String].self) { self = .list(value); return }
            if let value = try? container.decode([Double].self) {
                self = .list(value.map { NumberText.canonical($0) })
                return
            }
        }
        self = .none
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .none: try container.encodeNil()
        case .text(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .list(let value): try container.encode(value)
        }
    }

    public var isEmpty: Bool {
        switch self {
        case .none: return true
        case .text(let value): return value.isEmpty
        case .list(let value): return value.isEmpty
        case .number, .bool: return false
        }
    }
}

/// Formats a Double the way a human wrote it: `3` rather than `3.0`.
public enum NumberText {
    public static func canonical(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 {
            return String(Int64(value))
        }
        return String(value)
    }
}

// MARK: - The condition tree

public struct ConditionGroup: Equatable, Sendable, Codable, Identifiable {
    public enum Mode: String, Codable, Sendable, CaseIterable {
        case all, any, none
    }

    public var id: UUID
    public var mode: Mode
    public var items: [Condition]

    public init(id: UUID = UUID(), mode: Mode = .all, items: [Condition] = []) {
        self.id = id
        self.mode = mode
        self.items = items
    }

    private enum Keys: String, CodingKey { case id, mode, items, all, any, none }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: Keys.self) else {
            // Fail closed. `ConditionGroup()` is `.all` with no items, which is
            // vacuously true — so a `when` that is a string, an array or a
            // number (a typo in a hand-written config, the audience this
            // decoder exists for) became a step that claimed every file and
            // ran its `then` on all of them, silently. `.any` with no items
            // can never match, which is the safe reading of "unintelligible".
            self = ConditionGroup(mode: .any)
            return
        }
        id = ((try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        // Canonical form is {"mode":"all","items":[…]}; the sugar {"all":[…]}
        // exists so a hand-written config reads like the sentence it is.
        if let items = ((try? container.decodeIfPresent([Condition].self, forKey: .all)) ?? nil) {
            mode = .all
            self.items = items
            return
        }
        if let items = ((try? container.decodeIfPresent([Condition].self, forKey: .any)) ?? nil) {
            mode = .any
            self.items = items
            return
        }
        if let items = ((try? container.decodeIfPresent([Condition].self, forKey: .none)) ?? nil) {
            mode = .none
            self.items = items
            return
        }
        // A keyed container that names no group key at all is not a group —
        // `"when": {"attr":"kind","op":"is","value":"pdf"}` is a single test
        // written where a group belongs. Reaching the `mode` default here made
        // it an empty `.all`, which matches every file; fail closed instead.
        guard container.contains(.mode) || container.contains(.items) else {
            mode = .any
            items = []
            return
        }
        let raw = ((try? container.decodeIfPresent(String.self, forKey: .mode)) ?? nil) ?? ""
        // Case-folded: `"Any"` or `"NONE"` would otherwise fall back to `.all`
        // and widen the step into a catch-all — the fail-open direction, from
        // nothing worse than a capital letter. An absent mode is still `.all`,
        // which is the documented default.
        mode = raw.isEmpty ? .all : (Mode(rawValue: raw.lowercased()) ?? .all)
        items = ((try? container.decodeIfPresent([Condition].self, forKey: .items)) ?? nil) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        try container.encode(mode, forKey: .mode)
        try container.encode(items, forKey: .items)
    }
}

/// A group or a test. Discriminated on *shape* rather than a `"kind"` tag, so
/// the JSON stays short and writable by hand.
public indirect enum Condition: Equatable, Sendable, Codable, Identifiable {
    case group(ConditionGroup)
    case test(ConditionTest)

    public var id: UUID {
        switch self {
        case .group(let group): return group.id
        case .test(let test): return test.id
        }
    }

    private enum Keys: String, CodingKey { case mode, items, all, any, none }

    public init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: Keys.self),
           container.contains(.items) || container.contains(.all)
            || container.contains(.any) || container.contains(.none)
            || container.contains(.mode) {
            // `.mode` counts too: `{"mode":"all"}` with no items yet is a group
            // the writer spelled as a group, and reading it as a condition test
            // instead threw the shape away.
            self = .group((try? ConditionGroup(from: decoder)) ?? ConditionGroup(mode: .any))
        } else {
            self = .test((try? ConditionTest(from: decoder)) ?? ConditionTest())
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .group(let group): try group.encode(to: encoder)
        case .test(let test): try test.encode(to: encoder)
        }
    }
}

public struct ConditionTest: Equatable, Sendable, Codable, Identifiable {
    /// How a string comparison treats case. Insensitive by default, which is
    /// what today's engine does everywhere.
    public enum CaseSensitivity: String, Codable, Sendable, CaseIterable {
        case insensitive, sensitive
    }

    /// Which resolver decides a `kind` test. Migrated rules pin
    /// `.extensionTable` so their behaviour is byte-identical to the old
    /// engine; anything new uses Launch Services.
    public enum KindSource: String, Codable, Sendable, CaseIterable {
        case utType, extensionTable, either
    }

    public var id: UUID
    public var attribute: Attribute
    public var op: Operator
    public var value: ConditionValue
    public var caseSensitivity: CaseSensitivity
    public var kindSource: KindSource
    /// Names this test's regex/glob captures, so two capturing conditions in
    /// one step can never collide: `{match.<label>.<group>}`.
    public var captureAs: String?

    public init(id: UUID = UUID(),
                attribute: Attribute = .name,
                op: Operator = .contains,
                value: ConditionValue = .none,
                caseSensitivity: CaseSensitivity = .insensitive,
                kindSource: KindSource = .utType,
                captureAs: String? = nil) {
        self.id = id
        self.attribute = attribute
        self.op = op
        self.value = value
        self.caseSensitivity = caseSensitivity
        self.kindSource = kindSource
        self.captureAs = captureAs
    }

    private enum Keys: String, CodingKey {
        case id, attribute, attr, op, value, caseSensitivity, kindSource, captureAs
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: Keys.self) else {
            self = ConditionTest()
            return
        }
        id = ((try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        // "attr" is the short spelling a hand-written config may use.
        let decoded = ((try? container.decodeIfPresent(Attribute.self, forKey: .attribute)) ?? nil)
            ?? ((try? container.decodeIfPresent(Attribute.self, forKey: .attr)) ?? nil)
        attribute = decoded ?? .name
        op = ((try? container.decodeIfPresent(Operator.self, forKey: .op)) ?? nil) ?? .contains
        value = ((try? container.decodeIfPresent(ConditionValue.self, forKey: .value)) ?? nil) ?? .none
        let sensitivity = ((try? container.decodeIfPresent(String.self, forKey: .caseSensitivity)) ?? nil) ?? ""
        caseSensitivity = CaseSensitivity(rawValue: sensitivity) ?? .insensitive
        let source = ((try? container.decodeIfPresent(String.self, forKey: .kindSource)) ?? nil) ?? ""
        kindSource = KindSource(rawValue: source) ?? .utType
        captureAs = ((try? container.decodeIfPresent(String.self, forKey: .captureAs)) ?? nil) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        try container.encode(attribute, forKey: .attribute)
        try container.encode(op, forKey: .op)
        try container.encode(value, forKey: .value)
        try container.encode(caseSensitivity, forKey: .caseSensitivity)
        try container.encode(kindSource, forKey: .kindSource)
        try container.encodeIfPresent(captureAs, forKey: .captureAs)
    }
}
