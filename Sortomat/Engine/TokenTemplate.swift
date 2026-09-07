import Foundation

/// A value a template token can carry. Keeping it typed through the filter
/// chain is what lets `date:` format a real `Date` and `pad:` zero-pad a real
/// number instead of guessing from a string.
enum TemplateValue: Equatable {
    case text(String)
    case number(Double)
    case date(Date)
    case list([String])

    var isEmpty: Bool {
        switch self {
        // Newlines too: `escapeValue` collapses them away, so a value that
        // is only a newline rendered as nothing while `default:` — which
        // asks this question — decided it was not empty and stayed quiet.
        // A model answer arriving with a newline is called ordinary two
        // hundred lines down.
        case .text(let value): return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .list(let value): return value.isEmpty
        case .number, .date: return false
        }
    }
}

enum TemplateError: Equatable {
    case unterminatedPlaceholder
    case emptyToken
    case unknownFilter(String)

    var message: String {
        switch self {
        case .unterminatedPlaceholder: return L10n.t("template.error.unterminated")
        case .emptyToken: return L10n.t("template.error.emptyToken")
        case .unknownFilter(let name): return L10n.t("template.error.unknownFilter", name)
        }
    }
}

/// What a template renders to. The counter is left as a hole because the
/// engine is pure and cannot probe the disk for a free name; the pipeline
/// fills it in.
struct RenderedTemplate: Equatable {
    enum Part: Equatable {
        case literal(String)
        case counter(pad: Int)
    }

    var parts: [Part]

    var hasCounter: Bool {
        parts.contains { if case .counter = $0 { return true } else { return false } }
    }

    func string(counter: Int = 1) -> String {
        parts.map { part in
            switch part {
            case .literal(let text): return text
            case .counter(let pad):
                let digits = String(counter)
                // Clamped here too: this part can be built by the pipeline
                // without passing through the filter above.
                let width = min(max(pad, 1), 64)
                return digits.count >= width
                    ? digits
                    : String(repeating: "0", count: width - digits.count) + digits
            }
        }.joined()
    }
}

/// The one template language, used for destinations, renames, comments,
/// notifications and tags.
///
///     Finanzen/{match.year}/{whereFrom.host|default:'Unbekannt'}/{stem}.{ext}
///
/// Parsing is a single left-to-right walk — no regex, no backtracking. `{{`
/// and `}}` are literal braces. An unterminated `{`, an empty token or an
/// unknown filter is reported rather than silently swallowed, so the editor
/// can show it and a run-time render can fail loudly instead of producing an
/// empty path segment.
struct TokenTemplate {
    struct Filter: Equatable {
        var name: String
        var argument: String?
    }

    enum Node: Equatable {
        case literal(String)
        case placeholder(token: String, filters: [Filter])
    }

    let source: String
    let nodes: [Node]
    let errors: [TemplateError]

    var isValid: Bool { errors.isEmpty }

    /// Every token this template reads, in order — the validator uses it to
    /// warn about conditions a rule can never satisfy.
    var tokens: [String] {
        nodes.compactMap { if case .placeholder(let token, _) = $0 { return token } else { return nil } }
    }

    init(_ source: String) {
        self.source = source
        var nodes: [Node] = []
        var errors: [TemplateError] = []
        var literal = ""
        let characters = Array(source)
        var index = 0

        while index < characters.count {
            let character = characters[index]
            if character == "{" {
                if index + 1 < characters.count, characters[index + 1] == "{" {
                    literal.append("{")
                    index += 2
                    continue
                }
                guard let close = TokenTemplate.indexOfClose(characters, from: index) else {
                    errors.append(.unterminatedPlaceholder)
                    literal.append(character)
                    index += 1
                    continue
                }
                if !literal.isEmpty {
                    nodes.append(.literal(literal))
                    literal = ""
                }
                let body = String(characters[(index + 1)..<close])
                let (token, filters, filterErrors) = TokenTemplate.parseBody(body)
                errors.append(contentsOf: filterErrors)
                if token.isEmpty {
                    errors.append(.emptyToken)
                } else {
                    nodes.append(.placeholder(token: token, filters: filters))
                }
                index = close + 1
                continue
            }
            if character == "}" {
                if index + 1 < characters.count, characters[index + 1] == "}" {
                    literal.append("}")
                    index += 2
                    continue
                }
                literal.append("}")
                index += 1
                continue
            }
            literal.append(character)
            index += 1
        }
        if !literal.isEmpty { nodes.append(.literal(literal)) }

        self.nodes = nodes
        self.errors = errors
    }

    private static func indexOfClose(_ characters: [Character], from start: Int) -> Int? {
        var index = start + 1
        var quoted = false
        while index < characters.count {
            let character = characters[index]
            if character == "'" { quoted.toggle() }
            if character == "}", !quoted { return index }
            if character == "{", !quoted { return nil }
            index += 1
        }
        return nil
    }

    private static func parseBody(_ body: String) -> (String, [Filter], [TemplateError]) {
        var parts: [String] = []
        var current = ""
        var quoted = false
        for character in body {
            if character == "'" { quoted.toggle(); current.append(character); continue }
            if character == "|", !quoted {
                parts.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        parts.append(current)

        let token = parts.first?.trimmingCharacters(in: .whitespaces) ?? ""
        var filters: [Filter] = []
        var errors: [TemplateError] = []
        for raw in parts.dropFirst() {
            let text = raw.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            let name: String
            var argument: String?
            if let colon = text.firstIndex(of: ":") {
                name = String(text[text.startIndex..<colon]).trimmingCharacters(in: .whitespaces)
                argument = unquote(String(text[text.index(after: colon)...]))
            } else {
                name = text
            }
            guard TokenTemplate.knownFilters.contains(name) else {
                errors.append(.unknownFilter(name))
                continue
            }
            filters.append(Filter(name: name, argument: argument))
        }
        return (token, filters, errors)
    }

    private static func unquote(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed.hasPrefix("'"), trimmed.hasSuffix("'") else { return trimmed }
        let inner = String(trimmed.dropFirst().dropLast())
        // `replace:'a':'o'` is two quoted arguments, not one: stripping the
        // outer pair would leave «a':'o». Only a genuinely single-quoted
        // argument is unwrapped here; the filter splits its own pair.
        // `':'` rather than any apostrophe: the wrapping is kept for the
        // two-piece `replace:'a':'o'` form, and refusing to unwrap on *any*
        // apostrophe meant `default:'Mike's Mac'` came back with its quotes
        // still attached and wrote them into the folder name.
        return inner.contains("':'") ? trimmed : inner
    }

    static let knownFilters: Set<String> = [
        "date", "lower", "upper", "title", "slug", "ascii", "trim", "pad", "round",
        "truncate", "left", "right", "before", "after", "replace", "unit", "default", "or"
    ]

    // MARK: - Rendering

    /// Render, resolving each token through `resolve`. `counter` stays a hole
    /// so the pipeline can try 1, 2, 3… against the file system.
    func render(timeZone: TimeZone = .current,
                resolve: (String) -> TemplateValue?) -> RenderedTemplate {
        var parts: [RenderedTemplate.Part] = []

        func appendLiteral(_ text: String) {
            if case .literal(let previous)? = parts.last {
                parts[parts.count - 1] = .literal(previous + text)
            } else {
                parts.append(.literal(text))
            }
        }

        for node in nodes {
            switch node {
            case .literal(let text):
                appendLiteral(text)
            case .placeholder(let token, let filters):
                if token == "counter" {
                    let pad = filters.first { $0.name == "pad" }
                        .flatMap { $0.argument }
                        .flatMap { Int($0) } ?? 1
                    parts.append(.counter(pad: pad))
                    continue
                }
                var value = resolve(token)
                // `or:` chains to another token before anything is stringified.
                for filter in filters where filter.name == "or" {
                    guard value == nil || value?.isEmpty == true else { break }
                    if let next = filter.argument { value = resolve(next) }
                }
                let text = TokenTemplate.apply(filters, to: value, timeZone: timeZone)
                appendLiteral(TokenTemplate.pathTokens.contains(token)
                              ? TokenTemplate.escapePathValue(text)
                              : TokenTemplate.escapeValue(text))
            }
        }
        return RenderedTemplate(parts: parts)
    }

    private static func apply(_ filters: [Filter], to value: TemplateValue?,
                              timeZone: TimeZone) -> String {
        var current = value
        var text: String? = nil

        for filter in filters {
            switch filter.name {
            case "or":
                continue    // already resolved in render
            case "date":
                if case .date(let date)? = current, let format = filter.argument {
                    text = TemplateDates.string(date, format: format, timeZone: timeZone)
                    current = .text(text ?? "")
                }
            case "pad":
                // Clamped for the same reason `round:` is, two cases down:
                // `pad:999999999999` asks `String(repeating:count:)` for a
                // terabyte of zeros. Sixty-four digits is past any real name.
                let digits = min(max(Int(filter.argument ?? "") ?? 0, 0), 64)
                let rendered = text ?? stringify(current, timeZone: timeZone)
                // Nothing pads to nothing. Padding an absent value invented
                // one — `{invoice|pad:4}` became the literal folder «0000» —
                // and because `default:` only fires on empty text, it also
                // meant `{invoice|pad:4|default:'none'}` could never say
                // «none». `round:` and `unit:` already no-op on an absent
                // value; this is the one filter that did not.
                if !rendered.isEmpty {
                    text = rendered.count >= digits
                        ? rendered
                        : String(repeating: "0", count: digits - rendered.count) + rendered
                }
                current = .text(text ?? "")
            case "round":
                if case .number(let number)? = current {
                    // Clamped: `round:999999999999` would ask `String(format:)`
                    // for a trillion digits, and a Double carries about
                    // sixteen. One mistyped template should not be able to
                    // hang the editor's live preview.
                    let places = min(max(Int(filter.argument ?? "") ?? 0, 0), 16)
                    text = String(format: "%.\(places)f", number)
                    current = .text(text ?? "")
                }
            case "unit":
                if case .number(let number)? = current {
                    text = scale(number, unit: filter.argument ?? "human")
                    current = .text(text ?? "")
                }
            case "default":
                let rendered = text ?? stringify(current, timeZone: timeZone)
                if rendered.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    text = filter.argument ?? ""
                    current = .text(text ?? "")
                }
            default:
                let rendered = text ?? stringify(current, timeZone: timeZone)
                text = transform(rendered, filter: filter)
                current = .text(text ?? "")
            }
        }
        return text ?? stringify(current, timeZone: timeZone)
    }

    private static func transform(_ input: String, filter: Filter) -> String {
        switch filter.name {
        case "lower": return input.lowercased()
        case "upper": return input.uppercased()
        case "title": return input.capitalized
        case "trim": return input.trimmingCharacters(in: .whitespaces)
        case "ascii":
            return input.folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        case "slug":
            let folded = input
                .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .lowercased()
            let replaced = folded.replacingOccurrences(
                of: "[^a-z0-9]+", with: "-", options: .regularExpression
            )
            return replaced.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        case "truncate":
            let limit = Int(filter.argument ?? "") ?? input.count
            return String(input.prefix(max(0, limit))).trimmingCharacters(in: .whitespaces)
        case "left":
            let limit = Int(filter.argument ?? "") ?? input.count
            return String(input.prefix(max(0, limit)))
        case "right":
            let limit = Int(filter.argument ?? "") ?? input.count
            return String(input.suffix(max(0, limit)))
        case "before":
            guard let separator = filter.argument, let range = input.range(of: separator) else {
                return input
            }
            return String(input[input.startIndex..<range.lowerBound])
        case "after":
            guard let separator = filter.argument,
                  let range = input.range(of: separator, options: .backwards) else { return input }
            return String(input[range.upperBound...])
        case "replace":
            // replace:'FIND':'REPL' — plain strings, never a regex, so a
            // template can carry no ReDoS.
            guard let argument = filter.argument else { return input }
            let pieces = splitReplacement(argument)
            // An empty find matches at every position — `replace:'':'-'`
            // turns "ab" into "-a-b-". A malformed argument leaves the value
            // alone, which is what every other shape of it already does.
            guard pieces.count == 2, !pieces[0].isEmpty else { return input }
            return input.replacingOccurrences(of: pieces[0], with: pieces[1])
        default:
            return input
        }
    }

    private static func splitReplacement(_ argument: String) -> [String] {
        var pieces: [String] = []
        var current = ""
        var quoted = false
        for character in argument {
            if character == "'" { quoted.toggle(); continue }
            if character == ":", !quoted {
                pieces.append(current)
                current = ""
                continue
            }
            current.append(character)
        }
        pieces.append(current)
        return pieces
    }

    private static func scale(_ bytes: Double, unit: String) -> String {
        switch unit.lowercased() {
        case "kb": return NumberText.canonical((bytes / 1000).rounded())
        case "mb": return NumberText.canonical((bytes / 1_000_000).rounded())
        case "gb": return NumberText.canonical((bytes / 1_000_000_000).rounded())
        default:
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            // `Int64(Double)` traps on NaN, on infinity, and outside Int64's
            // range — the same trapping conversion that crashed `TimeSpan`.
            return formatter.string(fromByteCount: Int64(exactly: bytes.rounded()) ?? 0)
        }
    }

    private static func stringify(_ value: TemplateValue?, timeZone: TimeZone) -> String {
        switch value {
        case .none: return ""
        case .text(let text)?: return text
        case .number(let number)?: return NumberText.canonical(number)
        case .list(let list)?: return list.joined(separator: ", ")
        case .date(let date)?:
            return TemplateDates.string(date, format: "yyyy-MM-dd", timeZone: timeZone)
        }
    }

    /// The four tokens that *are* paths, and therefore keep their separators:
    /// the model's answer (a relative path is what the model is asked for, and
    /// `Sanitizer.destination` sanitizes each component and rejects traversal)
    /// and the two that describe where the file was found.
    static let pathTokens: Set<String> = ["model.path", "model.folder", "relpath", "subfolder"]

    /// A path-shaped value: separators survive, but traversal and absolute
    /// paths cannot — `Sanitizer.destination` rejects those outright, and this
    /// keeps a leading slash from ever reaching it.
    static func escapePathValue(_ value: String) -> String {
        // Trimmed first. Stripping slashes before trimming missed the leading
        // slash on " /Users/…" — and a model answer arriving with a space or a
        // newline in front is entirely ordinary — so `Sanitizer` refused the
        // whole destination and the file was quietly left where it was.
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "\\", with: "/")
        // Trimming *inside* the loop, because one pass left the trim at the
        // end to re-expose a slash: "/ /tmp" lost its first slash, the final
        // trim removed the space behind it, and the function handed back
        // "/tmp" — the absolute path this whole function exists to prevent.
        while cleaned.hasPrefix("/") {
            cleaned.removeFirst()
            cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return cleaned
    }

    /// An interpolated value may never create a folder.
    ///
    /// `Sanitizer.destination` splits the relative path on `/` *before*
    /// sanitizing each component, so a `/` arriving inside a value — a title
    /// like "AC/DC", a where-from host, a model answer — would silently create
    /// a directory. Only literal separators written in the template do that.
    /// `Sanitizer.sanitizeComponent` still runs afterwards and remains the
    /// authority on forbidden characters, length and the `.`/`..` guard.
    static func escapeValue(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping
            .replacingOccurrences(of: "[/\\\\]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }
}

/// Template dates are rendered on a fixed locale and calendar.
///
/// A `DateFormatter` with the user's locale renders `yyyy` as a Buddhist or
/// Japanese-era year on some systems and month names in the UI language — a
/// destination folder must never depend on either.
enum TemplateDates {
    static func string(_ date: Date, format: String, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// EXIF spells its timestamps `yyyy:MM:dd HH:mm:ss` — colons in the date
    /// part included.
    static func exifDate(_ text: String, timeZone: TimeZone = .current) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.date(from: text)
    }
}
