import Foundation

/// A persistent record of what each rule has already decided about a file, keyed
/// by `rule.id` + a cheap file fingerprint (path|size|mtime). This fixes two
/// audit findings at once: skip/fail memory is now per-rule (no cross-rule cache
/// poisoning, PLAN Phase 1) and survives relaunches, so previously-skipped files
/// aren't re-classified and re-paid for on every restart (PLAN Phase 2).
final class Ledger {
    enum Status: String, Codable {
        case skipped   // model/pre-rule said this file isn't ours — don't re-ask
        case done      // filed (or copied) — nothing more to do
        case failed    // transient failure — retry after `retryAfter`
    }

    struct Entry: Codable {
        var status: Status
        var date: Date
        var retryAfter: Date?
    }

    private var entries: [String: Entry]
    private let url: URL
    private let failRetryInterval: TimeInterval
    /// Whether anything changed since the last save — the whole-file rewrite
    /// used to run after every pass even when nothing had.
    private var dirty = false

    init(url: URL = ConfigStore.ledgerFile, failRetryInterval: TimeInterval = 1800) {
        self.url = url
        self.failRetryInterval = failRetryInterval
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            entries = decoded
        } else {
            entries = [:]
        }
    }

    /// A stable-per-content fingerprint that changes if the file is edited.
    static func fingerprint(_ url: URL) -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? Int64) ?? 0
        let mtime = (attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(size)|\(Int(mtime))"
    }

    func key(ruleID: UUID, fingerprint: String) -> String {
        keyPrefix(ruleID: ruleID) + fingerprint
    }

    /// The prefix every key of one rule starts with. Callers that filter keys
    /// by rule (the pipeline's preview set, `forget`) go through this rather
    /// than re-spelling the separator — a format change here would otherwise
    /// silently turn those filters into no-ops.
    func keyPrefix(ruleID: UUID) -> String {
        "\(ruleID.uuidString)|"
    }

    /// Should this (rule, file) be looked at now, or is it already accounted for?
    func shouldProcess(ruleID: UUID, fingerprint: String, now: Date = Date()) -> Bool {
        guard let entry = entries[key(ruleID: ruleID, fingerprint: fingerprint)] else {
            return true
        }
        switch entry.status {
        case .skipped, .done:
            return false
        case .failed:
            return (entry.retryAfter ?? now) <= now
        }
    }

    func record(ruleID: UUID, fingerprint: String, status: Status, now: Date = Date()) {
        let retryAfter = status == .failed ? now.addingTimeInterval(failRetryInterval) : nil
        entries[key(ruleID: ruleID, fingerprint: fingerprint)] =
            Entry(status: status, date: now, retryAfter: retryAfter)
        dirty = true
    }

    /// Drop entries for a rule (e.g. when it is deleted or reset).
    func forget(ruleID: UUID) {
        let prefix = keyPrefix(ruleID: ruleID)
        let before = entries.count
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
        if entries.count != before { dirty = true }
    }

    /// Drop entries whose file has vanished and whose record is old. A
    /// path|size|mtime key for a file that no longer exists can never match
    /// again — it only grows the file forever. Entries for files that *still
    /// exist* are always kept, however old: they are exactly the memory that
    /// prevents re-paying for an untouched file. The age guard keeps records
    /// for files on unmounted volumes or mid-rename from being dropped hastily.
    func prune(olderThan: TimeInterval = 30 * 86_400, now: Date = Date()) {
        let fm = FileManager.default
        let before = entries.count
        entries = entries.filter { key, entry in
            guard now.timeIntervalSince(entry.date) > olderThan else { return true }
            // Key layout: ruleUUID|path|size|mtime — the path may itself
            // contain "|", so strip one component from the front, two from
            // the back, and rejoin the middle.
            let parts = key.split(separator: "|", omittingEmptySubsequences: false)
            guard parts.count >= 4 else { return false } // malformed: drop
            let path = parts.dropFirst().dropLast(2).joined(separator: "|")
            return fm.fileExists(atPath: path)
        }
        if entries.count != before { dirty = true }
    }

    var count: Int { entries.count }

    func save() {
        guard dirty else { return }
        ConfigStore.ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(entries), (try? data.write(to: url, options: .atomic)) != nil {
            dirty = false
        }
    }
}
