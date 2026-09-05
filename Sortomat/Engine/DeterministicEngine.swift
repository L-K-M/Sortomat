import Foundation

/// Evaluates a rule's deterministic pre-rules before any model call. First match
/// wins; if nothing matches, the file falls through to the model (PLAN Phase 5:
/// "predictability of Hazel + fuzziness of an LLM").
enum DeterministicEngine {
    enum Decision: Equatable {
        case route(relativePath: String, preRuleName: String)
        case skip(preRuleName: String)
        case useLLM
    }

    /// Coarse content kinds, matched by extension.
    static let kindExtensions: [String: Set<String>] = [
        "image": ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp",
                  "svg", "avif", "dng", "raw", "cr2", "nef", "arw", "psd"],
        "video": ["mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg"],
        "audio": ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "ogg", "opus"],
        "pdf": ["pdf"],
        "archive": ["zip", "tar", "gz", "tgz", "bz2", "rar", "7z", "xz"],
        "text": ["txt", "md", "markdown", "csv", "tsv", "rtf", "log"],
        "ebook": ["epub", "mobi", "azw", "azw3", "fb2"],
        "document": ["doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "odt", "ods",
                     "odp", "rtfd"],
    ]

    static func evaluate(rule: Rule, file: URL, now: Date = Date()) -> Decision {
        for preRule in rule.preRules where matches(preRule, file: file, now: now) {
            switch preRule.action {
            case .skip:
                return .skip(preRuleName: preRule.name.isEmpty ? preRule.pattern : preRule.name)
            case .useLLM:
                return .useLLM
            case .route:
                let path = expandRoute(preRule.routePath, file: file, now: now)
                return .route(
                    relativePath: path,
                    preRuleName: preRule.name.isEmpty ? preRule.pattern : preRule.name
                )
            }
        }
        return .useLLM
    }

    static func matches(_ preRule: PreRule, file: URL, now: Date) -> Bool {
        let name = file.lastPathComponent
        switch preRule.match {
        case .glob:
            return globMatches(preRule.pattern, name)
        case .regex:
            guard isSafeRegex(preRule.pattern) else { return false }
            return name.range(of: preRule.pattern, options: [.regularExpression, .caseInsensitive]) != nil
        case .kind:
            let ext = file.pathExtension.lowercased()
            return kindExtensions[preRule.pattern.lowercased()]?.contains(ext) ?? false
        case .olderThanDays, .newerThanDays:
            guard let days = Double(preRule.pattern.trimmingCharacters(in: .whitespaces)),
                  let mtime = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                      .contentModificationDate
            else { return false }
            let ageDays = now.timeIntervalSince(mtime) / 86_400
            return preRule.match == .olderThanDays ? ageDays > days : ageDays < days
        }
    }

    /// Expand `{name} {ext} {year} {month} {day}` in a route template. Guarantees
    /// a filename: if the template never references `{name}`, the original stem is
    /// appended so every file doesn't collapse onto one destination.
    static func expandRoute(_ template: String, file: URL, now: Date) -> String {
        // An empty template used to expand to "/{name}" — an *absolute* path
        // the sanitizer rightly rejects, so a fresh pre-rule (whose default
        // route is empty) failed every matching file forever. Empty means
        // "the target folder itself".
        var path = template.trimmingCharacters(in: .whitespaces)
        if path.isEmpty { path = "{name}" }
        if !path.contains("{name}") {
            path = path.hasSuffix("/") ? path + "{name}" : path + "/{name}"
        }
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        let cal = Calendar(identifier: .gregorian)
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? now
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        // A fixed substitution order: a Dictionary iterates in hash-seeded
        // order, so a file literally named "receipt {year}.pdf" could route
        // differently across launches.
        let replacements: [(String, String)] = [
            ("{year}", String(format: "%04d", comps.year ?? 0)),
            ("{month}", String(format: "%02d", comps.month ?? 0)),
            ("{day}", String(format: "%02d", comps.day ?? 0)),
            ("{ext}", ext),
            ("{name}", stem),
        ]
        for (token, value) in replacements {
            path = path.replacingOccurrences(of: token, with: value)
        }
        return path
    }

    /// Whether a pattern parses as a regular expression. The rule editor uses
    /// this to flag patterns that would otherwise fail in silence — an invalid
    /// regex simply never matches anything.
    static func isValidRegex(_ pattern: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern)) != nil
    }

    /// Shell-style glob match (`*` any run, `?` one character), case-insensitive,
    /// without regular expressions: a glob with a dozen stars used to become an
    /// `.*.*.*…` chain that backtracks combinatorially in ICU on a long,
    /// adversarial file name. The classic two-pointer wildcard walk is O(n·m)
    /// in the worst case and never worse.
    static func globMatches(_ pattern: String, _ name: String) -> Bool {
        let p = Array(pattern.lowercased())
        let n = Array(name.lowercased())
        guard !p.isEmpty else { return false }
        var pi = 0, ni = 0
        var starPattern = -1, starName = 0
        while ni < n.count {
            if pi < p.count, p[pi] == "?" || p[pi] == n[ni] {
                pi += 1
                ni += 1
            } else if pi < p.count, p[pi] == "*" {
                starPattern = pi
                starName = ni
                pi += 1
            } else if starPattern >= 0 {
                pi = starPattern + 1
                starName += 1
                ni = starName
            } else {
                return false
            }
        }
        while pi < p.count, p[pi] == "*" { pi += 1 }
        return pi == p.count
    }

    /// Whether a user regex is one we are willing to run against file names:
    /// it must compile, stay short, and not nest quantifiers (`(a+)+`,
    /// `(\w+\s?)*`), the classic catastrophic-backtracking shape that
    /// `NSRegularExpression` offers no time limit against. The rule editor
    /// flags rejected patterns; the engine treats them as never matching.
    static func isSafeRegex(_ pattern: String) -> Bool {
        guard pattern.count <= 500, isValidRegex(pattern) else { return false }
        let nestedQuantifier = "\\([^()]*[+*][^()]*\\)[+*{]"
        return pattern.range(of: nestedQuantifier, options: .regularExpression) == nil
    }

    /// Translate a shell glob (`*`, `?`) to an anchored regex, escaping the rest.
    /// Kept for tooling; matching itself uses `globMatches`.
    static func globToRegex(_ glob: String) -> String? {
        guard !glob.isEmpty else { return nil }
        var pattern = "^"
        for char in glob {
            switch char {
            case "*": pattern += ".*"
            case "?": pattern += "."
            case ".", "(", ")", "[", "]", "{", "}", "+", "^", "$", "|", "\\":
                pattern += "\\" + String(char)
            default: pattern += String(char)
            }
        }
        pattern += "$"
        return pattern
    }
}
