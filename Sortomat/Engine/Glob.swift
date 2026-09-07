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
                // `!options.isEmpty` as well: a degenerate `{}` would leave
                // `branches` empty, and then `append` silently discards the
                // rest of the pattern and `matches` answers false for every
                // subject — one brace disabling a whole rule.
                if let (options, next) = parseAlternation(characters, from: index),
                   !options.isEmpty, branches.count * options.count <= maxBranches {
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
            // The first member slot sits one further along when a negation
            // marker was consumed, so `[!]]` means "anything but ]" rather
            // than an empty negated set followed by a stray literal.
            if character == "]", !members.isEmpty || index > start + (negated ? 2 : 1) {
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
        // One backtrack point per open star, not one for the whole match.
        //
        // The textbook single-point algorithm is only correct when every star
        // can absorb any character. Here `*` may not cross a separator, so a
        // dead end that kills the newest star is not the end of the match — an
        // earlier `**` may still stretch further and re-align everything after
        // it. With one shared point that earlier star's position had already
        // been overwritten, and the matcher gave up: `**/*.pdf` did not match
        // `a/b/c.pdf`, which is the most ordinary rule anyone would write.
        //
        // Still O(subject × pattern): a star's reach only ever advances.
        var backtrack: [(tokenIndex: Int, stretchedTo: Int, crossesSeparator: Bool)] = []
        var subjectIndex = 0
        var tokenIndex = 0

        func consumes(_ token: Token, _ character: Character) -> Bool {
            switch token {
            case .literal(let expected): return expected == character
            case .any: return matchesSeparator || character != "/"
            case .set(let members, let negated):
                // A negated set is still not a wildcard for "/": `[!a]` must
                // no more cross a separator than `?` does. An explicitly
                // listed "/" (`[/]`) still matches.
                let inSet = members.contains(character)
                if character == "/", !inSet, !matchesSeparator { return false }
                return inSet != negated
            case .star: return false
            }
        }

        while true {
            if tokenIndex == tokens.count, subjectIndex == subject.count { return true }
            if tokenIndex < tokens.count, case .star(let crosses) = tokens[tokenIndex] {
                backtrack.append((tokenIndex, subjectIndex, crosses || matchesSeparator))
                tokenIndex += 1
                continue
            }
            if tokenIndex < tokens.count, subjectIndex < subject.count,
               consumes(tokens[tokenIndex], subject[subjectIndex]) {
                tokenIndex += 1
                subjectIndex += 1
                continue
            }
            // Widen the newest star that can still absorb a character; a "/"
            // stops one that may not cross separators. A star that cannot
            // widen is abandoned and the one before it gets its turn.
            while let last = backtrack.last {
                if last.stretchedTo < subject.count,
                   last.crossesSeparator || subject[last.stretchedTo] != "/" {
                    backtrack[backtrack.count - 1].stretchedTo += 1
                    tokenIndex = last.tokenIndex + 1
                    subjectIndex = last.stretchedTo + 1
                    break
                }
                backtrack.removeLast()
            }
            if backtrack.isEmpty { return false }
        }
    }
}
