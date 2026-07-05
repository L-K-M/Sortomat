import Foundation

/// The running token usage for the current month, persisted beside the config —
/// "estimated spend" used to reset to zero on every launch, which made the
/// cost-awareness pitch a per-session anecdote. Rolls over automatically when
/// the month changes.
struct SpendStore: Codable, Equatable {
    /// Gregorian "YYYY-MM"; a stored record from another month is discarded.
    var month: String
    var input: Int
    var output: Int

    var usage: TokenUsage { TokenUsage(input: input, output: output) }

    static func monthKey(for date: Date = Date()) -> String {
        let comps = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", comps.year ?? 0, comps.month ?? 0)
    }

    /// The stored usage if it belongs to the current month, a fresh zero
    /// record otherwise (missing file, torn write, or month rollover).
    static func load(from url: URL = ConfigStore.spendFile, now: Date = Date()) -> SpendStore {
        let current = monthKey(for: now)
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(SpendStore.self, from: data),
              stored.month == current
        else {
            return SpendStore(month: current, input: 0, output: 0)
        }
        return stored
    }

    func save(to url: URL = ConfigStore.spendFile) {
        ConfigStore.ensureDirectory()
        if let data = try? JSONEncoder().encode(self) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
