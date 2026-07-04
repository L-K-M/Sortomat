import Foundation

struct Rule: Codable, Identifiable, Equatable {
    var id = UUID()
    var name = "Neue Regel"
    var watchPath = ""
    var targetPath = ""
    var prompt = ""
    /// Lowercase extensions without dot; empty list = all files.
    var extensions: [String] = []
    var copyInsteadOfMove = false
    var enabled = true
}

struct Config: Codable, Equatable {
    var rules: [Rule] = []
    var model = "mistral-small-latest"
    var apiBase = "https://api.mistral.ai"
    var scanIntervalSeconds: Double = 60

    static let sampleEbookPrompt = """
    Diese Regel sortiert E-Books (EPUB). Zielstruktur: {Genre}/{Nachname, Vorname}/{Titel}.epub

    Das Genre MUSS eines der folgenden sein: Abenteuer, Belletristik, Comic & Manga, \
    Erotik, Fantasy, Historischer Roman, Horror, Humor & Satire, Kinder- & Jugendbuch, \
    Klassiker, Krimi & Thriller, Kurzgeschichten, Liebesroman, Lyrik & Drama, \
    Märchen & Sagen, Science-Fiction, Biografie & Memoiren, Geschichte, \
    Gesundheit & Ernährung, Kochbuch, Kunst & Kultur, Philosophie, \
    Politik & Gesellschaft, Ratgeber & Selbsthilfe, Reise, Religion & Spiritualität, \
    Sachbuch, True Crime, Wirtschaft & Finanzen, Wissenschaft & Technik, Unbekannt.

    Autor als "Nachname, Vorname". Titel ohne Reihennummern-Präfixe wie "01 - ".
    Dateien, die keine E-Books sind, überspringen.
    """
}

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

    static func load() -> Config {
        guard let data = try? Data(contentsOf: configFile) else {
            // First launch: provide a disabled example rule as a template.
            var config = Config()
            var example = Rule()
            example.name = "Beispiel: E-Books sortieren"
            example.prompt = Config.sampleEbookPrompt
            example.extensions = ["epub"]
            example.enabled = false
            config.rules = [example]
            save(config)
            return config
        }
        return (try? JSONDecoder().decode(Config.self, from: data)) ?? Config()
    }

    static func save(_ config: Config) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(config) {
            try? data.write(to: configFile, options: .atomic)
        }
    }

    static func appendLog(_ line: String) {
        try? FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true
        )
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
