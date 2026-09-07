import Foundation

/// Where Sortomat keeps its config, logs, move journal and dedup ledger, and how
/// it loads/saves the rule set. The directory can be overridden for tests and
/// headless runs via `SORTOMAT_CONFIG_DIR`.
enum ConfigStore {
    static var directory: URL {
        if let override = ProcessInfo.processInfo.environment["SORTOMAT_CONFIG_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return appSupport.appendingPathComponent("Sortomat", isDirectory: true)
    }

    static var configFile: URL { directory.appendingPathComponent("config.json") }
    static var logFile: URL { directory.appendingPathComponent("activity.log") }
    static var journalFile: URL { directory.appendingPathComponent("journal.jsonl") }
    static var ledgerFile: URL { directory.appendingPathComponent("ledger.json") }
    static var memoFile: URL { directory.appendingPathComponent("memo.json") }
    static var spendFile: URL { directory.appendingPathComponent("spend.json") }

    /// One shared, lock-guarded formatter: `ISO8601DateFormatter` is not
    /// documented thread-safe, and allocating a fresh one per log line was
    /// pure waste on the main actor's hot path.
    private static let stampLock = NSLock()
    private static let stampFormatter = ISO8601DateFormatter()
    static func timestamp(for date: Date = Date()) -> String {
        stampLock.lock()
        defer { stampLock.unlock() }
        return stampFormatter.string(from: date)
    }

    /// Load the config, seeding a disabled example rule on first launch. Decoding
    /// is tolerant (every field defaults if missing), so upgrading the schema
    /// never silently wipes a user's rules — and an *undecodable* file (torn
    /// write, disk-full, hand-edit gone wrong) is preserved as a timestamped
    /// backup instead of being replaced by an empty config on the next save.
    static func load(from file: URL = configFile) -> Config {
        guard let data = try? Data(contentsOf: file) else {
            var config = Config()
            // The rule a brand-new user finds should be one that works. The
            // e-book template that used to be seeded here cannot do anything at
            // all without an API key, so a first launch offered a rule that was
            // guaranteed to sit there doing nothing; the tidy-up template is
            // entirely deterministic. Both are still in the gallery.
            config.rules = [RuleTemplate.tidy.makeRule()]
            save(config)
            return config
        }
        do {
            return try JSONDecoder().decode(Config.self, from: data)
        } catch {
            backUpCorruptConfig(data, of: file)
            return Config()
        }
    }

    /// Keep the evidence: `config.json.corrupt-<timestamp>` next to the config,
    /// plus a loud line in the activity log. The user's rules may well be
    /// recoverable from the backup by hand.
    private static func backUpCorruptConfig(_ data: Data, of file: URL) {
        let stamp = timestamp().replacingOccurrences(of: ":", with: "-")
        let backup = file.deletingLastPathComponent()
            .appendingPathComponent("\(file.lastPathComponent).corrupt-\(stamp)")
        try? data.write(to: backup)
        appendLog("ERROR: \(file.lastPathComponent) could not be decoded; "
            + "kept a copy at \(backup.lastPathComponent) and started with an empty config.")
    }

    static func save(_ config: Config) {
        ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configFile, options: .atomic)
        }
    }

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
    }

    /// Rotate at ~5 MB, keeping one previous generation — the log was
    /// append-only forever.
    static let maxLogBytes: Int64 = 5 * 1024 * 1024

    /// Serializes the whole append, rotation included: `appendLog` is called
    /// from the Pipeline actor and the main actor, and a rotation that renames
    /// the file out from under another thread's open handle sends that line to
    /// the rotated-away generation.
    private static let logLock = NSLock()

    static func appendLog(_ line: String) {
        logLock.lock()
        defer { logLock.unlock() }
        ensureDirectory()
        rotateLogIfNeeded()
        let entry = "\(timestamp())  \(line)\n"
        if let handle = try? FileHandle(forWritingTo: logFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(entry.utf8))
        } else {
            try? Data(entry.utf8).write(to: logFile)
        }
    }

    private static func rotateLogIfNeeded() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: logFile.path))?[.size] as? Int64,
              size >= maxLogBytes else { return }
        let previous = logFile.appendingPathExtension("1")
        try? fm.removeItem(at: previous)
        do {
            try fm.moveItem(at: logFile, to: previous)
        } catch {
            // If the previous generation is held open the move fails, and a
            // swallowed failure means the cap silently stops applying.
            Log.app.error("log rotation failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
