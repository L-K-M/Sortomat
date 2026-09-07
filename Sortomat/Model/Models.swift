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
        name: String = L10n.t("rule.defaultName"),
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
        quarantineSubfolder: String = L10n.t("rule.defaultQuarantine"),
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
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? L10n.t("rule.defaultName")
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
        quarantineSubfolder = try c.decodeIfPresent(String.self, forKey: .quarantineSubfolder) ?? L10n.t("rule.defaultQuarantine")
        confidenceThreshold = try c.decodeIfPresent(Double.self, forKey: .confidenceThreshold) ?? 0
        dryRun = try c.decodeIfPresent(Bool.self, forKey: .dryRun) ?? false
    }
}

public extension [Rule] {
    /// Enabled rules, highest priority first, so a higher-priority rule claims
    /// a contested file before a lower one — the behavior `Rule.priority`
    /// documents and the editor's stepper promises. Equal priorities keep the
    /// list order via an explicit index tiebreak: Swift's `sorted` does not
    /// guarantee stability, so relying on it would let rule order drift with
    /// the toolchain. Shared by the GUI scan loop and the headless runner.
    func inExecutionOrder() -> [Rule] {
        enumerated()
            .filter { $0.element.enabled }
            .sorted { lhs, rhs in
                if lhs.element.priority != rhs.element.priority {
                    return lhs.element.priority > rhs.element.priority
                }
                return lhs.offset < rhs.offset
            }
            .map(\.element)
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
    /// Emergency brake, persisted. A pause pulled at 23:00 because a rule is
    /// misfiling used to be released by the next launch — including the
    /// relaunch the update checker itself offers.
    public var paused: Bool
    /// Ceiling on estimated spend for the calendar month, in `currencyCode`;
    /// 0 = no ceiling. The per-pass budget caps a *burst*; at the default 60 s
    /// interval, a folder that keeps producing unclassifiable files bills up to
    /// 14 400 calls a day within it.
    public var monthlyBudget: Double
    /// ISO 4217 code the price fields are quoted in. The meter used to be
    /// `String(format: "$%.4f")` — a dollar sign, in front, with a decimal
    /// point, for a user who may be paying in EUR or running a free local model.
    public var currencyCode: String {
        // `NumberFormatter.currencyCode` wants an uppercase ISO 4217 code, and
        // the settings field is free text: "eur" typed in lower case would
        // otherwise fall back to the locale's own currency and print a symbol
        // for money the user isn't paying. (A `didSet` reassignment does not
        // recurse in Swift.)
        didSet { currencyCode = currencyCode.uppercased() }
    }
    /// Skip automatic passes while running on battery. A preview the user
    /// asked for still runs: they are standing at the machine, and an explicit
    /// request that silently does nothing is worse than the battery it saves.
    public var onlyOnPower: Bool
    /// Don't scan while macOS is in Low Power Mode.
    public var pauseInLowPowerMode: Bool

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
        notificationsEnabled: Bool = true,
        paused: Bool = false,
        monthlyBudget: Double = 0,
        // A fresh config guesses from where the machine is; the *decode*
        // default below stays "USD" so an existing config never shifts.
        currencyCode: String = Locale.current.currency?.identifier ?? "USD",
        onlyOnPower: Bool = false,
        pauseInLowPowerMode: Bool = true
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
        self.paused = paused
        self.monthlyBudget = monthlyBudget
        self.currencyCode = currencyCode
        self.onlyOnPower = onlyOnPower
        self.pauseInLowPowerMode = pauseInLowPowerMode
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
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
        monthlyBudget = try c.decodeIfPresent(Double.self, forKey: .monthlyBudget) ?? 0
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? "USD"
        onlyOnPower = try c.decodeIfPresent(Bool.self, forKey: .onlyOnPower) ?? false
        // Default on: the setting only does anything while the user has
        // explicitly asked macOS to conserve power, and doing the most
        // expensive possible work then is what nobody wants.
        pauseInLowPowerMode = try c.decodeIfPresent(Bool.self, forKey: .pauseInLowPowerMode) ?? true
    }
}
