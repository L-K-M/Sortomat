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
        "image": ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp"],
        "video": ["mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg"],
        "audio": ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "ogg", "opus"],
        "pdf": ["pdf"],
        "archive": ["zip", "tar", "gz", "tgz", "bz2", "rar", "7z", "xz"],
        "text": ["txt", "md", "markdown", "csv", "tsv", "rtf", "log"],
        "ebook": ["epub", "mobi", "azw", "azw3", "fb2"],
        "document": ["doc", "docx", "pages", "xls", "xlsx", "numbers", "ppt", "pptx", "key", "odt", "ods"],
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
            return globToRegex(preRule.pattern).flatMap {
                name.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil
            } ?? false
        case .regex:
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
        var path = template
        if !path.contains("{name}") {
            path = path.hasSuffix("/") ? path + "{name}" : path + "/{name}"
        }
        let stem = file.deletingPathExtension().lastPathComponent
        let ext = file.pathExtension
        let cal = Calendar(identifier: .gregorian)
        let date = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate ?? now
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let replacements: [String: String] = [
            "{name}": stem,
            "{ext}": ext,
            "{year}": String(format: "%04d", comps.year ?? 0),
            "{month}": String(format: "%02d", comps.month ?? 0),
            "{day}": String(format: "%02d", comps.day ?? 0),
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

    /// Translate a shell glob (`*`, `?`) to an anchored regex, escaping the rest.
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
