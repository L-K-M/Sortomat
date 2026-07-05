import Foundation

/// Command-line entry points used by tests, scripts and launchd jobs. Runs the
/// same Pipeline the GUI uses, then exits.
enum HeadlessRunner {
    static func run(_ arguments: [String]) async -> Never {
        let command = arguments.first ?? "scan-once"
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
        let apiKey = Keychain.apiKey() ?? ""
        if config.providerRequiresKey && apiKey.isEmpty {
            // Not fatal anymore: deterministic pre-rules still run without a
            // key; files that need the model are deferred and reported per rule.
            print(L10n.t("error.noKey"))
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
