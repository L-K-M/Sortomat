import Foundation

// MARK: - Privacy

/// How much of a file we are willing to send to the model.
public enum PrivacyMode: String, Codable, CaseIterable, Sendable {
    /// Name, metadata and a content excerpt.
    case full
    /// Name and metadata only — contents never leave the machine.
    case metadataOnly
}

// MARK: - Deterministic pre-rules

/// A deterministic rule evaluated *before* the LLM. Predictable, free, and it
/// keeps the common case off the paid/non-deterministic path (PLAN Phase 5).
public struct PreRule: Codable, Identifiable, Equatable, Sendable {
    public enum Match: String, Codable, CaseIterable, Sendable {
        /// Shell-style glob against the file name, e.g. `IMG_*.jpg`.
        case glob
        /// Regular expression against the file name.
        case regex
        /// A coarse content kind: `image`, `video`, `audio`, `pdf`, `archive`,
        /// `text`, `ebook`, `document`. Matched via file extension.
        case kind
        /// File age: pattern is a number of days; matches files *older* than that.
        case olderThanDays
        /// File age: pattern is a number of days; matches files *newer* than that.
        case newerThanDays
    }

    public enum Action: String, Codable, CaseIterable, Sendable {
        /// Route the file to `routePath` (relative to the rule target), no LLM call.
        case route
        /// Skip the file entirely (never sort it).
        case skip
        /// Hand the file to the LLM (the default fall-through).
        case useLLM
    }

    public var id: UUID
    public var name: String
    public var match: Match
    /// Glob/regex string, coarse kind, or a number of days depending on `match`.
    public var pattern: String
    public var action: Action
    /// Destination template used when `action == .route`. Supports the tokens
    /// `{name}`, `{ext}`, `{year}`, `{month}`, `{day}`.
    public var routePath: String

    public init(
        id: UUID = UUID(),
        name: String = "",
        match: Match = .glob,
        pattern: String = "",
        action: Action = .route,
        routePath: String = ""
    ) {
        self.id = id
        self.name = name
        self.match = match
        self.pattern = pattern
        self.action = action
        self.routePath = routePath
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        match = try c.decodeIfPresent(Match.self, forKey: .match) ?? .glob
        pattern = try c.decodeIfPresent(String.self, forKey: .pattern) ?? ""
        action = try c.decodeIfPresent(Action.self, forKey: .action) ?? .route
        routePath = try c.decodeIfPresent(String.self, forKey: .routePath) ?? ""
    }
}

// MARK: - Rule

/// One watched folder + how to file its new contents away.
public struct Rule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var enabled: Bool
    /// Higher priority rules claim a file first when several rules match it.
    public var priority: Int
    public var watchPath: String
    public var targetPath: String
    /// Watch (and scan) subfolders too.
    public var recursive: Bool
    /// The natural-language sorting instruction.
    public var prompt: String
    /// Lowercase extensions without a dot; empty = all files.
    public var extensions: [String]
    public var copyInsteadOfMove: Bool
    public var privacyMode: PrivacyMode
    /// Deterministic pre-rules, evaluated in order before any LLM call.
    public var preRules: [PreRule]
    /// If non-empty, the model's top-level destination folder is constrained to
    /// this enumerated set (kills a whole class of invented-path mis-sorts).
    public var taxonomy: [String]
    /// Bucket for files whose taxonomy folder is out of set, or whose confidence
    /// is below `confidenceThreshold`. Relative to the target folder.
    public var quarantineSubfolder: String
    /// 0 disables the check; otherwise a classification below this confidence is
    /// routed to `quarantineSubfolder` instead of being filed.
    public var confidenceThreshold: Double
    /// New rules preview (never touch files) until the user disables this.
    public var dryRun: Bool

    public init(
        id: UUID = UUID(),
        name: String = "Neue Regel",
        enabled: Bool = true,
        priority: Int = 0,
        watchPath: String = "",
        targetPath: String = "",
        recursive: Bool = false,
        prompt: String = "",
        extensions: [String] = [],
        copyInsteadOfMove: Bool = false,
        privacyMode: PrivacyMode = .full,
        preRules: [PreRule] = [],
        taxonomy: [String] = [],
        quarantineSubfolder: String = "_Quarantäne",
        confidenceThreshold: Double = 0,
        dryRun: Bool = false
    ) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.priority = priority
        self.watchPath = watchPath
        self.targetPath = targetPath
        self.recursive = recursive
        self.prompt = prompt
        self.extensions = extensions
        self.copyInsteadOfMove = copyInsteadOfMove
        self.privacyMode = privacyMode
        self.preRules = preRules
        self.taxonomy = taxonomy
        self.quarantineSubfolder = quarantineSubfolder
        self.confidenceThreshold = confidenceThreshold
        self.dryRun = dryRun
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Neue Regel"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        watchPath = try c.decodeIfPresent(String.self, forKey: .watchPath) ?? ""
        targetPath = try c.decodeIfPresent(String.self, forKey: .targetPath) ?? ""
        recursive = try c.decodeIfPresent(Bool.self, forKey: .recursive) ?? false
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt) ?? ""
        extensions = try c.decodeIfPresent([String].self, forKey: .extensions) ?? []
        copyInsteadOfMove = try c.decodeIfPresent(Bool.self, forKey: .copyInsteadOfMove) ?? false
        privacyMode = try c.decodeIfPresent(PrivacyMode.self, forKey: .privacyMode) ?? .full
        preRules = try c.decodeIfPresent([PreRule].self, forKey: .preRules) ?? []
        taxonomy = try c.decodeIfPresent([String].self, forKey: .taxonomy) ?? []
        quarantineSubfolder = try c.decodeIfPresent(String.self, forKey: .quarantineSubfolder) ?? "_Quarantäne"
        confidenceThreshold = try c.decodeIfPresent(Double.self, forKey: .confidenceThreshold) ?? 0
        dryRun = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
    }
}

// MARK: - Config

public struct Config: Codable, Equatable, Sendable {
    public var rules: [Rule]
    public var model: String
    public var apiBase: String
    /// Local backends (Ollama / LM Studio) need no key.
    public var providerRequiresKey: Bool
    /// USD per 1M tokens, used only to surface an estimated spend.
    public var inputPricePerMTok: Double
    public var outputPricePerMTok: Double
    public var scanIntervalSeconds: Double
    /// Upper bound on files classified concurrently (Phase 3 throttle).
    public var maxConcurrentClassifications: Int
    /// Max LLM calls per scan pass; 0 = unlimited.
    public var perScanBudget: Int
    public var notificationsEnabled: Bool

    public init(
        rules: [Rule] = [],
        model: String = "mistral-small-latest",
        apiBase: String = "https://api.mistral.ai",
        providerRequiresKey: Bool = true,
        inputPricePerMTok: Double = 0.2,
        outputPricePerMTok: Double = 0.6,
        scanIntervalSeconds: Double = 60,
        maxConcurrentClassifications: Int = 2,
        perScanBudget: Int = 0,
        notificationsEnabled: Bool = true
    ) {
        self.rules = rules
        self.model = model
        self.apiBase = apiBase
        self.providerRequiresKey = providerRequiresKey
        self.inputPricePerMTok = inputPricePerMTok
        self.outputPricePerMTok = outputPricePerMTok
        self.scanIntervalSeconds = scanIntervalSeconds
        self.maxConcurrentClassifications = maxConcurrentClassifications
        self.perScanBudget = perScanBudget
        self.notificationsEnabled = notificationsEnabled
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? []
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "mistral-small-latest"
        apiBase = try c.decodeIfPresent(String.self, forKey: .apiBase) ?? "https://api.mistral.ai"
        providerRequiresKey = try c.decodeIfPresent(Bool.self, forKey: .providerRequiresKey) ?? true
        inputPricePerMTok = try c.decodeIfPresent(Double.self, forKey: .inputPricePerMTok) ?? 0.2
        outputPricePerMTok = try c.decodeIfPresent(Double.self, forKey: .outputPricePerMTok) ?? 0.6
        scanIntervalSeconds = try c.decodeIfPresent(Double.self, forKey: .scanIntervalSeconds) ?? 60
        maxConcurrentClassifications = try c.decodeIfPresent(Int.self, forKey: .maxConcurrentClassifications) ?? 2
        perScanBudget = try c.decodeIfPresent(Int.self, forKey: .perScanBudget) ?? 0
        notificationsEnabled = try c.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
    }
}
