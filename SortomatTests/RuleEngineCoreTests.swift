import XCTest
import UniformTypeIdentifiers
@testable import Sortomat

/// A fact source with no file system behind it: the whole point of the engine
/// being pure is that this is enough to test every rule.
struct StubFactSource: FactSource {
    var stat = StatFacts()
    var metadata = MetadataFacts()
    var header = HeaderFacts()
    var content = ContentFacts()
    var resolvedKind: Kind?
    var duplicate = false

    func statFacts() -> StatFacts { stat }
    func metadataFacts() -> MetadataFacts { metadata }
    func headerFacts() -> HeaderFacts { header }
    func contentFacts() -> ContentFacts { content }
    func kind() -> Kind? { resolvedKind }
    func isDuplicateInTarget() -> Bool { duplicate }
}

final class GlobTests: XCTestCase {
    private func matches(_ pattern: String, _ name: String, caseSensitive: Bool = false) -> Bool {
        Glob(pattern: pattern, caseSensitive: caseSensitive).matches(name)
    }

    func testBraceSetsMatchInsteadOfBecomingLiterals() {
        // The old engine escaped { } into literal characters, so this pattern —
        // what anyone who has used a shell writes — matched nothing at all.
        XCTAssertTrue(matches("*.{jpg,png,heic}", "holiday.png"))
        XCTAssertTrue(matches("*.{jpg,png,heic}", "holiday.jpg"))
        XCTAssertFalse(matches("*.{jpg,png,heic}", "holiday.gif"))
    }

    func testCharacterClasses() {
        XCTAssertTrue(matches("IMG_[0-9][0-9][0-9][0-9].jpg", "IMG_2026.jpg"))
        XCTAssertFalse(matches("IMG_[0-9][0-9][0-9][0-9].jpg", "IMG_20a6.jpg"))
        XCTAssertTrue(matches("[!x]ile.txt", "file.txt"))
        XCTAssertFalse(matches("[!x]ile.txt", "xile.txt"))
    }

    func testMatchingIsAnchoredToTheWholeName() {
        XCTAssertFalse(matches("Screenshot", "Screenshot 2026-01-01.png"))
        XCTAssertTrue(matches("*Screenshot*", "Screenshot 2026-01-01.png"))
        XCTAssertFalse(matches("*.jpg", "photo.jpg.txt"))
    }

    func testDecomposedNamesMatchComposedPatterns() {
        // A name from an HFS+ volume is NFD; a pattern typed into a text field
        // is NFC. Before folding, this never matched.
        let decomposed = "A\u{0308}rzte.pdf"
        XCTAssertTrue(matches("*Ärzte*", decomposed))
        XCTAssertTrue(matches("Ärzte.pdf", decomposed))
    }

    func testCaseSensitivityIsOptOut() {
        XCTAssertTrue(matches("*.JPG", "photo.jpg"))
        XCTAssertFalse(matches("*.JPG", "photo.jpg", caseSensitive: true))
    }

    func testSingleStarStopsAtSeparatorInPathMode() {
        let shallow = Glob(pattern: "Invoices/*.pdf", matchesSeparator: false)
        XCTAssertTrue(shallow.matches("Invoices/one.pdf"))
        XCTAssertFalse(shallow.matches("Invoices/2026/one.pdf"))
        let deep = Glob(pattern: "Invoices/**.pdf", matchesSeparator: false)
        XCTAssertTrue(deep.matches("Invoices/2026/one.pdf"))
    }

    func testEscapedMetacharacters() {
        XCTAssertTrue(matches("a\\*b.txt", "a*b.txt"))
        XCTAssertFalse(matches("a\\*b.txt", "axxb.txt"))
    }
}

final class ValueCoercionTests: XCTestCase {
    func testDurationSuffixMonthsBeatsMinutes() {
        // "mo" has to be tested before "m", or three months is three minutes —
        // exactly the kind of bug a blind implementation ships.
        XCTAssertEqual(ValueCoercion.parseTimeSpan("3mo"), TimeSpan(amount: 3, unit: .months))
        XCTAssertEqual(ValueCoercion.parseTimeSpan("3m"), TimeSpan(amount: 3, unit: .minutes))
    }

    func testBareNumberMeansDays() {
        XCTAssertEqual(ValueCoercion.timeSpan(.number(30)), TimeSpan(amount: 30, unit: .days))
        XCTAssertEqual(ValueCoercion.parseTimeSpan("30"), TimeSpan(amount: 30, unit: .days))
    }

    func testByteSuffixes() {
        XCTAssertEqual(ValueCoercion.parseNumber("500MB"), 500_000_000)
        XCTAssertEqual(ValueCoercion.parseNumber("1.5GB"), 1_500_000_000)
        XCTAssertEqual(ValueCoercion.parseNumber("4KiB"), 4096)
        XCTAssertEqual(ValueCoercion.parseNumber("12"), 12)
        XCTAssertNil(ValueCoercion.parseNumber("later"))
    }

    func testCalendarArithmeticUsesRealMonths() {
        let calendar = Calendar(identifier: .gregorian)
        let now = DateComponents(calendar: calendar, year: 2026, month: 3, day: 31).date!
        let cutoff = TimeSpan(amount: 1, unit: .months).cutoff(from: now, calendar: calendar)
        let expected = calendar.date(byAdding: .month, value: -1, to: now)
        XCTAssertEqual(cutoff, expected)
    }
}

final class TokenTemplateTests: XCTestCase {
    private func render(_ template: String,
                        _ values: [String: TemplateValue] = [:]) -> String {
        TokenTemplate(template)
            .render(timeZone: TimeZone(identifier: "UTC")!) { values[$0] }
            .string()
    }

    func testInterpolatedValuesCannotCreateFolders() {
        // Sanitizer.destination splits on "/" *before* sanitizing components,
        // so a slash inside a value would silently make a directory.
        XCTAssertEqual(render("{title}.mp3", ["title": .text("AC/DC — Back in Black")]),
                       "AC DC — Back in Black.mp3")
        XCTAssertEqual(render("{title}", ["title": .text("a\\b")]), "a b")
    }

    func testLiteralSeparatorsStillMakeFolders() {
        XCTAssertEqual(render("{year}/{name}", ["year": .text("2026"), "name": .text("x.pdf")]),
                       "2026/x.pdf")
    }

    func testEscapedBraces() {
        XCTAssertEqual(render("{{literal}}"), "{literal}")
    }

    func testDateFilterIsGregorianAndPOSIX() {
        let date = Date(timeIntervalSince1970: 1_767_225_600)   // 2026-01-01T00:00:00Z
        XCTAssertEqual(render("{d|date:'yyyy-MM'}", ["d": .date(date)]), "2026-01")
        XCTAssertEqual(render("{d|date:'MMMM'}", ["d": .date(date)]), "January")
    }

    func testFallbackChain() {
        XCTAssertEqual(render("{a|or:b|default:'none'}", ["b": .text("second")]), "second")
        XCTAssertEqual(render("{a|or:b|default:'none'}"), "none")
    }

    func testFilters() {
        XCTAssertEqual(render("{s|slug}", ["s": .text("Wärme & Kälte")]), "warme-kalte")
        XCTAssertEqual(render("{s|upper}", ["s": .text("abc")]), "ABC")
        XCTAssertEqual(render("{n|pad:4}", ["n": .number(7)]), "0007")
        XCTAssertEqual(render("{s|before:'-'}", ["s": .text("ACME-2026")]), "ACME")
        XCTAssertEqual(render("{s|after:'-'}", ["s": .text("ACME-2026")]), "2026")
        XCTAssertEqual(render("{s|replace:'a':'o'}", ["s": .text("cat")]), "cot")
    }

    func testCounterIsAHoleTheCallerFills() {
        let rendered = TokenTemplate("{stem}-{counter|pad:3}.{ext}")
            .render { token in
                token == "stem" ? .text("shot") : (token == "ext" ? .text("png") : nil)
            }
        XCTAssertTrue(rendered.hasCounter)
        XCTAssertEqual(rendered.string(counter: 2), "shot-002.png")
    }

    func testUnknownFilterIsReportedRatherThanSwallowed() {
        let template = TokenTemplate("{name|frobnicate}")
        XCTAssertFalse(template.isValid)
        XCTAssertEqual(template.errors, [.unknownFilter("frobnicate")])
    }

    func testUnterminatedPlaceholderIsReported() {
        XCTAssertEqual(TokenTemplate("{name").errors, [.unterminatedPlaceholder])
    }
}

final class ConditionEvaluatorTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private func facts(name: String = "Rechnung ACME 2026-03-01.pdf",
                       source: StubFactSource = StubFactSource(),
                       policy: FileFacts.ContentPolicy = .allowed) -> FileFacts {
        let root = URL(fileURLWithPath: "/watch")
        return FileFacts(url: root.appendingPathComponent(name), watchRoot: root,
                         source: source, contentPolicy: policy)
    }

    private func evaluate(_ test: ConditionTest, _ facts: FileFacts,
                          now: Date = Date()) -> ConditionEvaluator.TestResult {
        ConditionEvaluator.evaluate(test, facts: facts, now: now, calendar: calendar)
    }

    func testExtensionAndNameOperators() {
        let file = facts()
        XCTAssertEqual(evaluate(ConditionTest(attribute: .ext, op: .equals, value: .text("pdf")), file).verdict, .pass)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .name, op: .beginsWith, value: .text("Rechnung")), file).verdict, .pass)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .stem, op: .contains, value: .text("acme")), file).verdict, .pass)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .ext, op: .isIn, value: .list(["pdf", "epub"])), file).verdict, .pass)
    }

    func testAMissingFactIsUnavailableNotFalse() {
        // "This photo has no capture date" and "this photo was taken in 2019"
        // are different answers to "why didn't my rule fire".
        let result = evaluate(ConditionTest(attribute: .dateCaptured, op: .olderThan, value: .text("30d")), facts())
        XCTAssertEqual(result.verdict, .unavailable)
        XCTAssertNil(result.actual)
    }

    func testContentConditionUnderMetadataOnlyIsBlockedNotFailed() {
        let file = facts(source: StubFactSource(content: ContentFacts(text: "secret")),
                         policy: .blocked)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .text, op: .contains, value: .text("secret")), file).verdict,
                       .blockedByPrivacy)
    }

    func testSizeAcceptsHumanUnits() {
        let file = facts(source: StubFactSource(stat: StatFacts(size: 900_000_000)))
        XCTAssertEqual(evaluate(ConditionTest(attribute: .size, op: .gt, value: .text("500MB")), file).verdict, .pass)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .size, op: .lt, value: .text("500MB")), file).verdict, .fail)
    }

    func testAgeUsesTheDateItIsAskedFor() {
        let now = Date()
        let old = now.addingTimeInterval(-60 * 86_400)
        // The whole point of P1: a file downloaded today whose mtime is old is
        // *new* by dateAdded and *old* by dateModified, and the rule says which.
        let file = facts(source: StubFactSource(stat: StatFacts(dateAdded: now, dateModified: old)))
        XCTAssertEqual(evaluate(ConditionTest(attribute: .dateModified, op: .olderThan, value: .text("30d")), file, now: now).verdict, .pass)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .dateAdded, op: .olderThan, value: .text("30d")), file, now: now).verdict, .fail)
    }

    func testTagsAreListOperators() {
        let file = facts(source: StubFactSource(stat: StatFacts(tags: ["Wichtig", "Steuer"])))
        XCTAssertEqual(evaluate(ConditionTest(attribute: .tags, op: .contains, value: .text("steuer")), file).verdict, .pass)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .tags, op: .containsAll, value: .list(["Steuer", "Wichtig"])), file).verdict, .pass)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .tags, op: .containsNone, value: .list(["Privat"])), file).verdict, .pass)
    }

    func testRegexCapturesAreHarvested() {
        let file = facts(name: "INV-2026-114.pdf")
        let test = ConditionTest(attribute: .stem, op: .matchesRegex,
                                 value: .text("INV-(?<year>[0-9]{4})-([0-9]+)"))
        let result = evaluate(test, file)
        XCTAssertEqual(result.verdict, .pass)
        XCTAssertEqual(result.captures["year"], "2026")
        XCTAssertEqual(result.captures["2"], "114")
    }

    func testAnUnknownAttributeIsReportedNotCrashed() {
        let result = evaluate(ConditionTest(attribute: Attribute("fromTheFuture"), op: .equals, value: .text("x")), facts())
        XCTAssertEqual(result.verdict, .unknownAttribute)
    }

    func testAnUnknownOperatorIsReported() {
        let result = evaluate(ConditionTest(attribute: .name, op: Operator("rhymesWith"), value: .text("x")), facts())
        XCTAssertEqual(result.verdict, .unknownOperator)
    }

    func testAnUnsafeRegexIsRejectedRatherThanRun() {
        let test = ConditionTest(attribute: .name, op: .matchesRegex, value: .text("(a+)+$"))
        XCTAssertEqual(evaluate(test, facts()).verdict, .invalidPattern)
    }

    func testEmptinessAnswersEvenForAMissingFact() {
        XCTAssertEqual(evaluate(ConditionTest(attribute: .comment, op: .isEmpty), facts()).verdict, .pass)
        XCTAssertEqual(evaluate(ConditionTest(attribute: .comment, op: .isNotEmpty), facts()).verdict, .fail)
    }
}

final class RuleEvaluatorTests: XCTestCase {
    private func rule(_ steps: [RuleStep], fallback: Rule.Fallback = .skip) -> Rule {
        Rule(name: "R", watchPath: "/watch", targetPath: "/target",
             steps: steps, fallback: fallback)
    }

    private func context(_ rule: Rule, name: String = "Rechnung ACME.pdf",
                         source: StubFactSource = StubFactSource(),
                         allowModel: Bool = true) -> RuleEvaluator.Context {
        let root = URL(fileURLWithPath: "/watch")
        let facts = FileFacts(url: root.appendingPathComponent(name), watchRoot: root,
                              source: source)
        return RuleEvaluator.Context(rule: rule, facts: facts,
                                     timeZone: TimeZone(identifier: "UTC")!,
                                     allowModel: allowModel)
    }

    private func step(_ name: String, _ test: ConditionTest, _ actions: [RuleAction]) -> RuleStep {
        RuleStep(name: name, when: ConditionGroup(mode: .all, items: [.test(test)]), then: actions)
    }

    func testFirstMatchWins() {
        let rule = rule([
            step("Invoices", ConditionTest(attribute: .ext, op: .equals, value: .text("pdf")),
                 [RuleAction(type: .move, template: "Finanzen/{stem}.{ext}")]),
            step("Everything", ConditionTest(attribute: .name, op: .matchesGlob, value: .text("*")),
                 [RuleAction(type: .move, template: "Rest/{name}")])
        ])
        guard case .decided(let placement, let trace) = RuleEvaluator.evaluate(context(rule)) else {
            return XCTFail("expected a decision")
        }
        XCTAssertEqual(placement.operation, .move)
        XCTAssertEqual(placement.relativePath?.string(), "Finanzen/Rechnung ACME.pdf")
        XCTAssertEqual(trace.steps.count, 1, "a claimed file must not be walked further")
        XCTAssertTrue(trace.summary.contains("Invoices"))
    }

    func testContinueLetsALaterStepDecide() {
        let rule = rule([
            step("Tag it", ConditionTest(attribute: .ext, op: .equals, value: .text("pdf")),
                 [RuleAction(type: .addTags, tags: ["Rechnung"]), RuleAction(type: .proceed)]),
            step("File it", ConditionTest(attribute: .name, op: .matchesGlob, value: .text("*")),
                 [RuleAction(type: .move, template: "Finanzen/{name}")])
        ])
        guard case .decided(let placement, _) = RuleEvaluator.evaluate(context(rule)) else {
            return XCTFail("expected a decision")
        }
        XCTAssertEqual(placement.relativePath?.string(), "Finanzen/Rechnung ACME.pdf")
        XCTAssertEqual(placement.sideEffects.first?.values, ["Rechnung"])
    }

    func testFallbackSkipsWhenNothingMatched() {
        let rule = rule([
            step("Images", ConditionTest(attribute: .ext, op: .equals, value: .text("png")),
                 [RuleAction(type: .move, template: "Bilder/{name}")])
        ])
        guard case .decided(let placement, let trace) = RuleEvaluator.evaluate(context(rule)) else {
            return XCTFail("expected a decision")
        }
        XCTAssertEqual(placement.operation, .skip)
        XCTAssertEqual(trace.fallbackUsed, .skip)
    }

    func testModelIsRequestedOnlyWhenAllowed() {
        let rule = rule([
            step("Ask", ConditionTest(attribute: .ext, op: .equals, value: .text("pdf")),
                 [RuleAction(type: .askModel)])
        ])
        guard case .needsModel(let request, let token, _) = RuleEvaluator.evaluate(context(rule)) else {
            return XCTFail("expected a model request")
        }
        XCTAssertEqual(request.stepIndex, 0)

        guard case .deferred = RuleEvaluator.evaluate(context(rule, allowModel: false)) else {
            return XCTFail("without a key or budget the file must defer, not decide")
        }

        let answer = ModelAnswer(relativePath: "Finanzen/2026/ACME.pdf", confidence: 0.9)
        guard case .decided(let placement, _) = RuleEvaluator.resume(token, answer: answer,
                                                                    context: context(rule)) else {
            return XCTFail("expected a decision after the model answered")
        }
        XCTAssertEqual(placement.relativePath?.string(), "Finanzen/2026/ACME.pdf")
        XCTAssertEqual(placement.confidence, 0.9)
    }

    func testCapturesReachTheDestination() {
        let test = ConditionTest(attribute: .stem, op: .matchesRegex,
                                 value: .text("^Rechnung (?<vendor>[A-Za-z]+)"))
        let rule = rule([
            step("Invoices", test, [RuleAction(type: .move, template: "Finanzen/{match.vendor}/{name}")])
        ])
        guard case .decided(let placement, _) = RuleEvaluator.evaluate(context(rule)) else {
            return XCTFail("expected a decision")
        }
        XCTAssertEqual(placement.relativePath?.string(), "Finanzen/ACME/Rechnung ACME.pdf")
    }

    func testNoneGroupNamesTheCulprit() {
        let group = ConditionGroup(mode: .none, items: [
            .test(ConditionTest(attribute: .ext, op: .equals, value: .text("pdf")))
        ])
        let rule = rule([RuleStep(name: "Not PDFs", when: group,
                                  then: [RuleAction(type: .move, template: "X/{name}")])])
        guard case .decided(_, let trace) = RuleEvaluator.evaluate(context(rule)) else {
            return XCTFail("expected a decision")
        }
        XCTAssertEqual(trace.steps.first?.matched, false)
        XCTAssertEqual(trace.steps.first?.culpritIndex, 0)
    }

    func testCheapConditionsAreEvaluatedFirst() {
        // The expensive one must never be reached once the free one fails.
        let group = ConditionGroup(mode: .all, items: [
            .test(ConditionTest(attribute: .text, op: .contains, value: .text("anything"))),
            .test(ConditionTest(attribute: .ext, op: .equals, value: .text("png")))
        ])
        let rule = rule([RuleStep(name: "S", when: group, then: [RuleAction(type: .skip)])])
        guard case .decided(_, let trace) = RuleEvaluator.evaluate(context(rule)) else {
            return XCTFail("expected a decision")
        }
        let tests = trace.steps.first?.tests ?? []
        XCTAssertEqual(tests.count, 2)
        XCTAssertEqual(tests[0].verdict, .notEvaluated, "the content condition must not be reached")
        XCTAssertEqual(tests[1].verdict, .fail)
    }
}

final class RuleCodableTests: XCTestCase {
    private func decodeRule(_ json: String) throws -> Rule {
        try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
    }

    func testAValueFromANewerBuildDecodesInsteadOfThrowing() throws {
        // A String enum would throw here, and ConfigStore would move the
        // user's whole rule set aside as corrupt.
        let rule = try decodeRule("""
        {"name":"R","fallback":"teleport","steps":[
          {"name":"S","when":{"all":[{"attribute":"telepathy","op":"vibesWith","value":"x"}]},
           "then":[{"type":"summon","to":"X/{name}"}]}]}
        """)
        XCTAssertEqual(rule.fallback, .askModel)
        XCTAssertEqual(rule.steps.count, 1)
        XCTAssertEqual(rule.steps[0].then[0].type, ActionType("summon"))
    }

    func testGroupSugarRoundTripsToTheCanonicalForm() throws {
        let rule = try decodeRule("""
        {"name":"R","steps":[{"name":"S","when":{"any":[
          {"attr":"ext","op":"is","value":"pdf"},
          {"all":[{"attr":"size","op":"gt","value":"1MB"}]}]},"then":[]}]}
        """)
        let group = rule.steps[0].when
        XCTAssertEqual(group.mode, .any)
        XCTAssertEqual(group.items.count, 2)
        if case .test(let test) = group.items[0] {
            XCTAssertEqual(test.attribute, .ext)
            XCTAssertEqual(test.value, .text("pdf"))
        } else {
            XCTFail("first item must decode as a test")
        }
        if case .group(let nested) = group.items[1] {
            XCTAssertEqual(nested.mode, .all)
        } else {
            XCTFail("second item must decode as a group")
        }

        let encoded = try JSONEncoder().encode(rule)
        let round = try JSONDecoder().decode(Rule.self, from: encoded)
        XCTAssertEqual(round.steps[0].when.mode, .any)
        XCTAssertEqual(round.steps[0].when.items.count, 2)
    }

    func testALegacyConfigIsMarkedAsSchemaOne() throws {
        let rule = try decodeRule(#"{"name":"R","preRules":[]}"#)
        XCTAssertEqual(rule.schemaVersion, 1, "a config with no schema key is a legacy config")
        XCTAssertTrue(rule.steps.isEmpty)
    }

    func testValuesKeepTheirJSONType() throws {
        let rule = try decodeRule("""
        {"name":"R","steps":[{"when":{"all":[
          {"attr":"size","op":"gt","value":25},
          {"attr":"isHidden","op":"isTrue","value":true},
          {"attr":"ext","op":"in","value":["pdf","epub"]},
          {"attr":"dateAdded","op":"olderThan","value":"30d"}]},"then":[]}]}
        """)
        let items = rule.steps[0].when.items
        guard case .test(let size) = items[0], case .test(let hidden) = items[1],
              case .test(let list) = items[2], case .test(let age) = items[3] else {
            return XCTFail("all four must decode as tests")
        }
        XCTAssertEqual(size.value, .number(25))
        XCTAssertEqual(hidden.value, .bool(true))
        XCTAssertEqual(list.value, .list(["pdf", "epub"]))
        XCTAssertEqual(age.value, .text("30d"))
    }
}

final class KindResolverTests: XCTestCase {
    func testEveryCatalogUTIResolves() {
        // A misspelled identifier would silently kill a whole kind, so it is a
        // red test rather than a mystery.
        for (kind, identifiers) in KindResolver.conformance {
            for identifier in identifiers {
                XCTAssertNotNil(UTType(identifier),
                                "\(kind.rawValue): «\(identifier)» does not resolve")
            }
        }
    }

    func testExtensionTableStillAnswers() {
        XCTAssertEqual(KindResolver.kind(forExtension: "epub"), .ebook)
        XCTAssertEqual(KindResolver.kind(forExtension: "PNG"), .image)
        XCTAssertEqual(KindResolver.kind(forExtension: "dmg"), .diskImage)
        XCTAssertNil(KindResolver.kind(forExtension: ""))
    }

    func testMagicBytesClassifyExtensionlessFiles() {
        XCTAssertEqual(MagicBytes.kind(sniffing: Data([0x25, 0x50, 0x44, 0x46, 0x2D])), .pdf)
        XCTAssertEqual(MagicBytes.kind(sniffing: Data([0xFF, 0xD8, 0xFF, 0xE0])), .image)
        XCTAssertEqual(MagicBytes.kind(sniffing: Data([0x50, 0x4B, 0x03, 0x04])), .archive)
        XCTAssertEqual(MagicBytes.kind(sniffing: Data("#!/bin/sh\n".utf8)), .text)
    }
}
