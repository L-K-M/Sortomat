import XCTest
@testable import Sortomat

/// The validator is what stands between a rule that looks right in the editor
/// and a rule that quietly does nothing for a week.
final class RuleValidatorTests: XCTestCase {
    // A rule that is fine, so every test below asserts a *difference*.
    private func healthyRule(steps: [RuleStep]) -> Rule {
        Rule(name: "Invoices", watchPath: "~/Downloads", targetPath: "~/Documents",
             prompt: "File invoices", steps: steps, fallback: .skip)
    }

    private func step(_ when: ConditionGroup, _ then: [RuleAction],
                      name: String = "Step") -> RuleStep {
        RuleStep(name: name, when: when, then: then)
    }

    private func when(_ attribute: Attribute, _ op: Operator,
                      _ value: ConditionValue) -> Condition {
        .test(ConditionTest(attribute: attribute, op: op, value: value))
    }

    private func codes(_ rule: Rule) -> [String] {
        RuleValidator.findings(for: rule).map(\.code)
    }

    func testAHealthyRuleIsSilent() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                 [RuleAction(type: .move, template: "Invoices/{name}")])
        ])
        XCTAssertEqual(RuleValidator.findings(for: rule), [], "got: \(codes(rule))")
        XCTAssertNil(RuleValidator.headline([]))
    }

    func testAnEmptyAnyGroupCanNeverMatch() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .any, items: []),
                 [RuleAction(type: .move, template: "{name}")])
        ])
        XCTAssertTrue(codes(rule).contains("step.neverMatches"))
    }

    func testAStepThatClaimsEveryFileHidesTheOnesAfterIt() {
        let greedy = step(ConditionGroup(mode: .all, items: []),
                          [RuleAction(type: .move, template: "{name}")], name: "Everything")
        let later = step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                         [RuleAction(type: .move, template: "PDFs/{name}")], name: "PDFs")
        XCTAssertTrue(codes(healthyRule(steps: [greedy, later])).contains("step.unreachable"))

        // …unless it hands the file on.
        var handsOn = greedy
        handsOn.then.append(RuleAction(type: .proceed))
        XCTAssertFalse(codes(healthyRule(steps: [handsOn, later])).contains("step.unreachable"))
    }

    func testAStepMayOnlyDecideOnePlacement() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                 [RuleAction(type: .move, template: "{name}"), RuleAction(type: .trash)])
        ])
        XCTAssertTrue(codes(rule).contains("step.twoPlacements"))
    }

    func testAMatchingStepThatDoesNothingIsAnError() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]), [])
        ])
        XCTAssertTrue(codes(rule).contains("step.noActions"))
    }

    func testUnknownAttributesAndOperatorsAreNamed() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [
                .test(ConditionTest(attribute: Attribute("colour"), op: .equals, value: .text("red"))),
                .test(ConditionTest(attribute: .name, op: Operator("rhymesWith"), value: .text("x")))
            ]), [RuleAction(type: .move, template: "{name}")])
        ])
        let found = codes(rule)
        XCTAssertTrue(found.contains("condition.unknownAttribute"))
        XCTAssertTrue(found.contains("condition.unknownOperator"))
    }

    func testAnOperatorThatNeedsAValueSaysSo() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.name, .contains, .none)]),
                 [RuleAction(type: .move, template: "{name}")])
        ])
        XCTAssertTrue(codes(rule).contains("condition.noValue"))

        // `isEmpty` asks about the fact itself and takes none.
        let valueless = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.tags, .isEmpty, .none)]),
                 [RuleAction(type: .move, template: "{name}")])
        ])
        XCTAssertFalse(codes(valueless).contains("condition.noValue"))
    }

    func testAContentConditionUnderMetadataOnlyIsRejectedInTheEditor() {
        var rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.text, .contains, .text("Rechnung"))]),
                 [RuleAction(type: .move, template: "{name}")])
        ])
        XCTAssertFalse(codes(rule).contains("condition.blockedByPrivacy"))
        rule.privacyMode = .metadataOnly
        XCTAssertTrue(codes(rule).contains("condition.blockedByPrivacy"))
    }

    func testARegexTheEngineRefusesToRunIsFlagged() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [
                when(.name, .matchesRegex, .text("(a+)+$"))
            ]), [RuleAction(type: .move, template: "{name}")])
        ])
        XCTAssertTrue(codes(rule).contains("condition.unsafeRegex"))
    }

    func testABrokenDestinationIsAnErrorAndAnUnknownTokenIsANote() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                 [RuleAction(type: .move, template: "{year}/{name")])
        ])
        let found = codes(rule)
        XCTAssertTrue(found.contains("action.badTemplate"), "got: \(found)")
        XCTAssertTrue(found.contains("action.unknownToken"), "got: \(found)")
    }

    func testADestinationWhoseLastPartCanRenderEmptyIsANote() {
        let risky = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                 [RuleAction(type: .move, template: "Invoices/{title}")])
        ])
        XCTAssertTrue(codes(risky).contains("action.nameCanBeEmpty"))

        // `{name}` always renders, so the same shape with a real fallback is fine.
        let safe = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                 [RuleAction(type: .move, template: "Invoices/{title} {name}")])
        ])
        XCTAssertFalse(codes(safe).contains("action.nameCanBeEmpty"))
    }

    func testAnActionCannotNameADestinationFolderThatDoesNotExist() {
        var rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                 [RuleAction(type: .move, template: "{name}", root: "Archive")])
        ])
        XCTAssertTrue(codes(rule).contains("action.unknownRoot"))
        rule.destinationRoots = [DestinationRoot(name: "Archive", path: "~/Archive")]
        XCTAssertFalse(codes(rule).contains("action.unknownRoot"))
    }

    func testAskingTheModelWithNoInstructionIsAnError() {
        var rule = healthyRule(steps: [])
        rule.prompt = ""
        rule.fallback = .askModel
        XCTAssertTrue(codes(rule).contains("rule.modelWithoutPrompt"))
    }

    func testACaptureWithNothingCapturingIsANote() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.name, .contains, .text("Rechnung"))]),
                 [RuleAction(type: .move, template: "{match.1}/{name}")])
        ])
        XCTAssertTrue(codes(rule).contains("action.captureWithoutSource"))

        let capturing = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [
                when(.name, .matchesRegex, .text("^(\\d{4})"))
            ]), [RuleAction(type: .move, template: "{match.1}/{name}")])
        ])
        XCTAssertFalse(codes(capturing).contains("action.captureWithoutSource"))
    }

    func testErrorsSortAboveNotesAndTheHeadlineCountsThem() {
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.name, .contains, .none)]),
                 [RuleAction(type: .move, template: "Invoices/{title}")])
        ])
        let findings = RuleValidator.findings(for: rule)
        XCTAssertEqual(findings.first?.severity, .error)
        XCTAssertEqual(findings.last?.severity, .warning)
        XCTAssertEqual(RuleValidator.headline(findings), L10n.plural("validate.errors", 1))
    }

    func testEveryFindingCarriesTheStepItBelongsTo() {
        let broken = step(ConditionGroup(mode: .any, items: []), [])
        let rule = healthyRule(steps: [broken])
        let findings = RuleValidator.findings(for: rule)
        XCTAssertFalse(findings.isEmpty)
        for finding in findings {
            XCTAssertEqual(finding.stepID, broken.id, finding.code)
        }
    }
}
