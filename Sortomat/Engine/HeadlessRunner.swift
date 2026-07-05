import Foundation

/// Command-line entry points used by tests, scripts and launchd jobs. Runs the
/// same Pipeline the GUI uses, then exits.
enum HeadlessRunner {
    /// Held for the whole run (a static so ARC can't release it early); the
    /// process exit releases it.
    private static var lock: ProcessLock?

    static func run(_ arguments: [String]) async -> Never {
        let command = arguments.first ?? "scan-once"
        // Every subcommand writes the ledger and/or journal. Running beside a
        // live GUI (or a second headless run) clobbers records — refuse
        // politely instead.
        lock = ProcessLock.acquire()
        if lock == nil {
            FileHandle.standardError.write(Data((L10n.t("process.locked") + "\n").utf8))
            exit(3)
        }
        switch command {
        case "scan-once":
            await scanOnce(apply: true)
        case "preview":
            await scanOnce(apply: false)
        case "undo":
            undoLast()
        default:
            FileHandle.standardError.write(Data("Unknown command: \(command)\n".utf8))
            exit(64)
        }
    }

    private static func scanOnce(apply: Bool) async -> Never {
        let config = ConfigStore.load()
        let needsKey = config.providerRequiresKey
        let apiKey = Keychain.apiKey() ?? ""
        if needsKey && apiKey.isEmpty {
            print(L10n.t("error.noKey"))
            exit(2)
        }

        let pipeline = Pipeline()
        var hadError = false
        for rule in config.rules.inExecutionOrder() {
            let result = await pipeline.scan(
                rule: rule, config: config, apiKey: apiKey, forcePreview: !apply
            )
            for entry in result.entries {
                print((entry.ok ? "OK   " : "ERR  ") + entry.message)
                ConfigStore.appendLog(entry.message)
                if !entry.ok { hadError = true }
            }
        }
        await pipeline.persist()
        exit(hadError ? 1 : 0)
    }

    private static func undoLast() -> Never {
        let entries = Journal.recent(limit: 500)
        guard let last = entries.first else {
            print("Nothing to undo.")
            exit(0)
        }
        // Undo the whole most-recent batch (same scan ≈ within a few seconds).
        let cutoff = last.date.addingTimeInterval(-5)
        let batch = entries.prefix { $0.date >= cutoff }
        var failed = false
        for entry in batch {
            do {
                try Journal.undo(entry)
                print("Undone: \(entry.destinationPath) → \(entry.sourcePath)")
            } catch {
                print("Failed: \(entry.destinationPath): \(error.localizedDescription)")
                failed = true
            }
        }
        exit(failed ? 1 : 0)
    }
}
