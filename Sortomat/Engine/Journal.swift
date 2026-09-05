import Foundation

/// One recorded placement, enough to reverse it (PLAN Phase 2: "record every
/// source → destination … one-click revert"). Stored append-only as JSONL.
struct JournalEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var ruleID: UUID
    var ruleName: String
    var sourcePath: String
    var destinationPath: String
    var wasCopy: Bool
    var reason: String
    /// One id per scan pass (or per approved-preview batch), so "undo the last
    /// check" can undo exactly the moves that belong together — instead of the
    /// old 5-second-window guess. Optional, so old journals decode unchanged.
    var batchID: UUID?
    /// When set, this line records the *reversal* of the entry with that id
    /// (an undo tombstone appended by `undo`), not a new placement. Optional,
    /// so journals written before this field decode unchanged.
    var undoOf: UUID?
    /// `size|mtime` of the placed file, captured right after the move. Undo
    /// refuses to move back a file that no longer matches: without this, a
    /// stale History entry would yank whatever *currently* sits at the
    /// destination (a replacement, a later edit) to the old source path.
    /// Optional, so journals written before this field decode unchanged.
    var destinationStamp: String?

    var source: URL { URL(fileURLWithPath: sourcePath) }
    var destination: URL { URL(fileURLWithPath: destinationPath) }
}

/// Append-only move journal with one-click undo.
enum Journal {
    static func record(_ entry: JournalEntry) {
        ConfigStore.ensureDirectory()
        guard let line = try? JSONEncoder().encode(entry) else { return }
        var data = line
        data.append(0x0A) // newline
        do {
            if let handle = try? FileHandle(forWritingTo: ConfigStore.journalFile) {
                defer { try? handle.close() }
                _ = try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } else {
                try data.write(to: ConfigStore.journalFile)
            }
        } catch {
            // The move already happened; a lost journal line means it can't
            // be undone from History. Say so instead of failing silently.
            ConfigStore.appendLog(L10n.t("journal.writeFailed", entry.destinationPath, error.localizedDescription))
            Log.pipeline.error("journal write failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `size|mtime` of a file, the cheap identity `undo` checks before moving
    /// a file back. Nil when the file can't be read.
    static func stamp(of url: URL) -> String? {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return nil }
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(size)|\(Int(mtime))"
    }

    /// Most recent entries first. Undone entries (those with a matching
    /// reversal tombstone) and the tombstones themselves are folded away, so
    /// an undone move doesn't resurface with a live Undo button on the next
    /// reload — clicking it again could only fail.
    static func recent(limit: Int = 200) -> [JournalEntry] {
        guard let data = try? Data(contentsOf: ConfigStore.journalFile) else { return [] }
        let decoder = JSONDecoder()
        let all = data.split(separator: 0x0A).compactMap { slice -> JournalEntry? in
            try? decoder.decode(JournalEntry.self, from: Data(slice))
        }
        let undone = Set(all.compactMap(\.undoOf))
        let entries = all.filter { $0.undoOf == nil && !undone.contains($0.id) }
        return Array(entries.reversed().prefix(limit))
    }

    /// The newest "batch" among `entries` (expected newest-first, as returned
    /// by `recent`): every entry sharing the newest entry's `batchID`, or — for
    /// legacy entries written before batch ids — everything within 5 seconds
    /// of the newest, the old heuristic.
    static func lastBatch(in entries: [JournalEntry]) -> [JournalEntry] {
        guard let newest = entries.first else { return [] }
        if let batch = newest.batchID {
            return entries.filter { $0.batchID == batch }
        }
        let cutoff = newest.date.addingTimeInterval(-5)
        return Array(entries.prefix { $0.date >= cutoff })
    }

    enum UndoError: LocalizedError {
        case sourceOccupied(String)
        case destinationMissing(String)
        case destinationModified(String)
        case destinationReplaced(String)

        var errorDescription: String? {
            switch self {
            case .sourceOccupied(let p): return L10n.t("journal.undo.sourceOccupied", p)
            case .destinationMissing(let p): return L10n.t("journal.undo.destinationMissing", p)
            case .destinationModified(let p): return L10n.t("journal.undo.destinationModified", p)
            case .destinationReplaced(let p): return L10n.t("journal.undo.destinationReplaced", p)
            }
        }
    }

    /// Reverse one entry: for a copy, delete the copy; for a move, move it back
    /// to its original path (refusing to clobber a file that reappeared there).
    /// A successful reversal is journaled as a tombstone so `recent` stops
    /// offering it.
    static func undo(_ entry: JournalEntry) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: entry.destinationPath) else {
            throw UndoError.destinationMissing(entry.destinationPath)
        }
        if entry.wasCopy {
            // Undo must not destroy work: if the copy has been edited since
            // (it no longer matches the surviving original), refuse rather
            // than delete a file the user changed. When the original is gone
            // we can't tell — deleting the only remaining version is worse
            // than leaving it, so refuse then too.
            // Full-content digests: the default 4 MiB prefix would miss an
            // edit past the prefix of a large copy — the same bounded-digest
            // trap the cross-volume verifier fell into (B2/R1).
            guard fm.fileExists(atPath: entry.sourcePath),
                  let sourceDigest = ContentHash.digest(of: entry.source, limit: .max),
                  let copyDigest = ContentHash.digest(of: entry.destination, limit: .max),
                  sourceDigest == copyDigest
            else {
                throw UndoError.destinationModified(entry.destinationPath)
            }
            try fm.removeItem(at: entry.destination)
            recordTombstone(for: entry)
            return
        }
        guard !fm.fileExists(atPath: entry.sourcePath) else {
            throw UndoError.sourceOccupied(entry.sourcePath)
        }
        // Only the file Sortomat placed may be moved back. A replacement or a
        // later edit changes size or mtime; leave such a file where it is.
        if let expected = entry.destinationStamp,
           let current = stamp(of: entry.destination), current != expected {
            throw UndoError.destinationReplaced(entry.destinationPath)
        }
        try fm.createDirectory(
            at: entry.source.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try fm.moveItem(at: entry.destination, to: entry.source)
        recordTombstone(for: entry)
    }

    private static func recordTombstone(for entry: JournalEntry) {
        record(JournalEntry(
            ruleID: entry.ruleID, ruleName: entry.ruleName,
            sourcePath: entry.sourcePath, destinationPath: entry.destinationPath,
            wasCopy: entry.wasCopy, reason: "undo", undoOf: entry.id
        ))
    }
}
