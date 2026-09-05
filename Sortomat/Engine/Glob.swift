import Foundation

/// A real glob compiler: `*`, `**`, `?`, `[a-z]`, `[!abc]` and `{jpg,png}`.
///
/// The old engine translated globs to regular expressions, which meant
/// `*.{jpg,png}` and `IMG_[0-9]*.jpg` — what anyone who has used a shell types
/// — were escaped into literals that matched nothing, and a pathological
/// pattern could turn into a `.*.*.*` regex. This matches directly, in
/// O(subject × pattern), with no regex engine involved.
///
/// Matching is anchored to the whole value, which is what Finder and Hazel do
/// and what the old engine did. The substring intent is served by the
/// `contains` / `beginsWith` / `endsWith` operators instead.
struct Glob {
    enum Token: Equatable {
        case literal(Character)
        case any                       // ?
        case star(crossesSeparator: Bool)  // * / **
        case set(Set<Character>, negated: Bool)
    }

    /// Alternations are expanded at compile time rather than matched, which
    /// keeps the matcher a simple linear scan. A pattern that would expand
    /// past this many branches keeps its braces as literal characters.
    static let maxBranches = 64

    let branches: [[Token]]
    let caseSensitive: Bool
    /// Whether `*` and `?` may cross a path separator. False for path-shaped
    /// attributes (`relpath`, `subfolder`), where `Invoices/*.pdf` must mean
    /// "directly inside Invoices"; true for names and free text, where a
    /// `*amazon.de*` pattern has to cross the slashes of a URL.
    let matchesSeparator: Bool

    init(pattern: String, caseSensitive: Bool = false, matchesSeparator: Bool = true) {
        self.caseSensitive = caseSensitive
        self.matchesSeparator = matchesSeparator
        let folded = TextKey.fold(pattern, caseSensitive: caseSensitive)
        self.branches = Glob.compile(folded)
    }

    func matches(_ subject: String) -> Bool {
        let folded = Array(TextKey.fold(subject, caseSensitive: caseSensitive))
        for branch in branches
        where Glob.match(branch, folded, matchesSeparator: matchesSeparator) { return true }
        return false
    }

    // MARK: - Compilation

    private static func compile(_ pattern: String) -> [[Token]] {
        var branches: [[Token]] = [[]]
        let characters = Array(pattern)
        var index = 0

        func append(_ token: Token) {
            for position in branches.indices { branches[position].append(token) }
        }

        while index < characters.count {
            let character = characters[index]
            switch character {
            case "\\" where index + 1 < characters.count:
                index += 1
                append(.literal(characters[index]))
            case "?":
                append(.any)
            case "*":
                if index + 1 < characters.count, characters[index + 1] == "*" {
                    index += 1
                    append(.star(crossesSeparator: true))
                } else {
                    append(.star(crossesSeparator: false))
                }
            case "[":
                if let (token, next) = parseSet(characters, from: index) {
                    append(token)
                    index = next
                } else {
                    append(.literal("["))
                }
            case "{":
                if let (options, next) = parseAlternation(characters, from: index),
                   branches.count * options.count <= maxBranches {
                    var expanded: [[Token]] = []
                    for branch in branches {
                        for option in options {
                            expanded.append(branch + compileLiteralRun(option))
                        }
                    }
                    branches = expanded
                    index = next
                } else {
                    append(.literal("{"))
                }
            default:
                append(.literal(character))
            }
            index += 1
        }
        return branches
    }

    /// A brace option is itself a small pattern (`{IMG_*,DSC_*}` is legal), but
    /// nested braces are not: they were already rejected by `parseAlternation`.
    private static func compileLiteralRun(_ option: String) -> [Token] {
        compile(option).first ?? []
    }

    private static func parseSet(_ characters: [Character], from start: Int) -> (Token, Int)? {
        var index = start + 1
        var negated = false
        if index < characters.count, characters[index] == "!" || characters[index] == "^" {
            negated = true
            index += 1
        }
        var members: Set<Character> = []
        var sawClose = false
        while index < characters.count {
            let character = characters[index]
            if character == "]", !members.isEmpty || index > start + 1 {
                sawClose = true
                break
            }
            if character == "\\", index + 1 < characters.count {
                index += 1
                members.insert(characters[index])
                index += 1
                continue
            }
            // A range: a-z.
            if index + 2 < characters.count, characters[index + 1] == "-", characters[index + 2] != "]" {
                let lower = characters[index]
                let upper = characters[index + 2]
                if let lowerValue = lower.unicodeScalars.first?.value,
                   let upperValue = upper.unicodeScalars.first?.value,
                   lowerValue <= upperValue, upperValue - lowerValue < 1024 {
                    for scalarValue in lowerValue...upperValue {
                        if let scalar = Unicode.Scalar(scalarValue) { members.insert(Character(scalar)) }
                    }
                    index += 3
                    continue
                }
            }
            members.insert(character)
            index += 1
        }
        guard sawClose else { return nil }
        return (.set(members, negated: negated), index)
    }

    private static func parseAlternation(_ characters: [Character], from start: Int) -> ([String], Int)? {
        var index = start + 1
        var options: [String] = []
        var current = ""
        while index < characters.count {
            let character = characters[index]
            if character == "\\", index + 1 < characters.count {
                current.append(characters[index])
                index += 1
                current.append(characters[index])
                index += 1
                continue
            }
            if character == "{" { return nil }   // nested alternations are not supported
            if character == "}" {
                options.append(current)
                return (options, index)
            }
            if character == "," {
                options.append(current)
                current = ""
                index += 1
                continue
            }
            current.append(character)
            index += 1
        }
        return nil
    }

    // MARK: - Matching

    /// The classic linear glob walk with one backtrack point per star, so the
    /// worst case is O(subject × pattern) rather than the exponential blow-up
    /// of naive recursion.
    private static func match(_ tokens: [Token], _ subject: [Character],
                              matchesSeparator: Bool) -> Bool {
        var subjectIndex = 0
        var tokenIndex = 0
        var starIndex = -1
        var starCrossesSeparator = false
        var resumeIndex = 0

        func consumes(_ token: Token, _ character: Character) -> Bool {
            switch token {
            case .literal(let expected): return expected == character
            case .any: return matchesSeparator || character != "/"
            case .set(let members, let negated): return members.contains(character) != negated
            case .star: return false
            }
        }

        while subjectIndex < subject.count {
            if tokenIndex < tokens.count, case .star(let crosses) = tokens[tokenIndex] {
                starIndex = tokenIndex
                starCrossesSeparator = crosses || matchesSeparator
                resumeIndex = subjectIndex
                tokenIndex += 1
                continue
            }
            if tokenIndex < tokens.count, consumes(tokens[tokenIndex], subject[subjectIndex]) {
                tokenIndex += 1
                subjectIndex += 1
                continue
            }
            guard starIndex >= 0 else { return false }
            // Widen the last star by one character — unless it is a single
            // star and that character is a path separator.
            if !starCrossesSeparator, subject[resumeIndex] == "/" { return false }
            resumeIndex += 1
            subjectIndex = resumeIndex
            tokenIndex = starIndex + 1
        }

        while tokenIndex < tokens.count, case .star = tokens[tokenIndex] { tokenIndex += 1 }
        return tokenIndex == tokens.count
    }
}
