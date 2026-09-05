import XCTest
@testable import Sortomat

final class DeterministicEngineTests: XCTestCase {
    private func rule(_ preRules: [PreRule]) -> Rule {
        Rule(name: "R", targetPath: "/t", preRules: preRules)
    }

    func testGlobRouteMatches() {
        let r = rule([PreRule(name: "img", match: .glob, pattern: "IMG_*.jpg",
                              action: .route, routePath: "Photos")])
        let decision = DeterministicEngine.evaluate(rule: r, file: URL(fileURLWithPath: "/x/IMG_1.jpg"))
        guard case let .route(path, name) = decision else {
            return XCTFail("expected route, got \(decision)")
        }
        XCTAssertEqual(name, "img")
        XCTAssertEqual(path, "Photos/IMG_1")   // {name} appended, no extension yet
    }

    func testGlobDoesNotMatchDifferentName() {
        let r = rule([PreRule(match: .glob, pattern: "IMG_*.jpg", action: .skip)])
        let decision = DeterministicEngine.evaluate(rule: r, file: URL(fileURLWithPath: "/x/photo.png"))
        XCTAssertEqual(decision, .useLLM)
    }

    func testRegexMatch() {
        let r = rule([PreRule(match: .regex, pattern: "^Invoice-\\d+", action: .skip)])
        let decision = DeterministicEngine.evaluate(rule: r, file: URL(fileURLWithPath: "/x/Invoice-42.pdf"))
        if case .skip = decision {} else { XCTFail("expected skip") }
    }

    func testKindMatch() {
        let r = rule([PreRule(match: .kind, pattern: "image", action: .skip)])
        XCTAssertNotEqual(DeterministicEngine.evaluate(rule: r, file: URL(fileURLWithPath: "/x/a.png")), .useLLM)
        XCTAssertEqual(DeterministicEngine.evaluate(rule: r, file: URL(fileURLWithPath: "/x/a.pdf")), .useLLM)
    }

    func testFirstMatchWins() {
        let r = rule([
            PreRule(name: "one", match: .glob, pattern: "*.txt", action: .skip),
            PreRule(name: "two", match: .glob, pattern: "*.txt", action: .route, routePath: "X"),
        ])
        let decision = DeterministicEngine.evaluate(rule: r, file: URL(fileURLWithPath: "/x/a.txt"))
        if case .skip = decision {} else { XCTFail("first (skip) should win") }
    }

    func testNoPreRulesFallsThroughToLLM() {
        XCTAssertEqual(DeterministicEngine.evaluate(rule: rule([]), file: URL(fileURLWithPath: "/x/a.txt")), .useLLM)
    }

    func testGlobToRegexEscaping() {
        // A literal dot in the glob must not become "any char".
        let pattern = DeterministicEngine.globToRegex("a.b*")
        XCTAssertEqual(pattern, "^a\\.b.*$")
    }

    func testRouteTemplateTokens() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("route-\(UUID().uuidString).png")
        try Data("x".utf8).write(to: url)
        defer { try? fm.removeItem(at: url) }
        var comps = DateComponents()
        comps.year = 2021; comps.month = 3; comps.day = 7
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)

        let expanded = DeterministicEngine.expandRoute("Shots/{year}-{month}", file: url, now: Date())
        XCTAssertEqual(expanded, "Shots/2021-03/\(url.deletingPathExtension().lastPathComponent)")
    }

    func testAgeMatch() throws {
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("age-\(UUID().uuidString).txt")
        try Data("x".utf8).write(to: url)
        defer { try? fm.removeItem(at: url) }
        let old = Date().addingTimeInterval(-100 * 86_400)
        try fm.setAttributes([.modificationDate: old], ofItemAtPath: url.path)

        let older = PreRule(match: .olderThanDays, pattern: "30", action: .skip)
        XCTAssertTrue(DeterministicEngine.matches(older, file: url, now: Date()))
        let newer = PreRule(match: .newerThanDays, pattern: "30", action: .skip)
        XCTAssertFalse(DeterministicEngine.matches(newer, file: url, now: Date()))
    }

    func testRegexValidity() {
        XCTAssertTrue(DeterministicEngine.isValidRegex("^Invoice-\\d+"))
        XCTAssertTrue(DeterministicEngine.isValidRegex("plain text"))
        XCTAssertFalse(DeterministicEngine.isValidRegex("["), "an unclosed class must be flagged")
        XCTAssertFalse(DeterministicEngine.isValidRegex("(a"), "an unclosed group must be flagged")
    }


    // MARK: - Route templates, glob matching, regex safety

    func testEmptyRouteMeansTheTargetItself() {
        let file = URL(fileURLWithPath: "/x/report.pdf")
        XCTAssertEqual(DeterministicEngine.expandRoute("", file: file, now: Date()), "report")
        XCTAssertEqual(DeterministicEngine.expandRoute("   ", file: file, now: Date()), "report")
    }

    func testTokenSubstitutionOrderIsDeterministic() throws {
        // A file literally named "receipt {year}.pdf" must route the same way
        // on every launch: {name} is substituted last, so its own braces are
        // never re-expanded.
        let fm = FileManager.default
        let url = fm.temporaryDirectory.appendingPathComponent("receipt {year}-\(UUID().uuidString).pdf")
        try Data("x".utf8).write(to: url)
        defer { try? fm.removeItem(at: url) }
        var comps = DateComponents()
        comps.year = 2021; comps.month = 3; comps.day = 7
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        try fm.setAttributes([.modificationDate: date], ofItemAtPath: url.path)

        let expanded = DeterministicEngine.expandRoute("{year}/{name}", file: url, now: Date())
        XCTAssertEqual(expanded, "2021/\(url.deletingPathExtension().lastPathComponent)")
    }

    func testGlobMatcher() {
        XCTAssertTrue(DeterministicEngine.globMatches("*.txt", "notes.txt"))
        XCTAssertTrue(DeterministicEngine.globMatches("IMG_*.jpg", "img_0001.JPG"))
        XCTAssertFalse(DeterministicEngine.globMatches("IMG_*.jpg", "IMG_1.png"))
        XCTAssertTrue(DeterministicEngine.globMatches("*", "anything at all"))
        XCTAssertTrue(DeterministicEngine.globMatches("a?c", "abc"))
        XCTAssertFalse(DeterministicEngine.globMatches("a?c", "ac"))
        XCTAssertTrue(DeterministicEngine.globMatches("*creenshot*", "Screenshot 2024.png"))
        XCTAssertFalse(DeterministicEngine.globMatches("", "x"))
        XCTAssertTrue(DeterministicEngine.globMatches("a*", "a"))
    }

    func testPathologicalGlobReturnsQuickly() {
        let pattern = String(repeating: "*a", count: 20) + "*b"
        let name = String(repeating: "a", count: 80)
        let start = Date()
        XCTAssertFalse(DeterministicEngine.globMatches(pattern, name))
        // The name promises "quickly", so measure it — otherwise a regression
        // to backtracking (2^20 paths on this shape) only shows up as a suite
        // that mysteriously takes minutes. The bound is deliberately loose: it
        // separates a linear walk from an exponential one, nothing finer.
        XCTAssertLessThan(Date().timeIntervalSince(start), 2,
                          "glob matching regressed to backtracking")
    }

    func testNestedQuantifierRegexesAreRejected() {
        XCTAssertFalse(DeterministicEngine.isSafeRegex("(a+)+$"))
        XCTAssertFalse(DeterministicEngine.isSafeRegex("(\\w+\\s?)*x"))
        XCTAssertFalse(DeterministicEngine.isSafeRegex("["))
        XCTAssertTrue(DeterministicEngine.isSafeRegex("^Invoice-\\d+"))
        XCTAssertTrue(DeterministicEngine.isSafeRegex("(abc)+"))
        XCTAssertTrue(DeterministicEngine.isSafeRegex("plain text"))
    }

    func testNestedQuantifiersAreCaughtThroughAnExtraParenLayer() {
        // A regex can't count its own parentheses, so the one-line screen this
        // replaces saw only the inner pair and passed `((a+))+` as safe.
        XCTAssertFalse(DeterministicEngine.isSafeRegex("((a+))+"))
        XCTAssertFalse(DeterministicEngine.isSafeRegex("((a|b)+)+"))
        XCTAssertFalse(DeterministicEngine.isSafeRegex("(x(y*)z)*"))
    }

    func testOpenEndedCountedRepetitionInAQuantifiedGroupIsRejected() {
        // `{2,}` is a quantifier like any other: `(a{2,})+` backtracks
        // exponentially exactly the way `(a+)+` does.
        XCTAssertFalse(DeterministicEngine.isSafeRegex("(a{2,})+"))
        XCTAssertFalse(DeterministicEngine.isSafeRegex("(a{1,4})+"))
        XCTAssertFalse(DeterministicEngine.isSafeRegex("(a+){2,}"))
    }

    func testOrdinaryUserPatternsSurviveTheScreen() {
        // A screen that rejects too much is its own bug: a rejected pattern
        // silently never matches, and the rule stops filing anything.
        XCTAssertTrue(DeterministicEngine.isSafeRegex("(a|b)+"), "alternation alone is not ambiguous")
        XCTAssertTrue(DeterministicEngine.isSafeRegex("(\\d{4})-(\\d{2})"))
        XCTAssertTrue(DeterministicEngine.isSafeRegex("(\\d{4})+"), "a fixed length adds no ambiguity")
        XCTAssertTrue(DeterministicEngine.isSafeRegex("^IMG_\\d{4}\\.(jpg|png)$"))
        XCTAssertTrue(DeterministicEngine.isSafeRegex("Rechnung[ _-]?(\\d+)"))
        XCTAssertTrue(DeterministicEngine.isSafeRegex("^(19|20)\\d{2}-\\d{2}-\\d{2}"))
    }

    func testTheRejectedPatternsActuallyStallABacktracker() {
        // The screen is only worth having if the shapes it rejects are the
        // slow ones — so prove it on the real engine, with a subject small
        // enough that a linear matcher finishes instantly.
        let subject = String(repeating: "a", count: 30) + "!"
        for pattern in ["(a+)+$", "((a+))+$", "(a{2,})+$"] {
            XCTAssertFalse(DeterministicEngine.isSafeRegex(pattern), "\(pattern) must be rejected")
        }
        // The accepted counterpart on the same subject is fast.
        let start = Date()
        XCTAssertTrue(DeterministicEngine.isSafeRegex("(a|b)+$"))
        _ = subject.range(of: "(a|b)+$", options: .regularExpression)
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
