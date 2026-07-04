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

    /// Load the config, seeding a disabled example rule on first launch. Decoding
    /// is tolerant (every field defaults if missing), so upgrading the schema
    /// never silently wipes a user's rules.
    static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile) else {
            var config = Config()
            config.rules = [RuleTemplate.ebooks.makeRule()]
            save(config)
            return config
        }
        return (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
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

    static func appendLog(_ line: String) {
        ensureDirectory()
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
}
