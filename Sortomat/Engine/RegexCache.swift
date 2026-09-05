import Foundation

/// Compiled regular expressions, cached by pattern and options, with the
/// project's existing safety rules applied: `DeterministicEngine.isSafeRegex`
/// rejects anything over 500 characters or carrying a nested quantifier, and
/// subjects are truncated so an adversarial file cannot make matching
/// unbounded.
enum RegexCache {
    /// Long enough for any file name and for the extracted-text sample; short
    /// enough that a pathological pattern still finishes.
    static let maxSubjectLength = 4096

    private static let lock = NSLock()
    private static var cache: [String: NSRegularExpression] = [:]

    static func regex(_ pattern: String, caseSensitive: Bool) -> NSRegularExpression? {
        guard DeterministicEngine.isSafeRegex(pattern) else { return nil }
        let key = (caseSensitive ? "s|" : "i|") + pattern
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] { return cached }
        let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
        guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
            return nil
        }
        // Bounded: a config with thousands of distinct patterns must not pin
        // them all in memory forever.
        if cache.count > 256 { cache.removeAll() }
        cache[key] = compiled
        return compiled
    }

    /// The first match, plus its capture groups by index and by name. Search is
    /// unanchored — "the name matches the regex" has always meant `firstMatch`
    /// here, so migrated regex pre-rules behave identically and `^`/`$` still
    /// anchor explicitly.
    static func firstMatch(pattern: String, in subject: String,
                           caseSensitive: Bool) -> RegexMatch? {
        guard let expression = regex(pattern, caseSensitive: caseSensitive) else { return nil }
        let bounded = String(subject.prefix(maxSubjectLength))
        let text = bounded as NSString
        guard let result = expression.firstMatch(
            in: bounded, options: [], range: NSRange(location: 0, length: text.length)
        ) else { return nil }

        var indexed: [String: String] = [:]
        for group in 0..<result.numberOfRanges {
            let range = result.range(at: group)
            guard range.location != NSNotFound else { continue }
            indexed[String(group)] = text.substring(with: range)
        }
        for name in namedGroups(in: pattern) {
            let range = result.range(withName: name)
            guard range.location != NSNotFound else { continue }
            indexed[name] = text.substring(with: range)
        }
        return RegexMatch(captures: indexed)
    }

    /// The names in `(?<name>…)` groups. Scanned from the pattern rather than
    /// asked of `NSRegularExpression`, which does not expose them.
    static func namedGroups(in pattern: String) -> [String] {
        var names: [String] = []
        let characters = Array(pattern)
        var index = 0
        while index + 2 < characters.count {
            if characters[index] == "(", characters[index + 1] == "?",
               characters[index + 2] == "<" {
                var cursor = index + 3
                var name = ""
                // (?<= and (?<! are look-behinds, not named groups.
                if cursor < characters.count, characters[cursor] == "=" || characters[cursor] == "!" {
                    index += 3
                    continue
                }
                while cursor < characters.count, characters[cursor] != ">" {
                    name.append(characters[cursor])
                    cursor += 1
                }
                if !name.isEmpty, cursor < characters.count { names.append(name) }
                index = cursor
            }
            index += 1
        }
        return names
    }
}

struct RegexMatch: Equatable {
    /// Group number (as a string) or group name → matched text.
    var captures: [String: String]
}
