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

    func testAGroupHoldingOnlyEmptyGroupsIsStillAHorizon() {
        // `all` of [empty `all`] is vacuously true exactly like an empty
        // `all`, and the editor can build it — `condition.emptyGroup` reports
        // the inner one. Looking only at the top level meant every step after
        // it kept its silence.
        let greedy = step(ConditionGroup(mode: .all, items: [
            .group(ConditionGroup(mode: .all, items: []))
        ]), [RuleAction(type: .move, template: "{name}")])
        let later = step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                         [RuleAction(type: .move, template: "PDFs/{name}")], name: "Later")
        XCTAssertTrue(codes(healthyRule(steps: [greedy, later])).contains("step.unreachable"))
        // One real condition beside it and the step claims nothing in
        // particular, so nothing after it is unreachable.
        let mixed = step(ConditionGroup(mode: .all, items: [
            .group(ConditionGroup(mode: .all, items: [])),
            when(.ext, .equals, .text("png"))
        ]), [RuleAction(type: .move, template: "{name}")])
        XCTAssertFalse(codes(healthyRule(steps: [mixed, later])).contains("step.unreachable"))
    }

    func testABetweenThatIsNotAPairIsAnError() {
        // The old check pattern-matched `.list` first, so a `between` carrying
        // a single text value — the shape a hand-edited rule gets wrong — was
        // the one shape that validated.
        for value in [ConditionValue.text("1"), .number(1), .list(["1"]), .list(["1", "2", "3"])] {
            let rule = healthyRule(steps: [
                step(ConditionGroup(mode: .all, items: [.test(ConditionTest(
                    attribute: .size, op: .between, value: value))]),
                     [RuleAction(type: .move, template: "{name}")])
            ])
            XCTAssertTrue(codes(rule).contains("condition.betweenNeedsTwo"), "accepted \(value)")
        }
        let pair = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [.test(ConditionTest(
                attribute: .size, op: .between, value: .list(["1", "2"])))]),
                 [RuleAction(type: .move, template: "{name}")])
        ])
        XCTAssertFalse(codes(pair).contains("condition.betweenNeedsTwo"))
    }

    func testADestinationEndingInASlashNamesTheFileAfterTheFolder() {
        // `Sanitizer.destination` discards the empty last component, so
        // «Invoices/» files the document as «Invoices.pdf» at the target root.
        // The most extreme version of the empty-name problem was the one the
        // check could not see.
        let risky = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                 [RuleAction(type: .move, template: "Invoices/")])
        ])
        XCTAssertTrue(codes(risky).contains("action.nameCanBeEmpty"))
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

    func testAPrivacySafeConditionIsNotCalledImpossible() {
        // `duplicateInTarget` reads the target folder's index and never opens
        // a file, so it works exactly as well under metadata-only. Reading the
        // *cost* tier as "opens the file" put a red error on a rule that
        // works — the one thing this validator may never do.
        var rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.duplicateInTarget, .isTrue, .none)]),
                 [RuleAction(type: .skip)])
        ])
        rule.privacyMode = .metadataOnly
        XCTAssertEqual(RuleValidator.findings(for: rule), [], "got: \(codes(rule))")
    }

    func testAnAttributeSpotlightUsuallyKnowsIsANoteNotAnError() {
        // `title` asks Spotlight first and only falls back to reading the
        // file, so under metadata-only it still matches — for indexed files.
        // That is worth saying and is not "can never match".
        var rule = healthyRule(steps: [
            step(ConditionGroup(mode: .all, items: [when(.title, .contains, .text("Hobbit"))]),
                 [RuleAction(type: .move, template: "{name}")])
        ])
        rule.privacyMode = .metadataOnly
        let findings = RuleValidator.findings(for: rule)
        XCTAssertEqual(findings.map(\.code), ["condition.metadataOnlyValue"])
        XCTAssertEqual(findings.first?.severity, .warning)
    }

    func testTheEditorsContentFlagIsTheValidatorsOwn() {
        // Two hand-kept lists of "does this read the file" had already
        // drifted. The catalog derives its flag from the engine now, so the
        // hint in the row and the finding under it cannot disagree again.
        for spec in RuleCatalog.attributes {
            XCTAssertEqual(spec.needsContent,
                           FileFacts.alwaysNeedsContent.contains(spec.attribute),
                           spec.attribute.rawValue)
        }
        XCTAssertFalse(RuleCatalog.spec(for: .duplicateInTarget)?.needsContent ?? true)
        XCTAssertTrue(RuleCatalog.spec(for: .text)?.needsContent ?? false)
    }

    func testEveryFindingIsDrawnSomewhereInTheEditor() {
        // `RuleIssues` shows the rule-level findings and the step card draws
        // the rest against the row they name. A finding that is neither — a
        // step id with no row and no `.step` site — would be invisible.
        let rule = healthyRule(steps: [
            step(ConditionGroup(mode: .any, items: []), []),
            step(ConditionGroup(mode: .all, items: [when(.name, .contains, .none)]),
                 [RuleAction(type: .move, template: "Invoices/{title}", root: "Nowhere")])
        ])
        for finding in RuleValidator.findings(for: rule) {
            let drawn = finding.stepID == nil          // RuleIssues
                || finding.isAboutStepItself           // the card
                || finding.conditionID != nil          // a condition row
                || finding.actionID != nil             // an action row
            XCTAssertTrue(drawn, "\(finding.code) has nowhere to be drawn")
        }
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
        // The name of this test is a claim about *severity* — a rule that
        // cannot do what it says versus one that works and surprises its
        // author — and it was asserting only that both were mentioned.
        let findings = RuleValidator.findings(for: rule)
        XCTAssertEqual(findings.first { $0.code == "action.badTemplate" }?.severity, .error)
        // `.warning` is the enum's spelling of what the docs call a note:
        // a rule that works and probably surprises its author.
        XCTAssertEqual(findings.first { $0.code == "action.unknownToken" }?.severity, .warning)
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

    // MARK: - Counting one step

    func testCountingAStepAsksAboutThatStepAlone() {
        let first = step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("pdf"))]),
                         [RuleAction(type: .move, template: "PDFs/{name}")], name: "PDFs")
        let second = step(ConditionGroup(mode: .all, items: [when(.ext, .equals, .text("png"))]),
                          [RuleAction(type: .move, template: "Images/{name}")], name: "Images")
        var rule = healthyRule(steps: [first, second])
        rule.fallback = .askModel
        rule.prompt = "sort them"

        let probe = AppState.probe(rule, step: second)
        XCTAssertEqual(probe.steps, [second], "a step is counted on its own, not after the ones before it")
        // With the rule's own `askModel` fallback left in place, every file the
        // step did not claim would have counted as a match.
        XCTAssertEqual(probe.fallback, .skip)
        XCTAssertEqual(probe.watchPath, rule.watchPath, "counted against the same folder")
        XCTAssertEqual(probe.extensions, rule.extensions)
    }
}
