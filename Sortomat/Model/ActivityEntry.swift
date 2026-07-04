import Foundation

struct ActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let ok: Bool
    let message: String

    init(ok: Bool, message: String, date: Date = Date()) {
        self.ok = ok
        self.message = message
        self.date = date
    }
}

/// Everything a scan produced: log entries, pending plans awaiting review (for
/// dry-run rules), and the token usage it cost.
struct ScanResult {
    var entries: [ActivityEntry] = []
    var pending: [PlannedAction] = []
    var usage = TokenUsage()

    static func + (lhs: ScanResult, rhs: ScanResult) -> ScanResult {
        ScanResult(
            entries: lhs.entries + rhs.entries,
            pending: lhs.pending + rhs.pending,
            usage: lhs.usage + rhs.usage
        )
    }
}
