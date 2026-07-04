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
        "\(ruleID.uuidString)|\(fingerprint)"
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
    }

    /// Drop entries for a rule (e.g. when it is deleted or reset).
    func forget(ruleID: UUID) {
        let prefix = ruleID.uuidString + "|"
        entries = entries.filter { !$0.key.hasPrefix(prefix) }
    }

    var count: Int { entries.count }

    func save() {
        ConfigStore.ensureDirectory()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
