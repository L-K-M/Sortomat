import Foundation

/// A per-rule, content-addressed memo of model verdicts: identical bytes get
/// the identical decision — instantly, deterministically, and for free. The
/// ledger keys on path|size|mtime, so the same attachment re-downloaded, the
/// same PDF re-exported, or the same e-book arriving under a new name was
/// re-classified (and re-paid for) every time. Keys use the *full-content*
/// digest: the bounded dedup prefix could cross-contaminate two large files
/// that share their first 4 MiB (the B7 trade-off must not leak in here).
final class DecisionMemo {
    struct Entry: Codable, Equatable {
        var action: String
        var relativePath: String?
        var reason: String?
        var confidence: Double?
        var date: Date
    }

    /// Bounded: past this, the oldest tenth is evicted in one sweep.
    static let maxEntries = 2000

    /// Files above this size are never memoized: a full-content digest of a
    /// multi-gigabyte video just to look up a verdict would cost more than
    /// the classification it might save. Everything a model can usefully
    /// classify (documents, e-books, images) is far below it.
    static let maxHashedBytes: Int64 = 256 * 1024 * 1024

    /// The memo key digest for a file — full content, so two large files that
    /// share a prefix can never share a verdict — or nil when the file is too
    /// large to be worth hashing (or can't be read).
    static func digest(of url: URL) -> String? {
        // Resource values follow symlinks; `attributesOfItem` has lstat
        // semantics and would report the *link's* few bytes, letting a link to
        // a huge file sail past the cap and get hashed in full.
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        guard Int64(size) <= maxHashedBytes else { return nil }
        return ContentHash.digest(of: url, limit: .max)
    }

    private var entries: [String: Entry]
    private let url: URL
    private var dirty = false

    init(url: URL = ConfigStore.memoFile) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    var isEmpty: Bool { entries.isEmpty }
    var count: Int { entries.count }

    /// A verdict belongs to one rule, one model and one file extension. The
    /// model matters because a decision recorded by a cheap local model must
    /// not be replayed after the user switches to a stronger one; the
    /// extension because the stored path was routed for it, and identical
    /// bytes can arrive under a different one.
    static func key(ruleID: UUID, model: String, ext: String, digest: String) -> String {
        "\(ruleID.uuidString)|\(model)|\(ext.lowercased())|\(digest)"
    }

    func lookup(ruleID: UUID, model: String, ext: String, digest: String) -> Entry? {
        entries[Self.key(ruleID: ruleID, model: model, ext: ext, digest: digest)]
    }

    func record(ruleID: UUID, model: String, ext: String, digest: String,
                action: String, relativePath: String?,
                reason: String?, confidence: Double?, now: Date = Date()) {
        entries[Self.key(ruleID: ruleID, model: model, ext: ext, digest: digest)] = Entry(
            action: action, relativePath: relativePath, reason: reason,
            confidence: confidence, date: now
        )
        dirty = true
        evictIfNeeded()
    }

    /// Drop everything remembered for one rule — its prompt changed or it was
    /// deleted; old verdicts no longer speak for it.
    func forget(ruleID: UUID) {
        let prefix = ruleID.uuidString + "|"
        let before = entries.count
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
        if entries.count != before { dirty = true }
    }

    /// Drop every remembered verdict (a global change — a new model, a new
    /// provider — invalidates all of them at once).
    func removeAll() {
        guard !entries.isEmpty else { return }
        entries.removeAll()
        dirty = true
    }

    private func evictIfNeeded() {
        guard entries.count > Self.maxEntries else { return }
        let oldestFirst = entries.sorted { $0.value.date < $1.value.date }
        for (key, _) in oldestFirst.prefix(Self.maxEntries / 10) {
            entries.removeValue(forKey: key)
        }
    }

    func save() {
        guard dirty else { return }
        ConfigStore.ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(entries),
           (try? data.write(to: url, options: .atomic)) != nil {
            dirty = false
        }
    }
}
