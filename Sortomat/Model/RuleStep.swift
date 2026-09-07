import Foundation

/// One "if … then …" inside a rule. Steps run in order and the first one whose
/// `when` matches claims the file, unless one of its actions says `continue`.
public struct RuleStep: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    public var when: ConditionGroup
    public var then: [RuleAction]

    public init(id: UUID = UUID(),
                name: String = "",
                enabled: Bool = true,
                when: ConditionGroup = ConditionGroup(mode: .all, items: []),
                then: [RuleAction] = []) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.when = when
        self.then = then
    }

    public init(from decoder: Decoder) throws {
        // Fail closed, the same way `ConditionGroup` does. `RuleStep()` carries
        // the *editor's* default — `.all` with no items, which is vacuously
        // true — so an unintelligible step claimed every file the rule saw.
        // `.any` with no items can never match, which is the safe reading.
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = RuleStep(when: ConditionGroup(mode: .any))
            return
        }
        id = ((try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        enabled = ((try? container.decodeIfPresent(Bool.self, forKey: .enabled)) ?? nil) ?? true
        // An absent `when` is the same question as an unintelligible one, and
        // was the one path still failing open: `{"name":"PDFs","then":[…]}` —
        // the shape a hand-written config gets wrong — ran its `then` on every
        // file. The memberwise default stays `.all`: a step the *editor* has
        // just added has no conditions yet, and the validator says so.
        when = ((try? container.decodeIfPresent(ConditionGroup.self, forKey: .when)) ?? nil)
            ?? ConditionGroup(mode: .any)
        then = ((try? container.decodeIfPresent([RuleAction].self, forKey: .then)) ?? nil) ?? []
    }

    /// Whether this step ever places a file (as opposed to only tagging it and
    /// continuing). Used by the validator and by the summary sentence.
    public var placement: RuleAction? {
        then.first { ActionType.placements.contains($0.type) }
    }
}

/// An action is a struct with a typed payload rather than a tagged enum with
/// hand-written `Codable`: it decodes tolerantly by construction, an unknown
/// type survives a re-save untouched, and the editor can be data-driven.
public struct RuleAction: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var type: ActionType
    /// The one template most actions need: a destination path, a new file
    /// name, comment text, a notification body, a Shortcut name.
    public var template: String
    /// Tags for `addTags`/`removeTags`; the colour name for `setLabel`.
    public var tags: [String]
    /// Which folder `template` is relative to. nil means the rule's target.
    public var root: String?
    /// Per-action overrides for `askModel`; nil everywhere else.
    public var model: ModelStepOptions?

    public init(id: UUID = UUID(),
                type: ActionType = .move,
                template: String = "",
                tags: [String] = [],
                root: String? = nil,
                model: ModelStepOptions? = nil) {
        self.id = id
        self.type = type
        self.template = template
        self.tags = tags
        self.root = root
        self.model = model
    }

    private enum Keys: String, CodingKey { case id, type, template, to, tags, root, model }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: Keys.self) else {
            self = RuleAction(type: .skip)
            return
        }
        id = ((try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        type = ((try? container.decodeIfPresent(ActionType.self, forKey: .type)) ?? nil) ?? .unknown
        // "to" is the readable spelling for a destination; "template" the canonical one.
        template = ((try? container.decodeIfPresent(String.self, forKey: .template)) ?? nil)
            ?? ((try? container.decodeIfPresent(String.self, forKey: .to)) ?? nil) ?? ""
        tags = ((try? container.decodeIfPresent([String].self, forKey: .tags)) ?? nil) ?? []
        root = ((try? container.decodeIfPresent(String.self, forKey: .root)) ?? nil) ?? nil
        model = ((try? container.decodeIfPresent(ModelStepOptions.self, forKey: .model)) ?? nil) ?? nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(template, forKey: .template)
        try container.encode(tags, forKey: .tags)
        try container.encodeIfPresent(root, forKey: .root)
        try container.encodeIfPresent(model, forKey: .model)
    }
}

/// Per-action overrides for the model. All-nil means exactly today's
/// behaviour: the rule's own prompt, taxonomy, privacy mode and threshold.
public struct ModelStepOptions: Codable, Equatable, Sendable {
    public var prompt: String?
    public var taxonomy: [String]?
    public var privacyMode: PrivacyMode?
    public var confidenceThreshold: Double?
    /// Only for the `modelSays` condition: the yes/no question to ask.
    public var question: String?

    public init(prompt: String? = nil,
                taxonomy: [String]? = nil,
                privacyMode: PrivacyMode? = nil,
                confidenceThreshold: Double? = nil,
                question: String? = nil) {
        self.prompt = prompt
        self.taxonomy = taxonomy
        self.privacyMode = privacyMode
        self.confidenceThreshold = confidenceThreshold
        self.question = question
    }

    private enum Keys: String, CodingKey {
        case prompt, taxonomy, privacyMode, confidenceThreshold, question
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: Keys.self) else {
            self = ModelStepOptions()
            return
        }
        prompt = ((try? container.decodeIfPresent(String.self, forKey: .prompt)) ?? nil) ?? nil
        taxonomy = ((try? container.decodeIfPresent([String].self, forKey: .taxonomy)) ?? nil) ?? nil
        let mode = ((try? container.decodeIfPresent(String.self, forKey: .privacyMode)) ?? nil) ?? nil
        privacyMode = mode.flatMap { PrivacyMode(rawValue: $0) }
        confidenceThreshold = ((try? container.decodeIfPresent(Double.self, forKey: .confidenceThreshold)) ?? nil) ?? nil
        question = ((try? container.decodeIfPresent(String.self, forKey: .question)) ?? nil) ?? nil
    }
}

/// A named folder an action may target besides the rule's own target folder.
/// A destination can only ever leave the target folder through a root the user
/// typed here, and `Sanitizer.destination` still confines the rendered path
/// inside whichever root was chosen.
public struct DestinationRoot: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var path: String

    public init(id: UUID = UUID(), name: String = "", path: String = "") {
        self.id = id
        self.name = name
        self.path = path
    }

    public init(from decoder: Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
            self = DestinationRoot()
            return
        }
        id = ((try? container.decodeIfPresent(UUID.self, forKey: .id)) ?? nil) ?? UUID()
        name = ((try? container.decodeIfPresent(String.self, forKey: .name)) ?? nil) ?? ""
        path = ((try? container.decodeIfPresent(String.self, forKey: .path)) ?? nil) ?? ""
    }
}
