import Foundation

struct ActivityEntry: Identifiable, Equatable {
    /// What the entry reports — lets callers summarize ("3 files filed",
    /// "1 failure") instead of guessing from message text.
    enum Kind: Equatable {
        case filed   // a file was actually placed (moved/copied/quarantined)
        case failed
        case info    // skips, duplicates, previews, budget notes
    }

    let id = UUID()
    let date: Date
    let ok: Bool
    let message: String
    let kind: Kind

    init(ok: Bool, message: String, date: Date = Date(), kind: Kind? = nil) {
        self.ok = ok
        self.message = message
        self.date = date
        self.kind = kind ?? (ok ? .info : .failed)
    }
}

/// Everything a scan produced: log entries, pending plans awaiting review (for
/// dry-run rules), and the token usage it cost.
struct ScanResult {
    var entries: [ActivityEntry] = []
    var pending: [PlannedAction] = []
    var usage = TokenUsage()
    /// Candidates rejected by the stability probe (too young / still growing).
    /// Non-zero tells the caller a short follow-up pass is worth scheduling.
    var unstableCount = 0
    /// The rule this result belongs to (nil for the empty placeholder result).
    var ruleID: UUID?
    /// The rule's watched folder was missing this pass. Callers notify once
    /// per outage rather than once per pass; the log still records each pass.
    var watchMissing = false

    static func + (lhs: ScanResult, rhs: ScanResult) -> ScanResult {
        ScanResult(
            entries: lhs.entries + rhs.entries,
            pending: lhs.pending + rhs.pending,
            usage: lhs.usage + rhs.usage,
            unstableCount: lhs.unstableCount + rhs.unstableCount,
            ruleID: lhs.ruleID ?? rhs.ruleID,
            watchMissing: lhs.watchMissing || rhs.watchMissing
        )
    }
}
