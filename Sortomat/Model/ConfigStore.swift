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

    /// Load the config, seeding a disabled example rule on first launch. Decoding
    /// is tolerant (every field defaults if missing), so upgrading the schema
    /// never silently wipes a user's rules — and an *undecodable* file (torn
    /// write, disk-full, hand-edit gone wrong) is preserved as a timestamped
    /// backup instead of being replaced by an empty config on the next save.
    static func load(from file: URL = configFile) -> Config {
        guard let data = try? Data(contentsOf: file) else {
            var config = Config()
            config.rules = [RuleTemplate.ebooks.makeRule()]
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
        let stamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
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

    static func appendLog(_ line: String) {
        ensureDirectory()
        rotateLogIfNeeded()
        let stamp = ISO8601DateFormatter().string(from: Date())
        let entry = "\(stamp)  \(line)\n"
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
        try? fm.moveItem(at: logFile, to: previous)
    }
}
