import Foundation

/// Evaluates one condition against one file. Pure: everything it can know
/// arrives through `FileFacts`, so the same code answers "would this rule
/// match?" in the editor and "does this rule match?" in a scan.
enum ConditionEvaluator {
    struct TestResult: Equatable {
        var verdict: Verdict
        var actual: String?
        var captures: [String: String]

        init(_ verdict: Verdict, actual: String? = nil, captures: [String: String] = [:]) {
            self.verdict = verdict
            self.actual = actual
            self.captures = captures
        }
    }

    static func evaluate(_ test: ConditionTest, facts: FileFacts,
                         now: Date, calendar: Calendar) -> TestResult {
        let lookup = facts.lookup(test.attribute)
        let caseSensitive = test.caseSensitivity == .sensitive

        // Emptiness is the one question a missing fact can still answer.
        if test.op == .isEmpty || test.op == .isNotEmpty {
            switch lookup {
            case .available(let value):
                let empty = isEmpty(value)
                let wantEmpty = test.op == .isEmpty
                return TestResult(empty == wantEmpty ? .pass : .fail, actual: value.display())
            case .unavailable:
                return TestResult(test.op == .isEmpty ? .pass : .fail, actual: nil)
            case .blockedByPrivacy: return TestResult(.blockedByPrivacy)
            case .tooExpensive: return TestResult(.tooExpensive)
            case .unknownAttribute: return TestResult(.unknownAttribute)
            case .needsModel: return TestResult(.needsModel)
            }
        }

        let value: FactValue
        switch lookup {
        case .available(let found): value = found
        case .unavailable: return TestResult(.unavailable)
        case .blockedByPrivacy: return TestResult(.blockedByPrivacy)
        case .tooExpensive: return TestResult(.tooExpensive)
        case .unknownAttribute: return TestResult(.unknownAttribute)
        case .needsModel: return TestResult(.needsModel)
        }

        let actual = value.display()
        switch value {
        case .string(let text):
            return string(test, subject: text, caseSensitive: caseSensitive, actual: actual,
                          pathShaped: isPathShaped(test.attribute))
        case .strings(let values):
            return stringList(test, subject: values, caseSensitive: caseSensitive, actual: actual)
        case .number(let number):
            return numeric(test, subject: number, actual: actual)
        case .date(let date):
            return dates(test, subject: date, now: now, calendar: calendar, actual: actual)
        case .bool(let flag):
            switch test.op {
            case .isTrue: return TestResult(flag ? .pass : .fail, actual: actual)
            case .isFalse: return TestResult(flag ? .fail : .pass, actual: actual)
            case .equals, .eq:
                guard let expected = ValueCoercion.bool(test.value) else {
                    return TestResult(.invalidValue, actual: actual)
                }
                return TestResult(flag == expected ? .pass : .fail, actual: actual)
            default: return TestResult(.unknownOperator, actual: actual)
            }
        case .kind(let kind):
            return kinds(test, subject: kind, actual: actual)
        }
    }

    // MARK: - Per-type operators

    private static func string(_ test: ConditionTest, subject: String, caseSensitive: Bool,
                               actual: String?, pathShaped: Bool) -> TestResult {
        let folded = TextKey.fold(subject, caseSensitive: caseSensitive)

        func expectedText() -> String? {
            ValueCoercion.string(test.value).map { TextKey.fold($0, caseSensitive: caseSensitive) }
        }

        switch test.op {
        case .equals, .eq:
            guard let expected = expectedText() else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(folded == expected ? .pass : .fail, actual: actual)
        case .isNot, .ne:
            guard let expected = expectedText() else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(folded == expected ? .fail : .pass, actual: actual)
        case .contains:
            guard let expected = expectedText() else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(folded.contains(expected) ? .pass : .fail, actual: actual)
        case .notContains:
            guard let expected = expectedText() else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(folded.contains(expected) ? .fail : .pass, actual: actual)
        case .beginsWith:
            guard let expected = expectedText() else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(folded.hasPrefix(expected) ? .pass : .fail, actual: actual)
        case .endsWith:
            guard let expected = expectedText() else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(folded.hasSuffix(expected) ? .pass : .fail, actual: actual)
        case .isIn, .notIn:
            let options = ValueCoercion.strings(test.value)
                .map { TextKey.fold($0, caseSensitive: caseSensitive) }
            guard !options.isEmpty else { return TestResult(.invalidValue, actual: actual) }
            let hit = options.contains(folded)
            return TestResult((test.op == .isIn) == hit ? .pass : .fail, actual: actual)
        case .matchesGlob, .notMatchesGlob:
            guard let pattern = ValueCoercion.string(test.value), !pattern.isEmpty else {
                return TestResult(.invalidValue, actual: actual)
            }
            let glob = Glob(pattern: pattern, caseSensitive: caseSensitive,
                            matchesSeparator: !pathShaped)
            guard !glob.branches.isEmpty else { return TestResult(.invalidPattern, actual: actual) }
            let hit = glob.matches(subject)
            return TestResult((test.op == .matchesGlob) == hit ? .pass : .fail, actual: actual)
        case .matchesRegex, .notMatchesRegex:
            guard let pattern = ValueCoercion.string(test.value), !pattern.isEmpty else {
                return TestResult(.invalidValue, actual: actual)
            }
            guard DeterministicEngine.isSafeRegex(pattern) else {
                return TestResult(.invalidPattern, actual: actual)
            }
            // NFC on both sides so an accented pattern matches a decomposed
            // name; case is left alone so captures keep the file's spelling.
            let match = RegexCache.firstMatch(
                pattern: pattern.precomposedStringWithCanonicalMapping,
                in: subject.precomposedStringWithCanonicalMapping,
                caseSensitive: caseSensitive
            )
            let hit = match != nil
            let verdict: Verdict = (test.op == .matchesRegex) == hit ? .pass : .fail
            // Captures are only useful from a *matching* positive test.
            if test.op == .matchesRegex, let match {
                return TestResult(verdict, actual: actual, captures: match.captures)
            }
            return TestResult(verdict, actual: actual)
        case .conformsTo:
            guard let expected = ValueCoercion.string(test.value) else {
                return TestResult(.invalidValue, actual: actual)
            }
            return TestResult(KindResolver.conforms(subject, to: expected) ? .pass : .fail, actual: actual)
        default:
            return TestResult(.unknownOperator, actual: actual)
        }
    }

    private static func stringList(_ test: ConditionTest, subject: [String],
                                   caseSensitive: Bool, actual: String?) -> TestResult {
        let folded = subject.map { TextKey.fold($0, caseSensitive: caseSensitive) }
        let expected = ValueCoercion.strings(test.value)
            .map { TextKey.fold($0, caseSensitive: caseSensitive) }

        switch test.op {
        // Every expected value, not just the first. `isIn` means "the subject
        // is one of these", so reading one entry of the list was never right;
        // and `notIn` failed *open* — "tags notIn work, urgent" passed for a
        // file tagged `urgent`, because only `work` was ever looked at. These
        // now read exactly as `containsAny` and `containsNone` below.
        case .contains, .isIn:
            guard !expected.isEmpty else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(expected.contains { folded.contains($0) } ? .pass : .fail, actual: actual)
        case .notContains, .notIn:
            guard !expected.isEmpty else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(expected.contains { folded.contains($0) } ? .fail : .pass, actual: actual)
        case .containsAny:
            guard !expected.isEmpty else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(expected.contains { folded.contains($0) } ? .pass : .fail, actual: actual)
        case .containsAll:
            guard !expected.isEmpty else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(expected.allSatisfy { folded.contains($0) } ? .pass : .fail, actual: actual)
        case .containsNone:
            guard !expected.isEmpty else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(expected.contains { folded.contains($0) } ? .fail : .pass, actual: actual)
        case .equals, .eq:
            // The same guard every branch above carries. Without it a blank
            // value coerces to no strings and `folded == expected` reads as
            // «this file has no tags» — a rule the user did not write, passing
            // silently, instead of the misconfiguration it is.
            guard !expected.isEmpty else { return TestResult(.invalidValue, actual: actual) }
            return TestResult(folded == expected ? .pass : .fail, actual: actual)
        case .matchesGlob, .notMatchesGlob:
            guard let pattern = ValueCoercion.string(test.value), !pattern.isEmpty else {
                return TestResult(.invalidValue, actual: actual)
            }
            let glob = Glob(pattern: pattern, caseSensitive: caseSensitive)
            // Same guard the scalar path has: an uncompilable pattern is
            // `.invalidPattern`, not a silent non-match.
            guard !glob.branches.isEmpty else { return TestResult(.invalidPattern, actual: actual) }
            let hit = subject.contains { glob.matches($0) }
            return TestResult((test.op == .matchesGlob) == hit ? .pass : .fail, actual: actual)
        default:
            return TestResult(.unknownOperator, actual: actual)
        }
    }

    private static func numeric(_ test: ConditionTest, subject: Double, actual: String?) -> TestResult {
        if test.op == .between {
            guard let (lower, upper) = ValueCoercion.range(test.value) else {
                return TestResult(.invalidValue, actual: actual)
            }
            return TestResult(subject >= lower && subject <= upper ? .pass : .fail, actual: actual)
        }
        guard let expected = ValueCoercion.number(test.value) else {
            return TestResult(.invalidValue, actual: actual)
        }
        switch test.op {
        case .eq, .equals: return TestResult(subject == expected ? .pass : .fail, actual: actual)
        case .ne, .isNot: return TestResult(subject != expected ? .pass : .fail, actual: actual)
        case .gt: return TestResult(subject > expected ? .pass : .fail, actual: actual)
        case .gte: return TestResult(subject >= expected ? .pass : .fail, actual: actual)
        case .lt: return TestResult(subject < expected ? .pass : .fail, actual: actual)
        case .lte: return TestResult(subject <= expected ? .pass : .fail, actual: actual)
        default: return TestResult(.unknownOperator, actual: actual)
        }
    }

    private static func dates(_ test: ConditionTest, subject: Date, now: Date,
                              calendar: Calendar, actual: String?) -> TestResult {
        switch test.op {
        case .before, .lt:
            guard let expected = ValueCoercion.date(test.value, calendar: calendar) else {
                return TestResult(.invalidValue, actual: actual)
            }
            return TestResult(subject < expected ? .pass : .fail, actual: actual)
        case .after, .gt:
            guard let expected = ValueCoercion.date(test.value, calendar: calendar) else {
                return TestResult(.invalidValue, actual: actual)
            }
            return TestResult(subject > expected ? .pass : .fail, actual: actual)
        case .olderThan, .newerThan, .inLast, .notInLast:
            guard let span = ValueCoercion.timeSpan(test.value),
                  let cutoff = span.cutoff(from: now, calendar: calendar) else {
                return TestResult(.invalidValue, actual: actual)
            }
            // Strict comparisons, exactly matching the legacy
            // olderThanDays/newerThanDays semantics.
            let older = subject < cutoff
            switch test.op {
            case .olderThan: return TestResult(older ? .pass : .fail, actual: actual)
            case .newerThan, .inLast: return TestResult(older ? .fail : .pass, actual: actual)
            // Named, not defaulted: the outer case lists exactly four
            // operators, so a fifth added there would silently inherit
            // `notInLast`'s answer instead of failing the switch.
            case .notInLast: return TestResult(older ? .pass : .fail, actual: actual)
            default: return TestResult(.unknownOperator, actual: actual)
            }
        default:
            return TestResult(.unknownOperator, actual: actual)
        }
    }

    private static func kinds(_ test: ConditionTest, subject: Kind, actual: String?) -> TestResult {
        let expected = ValueCoercion.strings(test.value).map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        guard !expected.isEmpty else { return TestResult(.invalidValue, actual: actual) }
        let hit = expected.contains(subject.rawValue.lowercased())
        switch test.op {
        case .equals, .eq, .isIn, .contains: return TestResult(hit ? .pass : .fail, actual: actual)
        case .isNot, .ne, .notIn, .notContains: return TestResult(hit ? .fail : .pass, actual: actual)
        default: return TestResult(.unknownOperator, actual: actual)
        }
    }

    // MARK: - Helpers

    private static func isEmpty(_ value: FactValue) -> Bool {
        switch value {
        case .string(let text): return text.trimmingCharacters(in: .whitespaces).isEmpty
        case .strings(let values): return values.isEmpty
        case .number(let number): return number == 0
        case .bool(let flag): return !flag
        case .date: return false
        case .kind(let kind): return kind.rawValue.isEmpty
        }
    }

    /// Whether `*` should stop at a path separator for this attribute:
    /// `Invoices/*.pdf` on `relpath` means "directly inside Invoices", while
    /// `*amazon.de*` on a download URL has to cross slashes.
    private static func isPathShaped(_ attribute: Attribute) -> Bool {
        attribute == .relPath || attribute == .subfolder
    }
}
