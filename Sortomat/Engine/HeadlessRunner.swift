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
            // stderr: stdout is the machine-readable OK/ERR stream a launchd
            // job or a shell pipeline reads.
            FileHandle.standardError.write(Data((L10n.t("error.noKey") + "\n").utf8))
        }

        let pipeline = Pipeline()
        var hadError = false
        // One pass is one undoable batch, exactly as in the GUI — without a
        // shared id `Sortomat undo` reversed only the last rule's moves.
        let batchID = UUID()
        for rule in config.rules.inExecutionOrder() {
            let result = await pipeline.scan(
                rule: rule, config: config, apiKey: apiKey, forcePreview: !apply,
                batchID: batchID
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
        // The whole journal: a pass over a big folder can journal more than a
        // few hundred moves, and a truncated window makes `lastBatch` reverse
        // only part of the batch while still printing success.
        let entries = Journal.recent(limit: .max)
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
