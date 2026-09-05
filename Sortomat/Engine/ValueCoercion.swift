import Foundation

/// A span of time written the way people write it: `30d`, `2w`, `3mo`, `6h`.
struct TimeSpan: Equatable, Sendable {
    enum Unit: String, Equatable, Sendable {
        case minutes = "m"
        case hours = "h"
        case days = "d"
        case weeks = "w"
        case months = "mo"
        case years = "y"
    }

    var amount: Double
    var unit: Unit

    /// `now` minus this span, on the Gregorian calendar in the current zone —
    /// so "3 months" is three real months, not ninety days.
    func cutoff(from now: Date, calendar: Calendar) -> Date? {
        let whole = Int(amount.rounded())
        switch unit {
        case .minutes: return calendar.date(byAdding: .minute, value: -whole, to: now)
        case .hours: return calendar.date(byAdding: .hour, value: -whole, to: now)
        case .days: return calendar.date(byAdding: .day, value: -whole, to: now)
        case .weeks: return calendar.date(byAdding: .weekOfYear, value: -whole, to: now)
        case .months: return calendar.date(byAdding: .month, value: -whole, to: now)
        case .years: return calendar.date(byAdding: .year, value: -whole, to: now)
        }
    }
}

/// Turns a `ConditionValue` into whatever the operator asked for. Pure, total,
/// and never throwing: a value that cannot be coerced makes the test false
/// with `verdict: .invalidValue`, which the trace then explains.
enum ValueCoercion {
    static func string(_ value: ConditionValue) -> String? {
        switch value {
        case .text(let text): return text
        case .number(let number): return NumberText.canonical(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .list(let list): return list.first
        case .none: return nil
        }
    }

    static func strings(_ value: ConditionValue) -> [String] {
        switch value {
        case .text(let text): return [text]
        case .number(let number): return [NumberText.canonical(number)]
        case .bool(let flag): return [flag ? "true" : "false"]
        case .list(let list): return list
        case .none: return []
        }
    }

    /// Numbers, with the byte suffixes people actually type. Decimal and
    /// binary suffixes are both accepted because both are in daily use.
    static func number(_ value: ConditionValue) -> Double? {
        switch value {
        case .number(let number): return number
        case .bool(let flag): return flag ? 1 : 0
        case .text(let text): return parseNumber(text)
        case .list(let list): return list.first.flatMap(parseNumber)
        case .none: return nil
        }
    }

    static func parseNumber(_ text: String) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        let multipliers: [(String, Double)] = [
            ("kib", 1024), ("mib", 1024 * 1024), ("gib", 1024 * 1024 * 1024),
            ("tib", 1024 * 1024 * 1024 * 1024),
            ("kb", 1000), ("mb", 1_000_000), ("gb", 1_000_000_000),
            ("tb", 1_000_000_000_000),
            ("k", 1000), ("m", 1_000_000), ("g", 1_000_000_000),
            ("b", 1)
        ]
        for (suffix, multiplier) in multipliers where trimmed.hasSuffix(suffix) {
            let head = String(trimmed.dropLast(suffix.count)).trimmingCharacters(in: .whitespaces)
            if let amount = Double(head) { return amount * multiplier }
        }
        return Double(trimmed)
    }

    static func range(_ value: ConditionValue) -> (Double, Double)? {
        let parts = strings(value)
        guard parts.count >= 2,
              let lower = parseNumber(parts[0]),
              let upper = parseNumber(parts[1]) else { return nil }
        return lower <= upper ? (lower, upper) : (upper, lower)
    }

    /// A bare number means **days**, matching the legacy `olderThanDays` unit.
    static func timeSpan(_ value: ConditionValue) -> TimeSpan? {
        switch value {
        case .number(let number): return TimeSpan(amount: number, unit: .days)
        case .text(let text): return parseTimeSpan(text)
        case .list(let list): return list.first.flatMap(parseTimeSpan)
        case .bool, .none: return nil
        }
    }

    static func parseTimeSpan(_ text: String) -> TimeSpan? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty else { return nil }
        // "mo" must be tested before "m", or "3mo" reads as three minutes.
        let units: [TimeSpan.Unit] = [.months, .minutes, .hours, .days, .weeks, .years]
        for unit in units where trimmed.hasSuffix(unit.rawValue) {
            let head = String(trimmed.dropLast(unit.rawValue.count)).trimmingCharacters(in: .whitespaces)
            if let amount = Double(head) { return TimeSpan(amount: amount, unit: unit) }
        }
        if let amount = Double(trimmed) { return TimeSpan(amount: amount, unit: .days) }
        return nil
    }

    /// Absolute dates: a calendar day, or an instant.
    static func date(_ value: ConditionValue, calendar: Calendar) -> Date? {
        guard let text = string(value)?.trimmingCharacters(in: .whitespaces), !text.isEmpty else {
            return nil
        }
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd", "yyyy/MM/dd"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: text) { return date }
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: text)
    }

    static func bool(_ value: ConditionValue) -> Bool? {
        switch value {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        case .text(let text):
            switch text.trimmingCharacters(in: .whitespaces).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        case .list, .none: return nil
        }
    }
}
