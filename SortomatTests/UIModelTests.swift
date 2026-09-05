import XCTest
@testable import Sortomat

/// The value types behind the main window. They exist to be testable without a
/// window on screen — the mode mapping in particular is what stops "enabled +
/// preview only" from ever being shown as two unrelated switches again.
final class UIModelTests: XCTestCase {
    override func tearDown() {
        L10n.forcedLanguage = nil
    }

    private func rule(enabled: Bool, dryRun: Bool, watch: String = "/w", name: String = "R") -> Rule {
        Rule(name: name, enabled: enabled, watchPath: watch, targetPath: "/t", dryRun: dryRun)
    }

    // MARK: - RuleMode

    func testModeReadsTheTwoStoredBooleans() {
        XCTAssertEqual(RuleMode(rule(enabled: true, dryRun: false)), .automatic)
        XCTAssertEqual(RuleMode(rule(enabled: true, dryRun: true)), .askFirst)
        XCTAssertEqual(RuleMode(rule(enabled: false, dryRun: true)), .off)
        XCTAssertEqual(RuleMode(rule(enabled: false, dryRun: false)), .off)
    }

    func testModeRoundTripsThroughTheStoredShape() {
        // Nothing downstream — config.json, the CLI, rule packs — learns a new
        // shape, so the picker has to write back to the booleans exactly.
        for mode in RuleMode.allCases {
            var r = rule(enabled: false, dryRun: false)
            mode.apply(to: &r)
            XCTAssertEqual(RuleMode(r), mode, "\(mode) did not survive the round trip")
        }
    }

    func testTurningARuleOffKeepsWhichWayItWouldRun() {
        // Off is not "and also forget you wanted to be asked first": switching
        // back on must not silently promote an ask-first rule to automatic.
        var r = rule(enabled: true, dryRun: true)
        RuleMode.off.apply(to: &r)
        XCTAssertFalse(r.enabled)
        XCTAssertTrue(r.dryRun, "the ask-first preference survives being switched off")
        RuleMode.askFirst.apply(to: &r)
        XCTAssertEqual(RuleMode(r), .askFirst)
    }

    func testEveryModeHasALabelAndAnExplanation() {
        for language in ["en", "de"] {
            L10n.forcedLanguage = language
            for mode in RuleMode.allCases {
                XCTAssertFalse(mode.label.isEmpty)
                XCTAssertNotEqual(mode.label, "mode.\(mode.rawValue)", "\(language) label missing")
                XCTAssertNotEqual(mode.help, "mode.\(mode.rawValue).help", "\(language) help missing")
            }
        }
    }

    // MARK: - Heat

    func testHeatBucketsCoverTheWholeRange() {
        XCTAssertEqual(Heat(confidence: 1.0), .certain)
        XCTAssertEqual(Heat(confidence: 0.9), .certain)
        XCTAssertEqual(Heat(confidence: 0.89), .sure)
        XCTAssertEqual(Heat(confidence: 0.75), .sure)
        XCTAssertEqual(Heat(confidence: 0.74), .probably)
        XCTAssertEqual(Heat(confidence: 0.5), .probably)
        XCTAssertEqual(Heat(confidence: 0.49), .unsure)
        XCTAssertEqual(Heat(confidence: 0), .unsure)
    }

    func testNoConfidenceIsUnsureNotCertain() {
        // A missing number means the model didn't say. Reading that as "fine"
        // is exactly the fail-open the quarantine exists to prevent.
        XCTAssertEqual(Heat(confidence: nil), .unsure)
    }

    func testEveryHeatHasAWord() {
        for language in ["en", "de"] {
            L10n.forcedLanguage = language
            for heat in [Heat.certain, .sure, .probably, .unsure, .exact] {
                XCTAssertFalse(heat.label.isEmpty)
                XCTAssertFalse(heat.label.hasPrefix("heat."), "\(language): \(heat) renders its key")
            }
        }
    }

    // MARK: - InboxItem

    private func plan(origin: PlannedAction.Origin, confidence: Double?,
                      destination: String = "/t/Invoices/x.pdf") -> PlannedAction {
        PlannedAction(
            ruleID: UUID(), ruleName: "R", source: URL(fileURLWithPath: "/w/x.pdf"),
            kind: .move, destination: URL(fileURLWithPath: destination),
            origin: origin, reason: "because", confidence: confidence, copyInsteadOfMove: false
        )
    }

    func testAStepDecisionIsAnExactMatchWhateverTheConfidence() {
        let item = InboxItem(plan: plan(origin: .preRule, confidence: nil),
                             target: URL(fileURLWithPath: "/t"), ruleMode: .automatic)
        XCTAssertEqual(item.heat, .exact)
    }

    func testAModelDecisionUsesItsConfidence() {
        let item = InboxItem(plan: plan(origin: .model, confidence: 0.8),
                             target: URL(fileURLWithPath: "/t"), ruleMode: .automatic)
        XCTAssertEqual(item.heat, .sure)
        XCTAssertEqual(item.destinationText, "Invoices/x.pdf")
    }

    func testEveryOriginSaysWhereTheDecisionCameFrom() {
        L10n.forcedLanguage = "en"
        let origins: [PlannedAction.Origin] = [.preRule, .model, .taxonomy, .confidence, .system]
        var seen: Set<String> = []
        for origin in origins {
            let item = InboxItem(plan: plan(origin: origin, confidence: 0.5),
                                 target: URL(fileURLWithPath: "/t"), ruleMode: .automatic)
            XCTAssertFalse(item.originText.hasPrefix("origin."), "\(origin) renders its key")
            seen.insert(item.originText)
        }
        XCTAssertEqual(seen.count, origins.count, "two origins read the same to a user")
    }

    // MARK: - RuleGroup

    func testRulesGroupByTheFolderTheyWatch() {
        let rules = [
            rule(enabled: true, dryRun: false, watch: "/a", name: "one"),
            rule(enabled: true, dryRun: false, watch: "/b", name: "two"),
            rule(enabled: true, dryRun: false, watch: "/a", name: "three"),
        ]
        let groups = RuleGroup.group(rules)
        XCTAssertEqual(groups.map(\.watchPath), ["/a", "/b"], "first-seen order, not sorted")
        XCTAssertEqual(groups[0].rules.map(\.name), ["one", "three"])
        XCTAssertEqual(groups[1].rules.map(\.name), ["two"])
    }

    func testTildeAndExpandedFormsOfOneFolderAreOneGroup() {
        // "~/Downloads" and "/Users/x/Downloads" are the same folder; showing
        // them as two sections would be a bug the user can't do anything about.
        let home = NSHomeDirectory()
        let rules = [
            rule(enabled: true, dryRun: false, watch: "~/Downloads", name: "one"),
            rule(enabled: true, dryRun: false, watch: "\(home)/Downloads", name: "two"),
        ]
        let groups = RuleGroup.group(rules)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].rules.count, 2)
        XCTAssertEqual(groups[0].title, "~/Downloads")
    }

    func testAFolderlessRuleStillGetsASection() {
        L10n.forcedLanguage = "en"
        let groups = RuleGroup.group([rule(enabled: false, dryRun: false, watch: "")])
        XCTAssertEqual(groups.count, 1)
        XCTAssertFalse(groups[0].title.isEmpty)
        XCTAssertFalse(groups[0].title.hasPrefix("sidebar."))
    }

    // MARK: - SidebarSelection

    func testOnlyARuleSelectionCarriesARuleID() {
        let id = UUID()
        XCTAssertEqual(SidebarSelection.rule(id).ruleID, id)
        XCTAssertNil(SidebarSelection.inbox.ruleID)
        XCTAssertNil(SidebarSelection.history.ruleID)
    }

    // MARK: - FileSummary

    func testFileSummaryReadsTheFileAndSurvivesAMissingOne() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sortomat-ui-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Report 2024.pdf")
        try Data(count: 4096).write(to: file)

        let present = FileSummary(url: file)
        XCTAssertTrue(present.exists)
        XCTAssertEqual(present.name, "Report 2024.pdf")
        XCTAssertFalse(present.sizeText.isEmpty)
        XCTAssertNotNil(present.modified)

        // A plan whose file vanished must still render a row rather than trap.
        let gone = FileSummary(url: dir.appendingPathComponent("nope.pdf"))
        XCTAssertFalse(gone.exists)
        XCTAssertEqual(gone.name, "nope.pdf")
        XCTAssertEqual(gone.modifiedText, "")
    }
}
