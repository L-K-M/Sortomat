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
            FileHandle.standardError.write(Data((L10n.t("headless.unknownCommand", command) + "\n").utf8))
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
        let batch = Journal.lastBatch(in: entries)
        guard !batch.isEmpty else {
            print(L10n.t("headless.nothingToUndo"))
            exit(0)
        }
        // Pin every restored file as skipped in the ledger — otherwise the
        // next scan-once re-classifies (re-pays for) it and moves it right
        // back. The GUI undo path does the same via AppState.undo.
        let ledger = Ledger()
        var failed = false
        for entry in batch {
            do {
                try Journal.undo(entry)
                if !entry.wasCopy {
                    let fingerprint = Ledger.fingerprint(URL(fileURLWithPath: entry.sourcePath))
                    ledger.record(ruleID: entry.ruleID, fingerprint: fingerprint, status: .skipped)
                }
                print(L10n.t("headless.undone", entry.destinationPath, entry.sourcePath))
            } catch {
                print(L10n.t("headless.undoFailed", entry.destinationPath, error.localizedDescription))
                failed = true
            }
        }
        ledger.save()
        exit(failed ? 1 : 0)
    }
}
