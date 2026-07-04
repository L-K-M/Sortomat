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
        if let handle = try? FileHandle(forWritingTo: ConfigStore.journalFile) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: ConfigStore.journalFile)
        }
    }

    /// Most recent entries first.
    static func recent(limit: Int = 200) -> [JournalEntry] {
        guard let data = try? Data(contentsOf: ConfigStore.journalFile) else { return [] }
        let decoder = JSONDecoder()
        let entries = data.split(separator: 0x0A).compactMap { slice -> JournalEntry? in
            try? decoder.decode(JournalEntry.self, from: Data(slice))
        }
        return Array(entries.reversed().prefix(limit))
    }

    enum UndoError: LocalizedError {
        case sourceOccupied(String)
        case destinationMissing(String)

        var errorDescription: String? {
            switch self {
            case .sourceOccupied(let p): return "A file is already at the original location: \(p)"
            case .destinationMissing(let p): return "The moved file is no longer at: \(p)"
            }
        }
    }

    /// Reverse one entry: for a copy, delete the copy; for a move, move it back
    /// to its original path (refusing to clobber a file that reappeared there).
    static func undo(_ entry: JournalEntry) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: entry.destinationPath) else {
            throw UndoError.destinationMissing(entry.destinationPath)
        }
        if entry.wasCopy {
            try fm.removeItem(at: entry.destination)
            return
        }
        guard !fm.fileExists(atPath: entry.sourcePath) else {
            throw UndoError.sourceOccupied(entry.sourcePath)
        }
        try fm.createDirectory(
            at: entry.source.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try fm.moveItem(at: entry.destination, to: entry.source)
    }
}
