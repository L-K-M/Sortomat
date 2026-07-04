import Foundation

struct ActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let ok: Bool
    let message: String
}

/// Serializes all file processing. Remembers files the LLM skipped and files
/// that failed, so folders aren't re-classified on every scan.
actor Pipeline {
    /// Extensions of files that are still being written by other apps.
    private static let partialExtensions: Set<String> = [
        "download", "crdownload", "part", "partial", "tmp",
    ]

    private var skipped: Set<String> = []
    private var failedUntil: [String: Date] = [:]
    private let failRetryInterval: TimeInterval = 1800

    func scan(rule: Rule, config: Config, apiKey: String) async -> [ActivityEntry] {
        guard rule.enabled else { return [] }
        let watch = URL(fileURLWithPath: (rule.watchPath as NSString).expandingTildeInPath)
        let target = URL(fileURLWithPath: (rule.targetPath as NSString).expandingTildeInPath)
        guard !rule.watchPath.isEmpty, !rule.targetPath.isEmpty else { return [] }

        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: watch.path, isDirectory: &isDir),
              isDir.boolValue
        else {
            return [entry(false, "[\(rule.name)] Überwachter Ordner fehlt: \(watch.path)")]
        }

        var entries: [ActivityEntry] = []
        for file in candidateFiles(in: watch, target: target, rule: rule) {
            if let result = await process(file: file, rule: rule, target: target,
                                          config: config, apiKey: apiKey) {
                entries.append(result)
            }
        }
        return entries
    }

    // MARK: - Candidate discovery

    private func candidateFiles(in watch: URL, target: URL, rule: Rule) -> [URL] {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: watch, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let targetPath = target.standardizedFileURL.path
        return children
            .filter { url in
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?
                    .isRegularFile == true else { return false }
                let ext = url.pathExtension.lowercased()
                if Self.partialExtensions.contains(ext) { return false }
                // Never touch the rule's own target if it lives inside the watch folder.
                if url.standardizedFileURL.path.hasPrefix(targetPath + "/") { return false }
                if !rule.extensions.isEmpty, !rule.extensions.contains(ext) { return false }
                return true
            }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func fingerprint(_ url: URL) -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? Int64) ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(Int(mtime))"
    }

    /// A file is stable if it wasn't modified in the last few seconds and its
    /// size doesn't change across a short re-check.
    private func isStable(_ url: URL) async -> Bool {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let modified = attrs[.modificationDate] as? Date,
              let size = attrs[.size] as? Int64
        else { return false }
        guard Date().timeIntervalSince(modified) > 5 else { return false }
        try? await Task.sleep(nanoseconds: 700_000_000)
        let sizeAfter = (try? fm.attributesOfItem(atPath: url.path)[.size] as? Int64) ?? -1
        return sizeAfter == size
    }

    // MARK: - Processing

    private func process(
        file: URL, rule: Rule, target: URL, config: Config, apiKey: String
    ) async -> ActivityEntry? {
        let key = fingerprint(file)
        if skipped.contains(key) { return nil }
        if let until = failedUntil[key], until > Date() { return nil }
        guard await isStable(file) else { return nil }

        let name = file.lastPathComponent
        do {
            guard let base = URL(string: config.apiBase) else {
                throw MistralError.badResponse("ungültige API-Basis-URL")
            }
            let client = MistralClient(apiKey: apiKey, model: config.model, baseURL: base)
            let description = FileContext.describe(url: file)
            let result = try await client.classify(
                rulePrompt: rule.prompt, fileDescription: description
            )

            if result.action != "move" {
                skipped.insert(key)
                let reason = result.reason ?? "Regel trifft nicht zu"
                return entry(true, "[\(rule.name)] Übersprungen: \(name) – \(reason)")
            }
            guard let relative = result.relativePath, !relative.isEmpty else {
                throw MistralError.badResponse("relative_path fehlt bei action=move")
            }

            let destination = try Mover.destination(
                target: target, relativePath: relative,
                originalExtension: file.pathExtension
            )
            let outcome = try Mover.place(
                source: file, destination: destination, copy: rule.copyInsteadOfMove
            )
            switch outcome {
            case .moved(let url), .copied(let url):
                if rule.copyInsteadOfMove { skipped.insert(key) }
                let relDest = url.path.replacingOccurrences(
                    of: target.path + "/", with: ""
                )
                return entry(true, "[\(rule.name)] \(name) → \(relDest)")
            case .duplicate(let url):
                skipped.insert(key)
                return entry(
                    true,
                    "[\(rule.name)] Duplikat: \(name) existiert bereits als \(url.lastPathComponent)"
                )
            }
        } catch {
            failedUntil[key] = Date().addingTimeInterval(failRetryInterval)
            return entry(false, "[\(rule.name)] FEHLER bei \(name): \(error.localizedDescription)")
        }
    }

    private func entry(_ ok: Bool, _ message: String) -> ActivityEntry {
        ActivityEntry(date: Date(), ok: ok, message: message)
    }
}

/// One-shot CLI mode: `Sortomat scan-once` processes all enabled rules and
/// exits. Used for testing and scriptability.
enum HeadlessRunner {
    static func run() async {
        let config = ConfigStore.load()
        guard let apiKey = Keychain.apiKey(), !apiKey.isEmpty else {
            print("FEHLER: kein API-Key (Keychain oder MISTRAL_API_KEY).")
            exit(2)
        }
        let pipeline = Pipeline()
        var hadError = false
        for rule in config.rules where rule.enabled {
            let entries = await pipeline.scan(rule: rule, config: config, apiKey: apiKey)
            for entry in entries {
                print((entry.ok ? "OK   " : "ERR  ") + entry.message)
                ConfigStore.appendLog(entry.message)
                if !entry.ok { hadError = true }
            }
        }
        exit(hadError ? 1 : 0)
    }
}
