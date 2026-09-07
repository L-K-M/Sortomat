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
        for language in L10n.supportedLanguages {
            L10n.forcedLanguage = language
            for mode in RuleMode.allCases {
                XCTAssertFalse(mode.label.isEmpty)
                XCTAssertNotEqual(mode.label, "mode.\(mode.rawValue)", "\(language) label missing")
                // Empty is its own failure: a key that exists but holds "" is
                // a blank explanation next to the mode that acts without
                // asking, and the key-fallback check alone passes it.
                XCTAssertFalse(mode.help.isEmpty, "\(language): \(mode.rawValue) help is empty")
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
        for language in L10n.supportedLanguages {
            L10n.forcedLanguage = language
            // `allCases`, not a hand-written list: a new tier with no German
            // label would otherwise ship with this test still green.
            for heat in Heat.allCases {
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
        // Restored rather than left set: `setUp` clears it for *this* class,
        // which does nothing for whichever class the runner picks next.
        let previous = L10n.forcedLanguage
        L10n.forcedLanguage = "en"
        addTeardownBlock { L10n.forcedLanguage = previous }
        func label(_ origin: PlannedAction.Origin) -> String {
            InboxItem(plan: plan(origin: origin, confidence: 0.5),
                      target: URL(fileURLWithPath: "/t"), ruleMode: .automatic).originText
        }
        for origin in PlannedAction.Origin.allCases {
            XCTAssertFalse(label(origin).hasPrefix("origin."), "\(origin) renders its key")
            XCTAssertFalse(label(origin).isEmpty, "\(origin) says nothing")
        }
        // The distinctness this used to assert across *every* case: `.preRule`
        // is the engine's old spelling of `.step` and is no longer produced,
        // so the two deliberately read the same rather than being told apart
        // by a distinction a user does not have. What must stay distinct is
        // the promise each one makes.
        XCTAssertEqual(label(.preRule), label(.step))
        for pair in [(PlannedAction.Origin.step, PlannedAction.Origin.model),
                     (.model, .taxonomy), (.taxonomy, .confidence),
                     (.confidence, .fallback), (.fallback, .system),
                     (.step, .fallback)] {
            XCTAssertNotEqual(label(pair.0), label(pair.1),
                              "\(pair.0) and \(pair.1) read the same to a user")
        }
    }

    func testAStepDecisionIsExactAndAFallbackIsNot() {
        // A step asked no model, so there is no confidence to report and
        // "Certain" would understate it. A fallback parking a file it could
        // not place is the definition of unsure.
        func heat(_ origin: PlannedAction.Origin) -> Heat {
            InboxItem(plan: plan(origin: origin, confidence: nil),
                      target: URL(fileURLWithPath: "/t"), ruleMode: .automatic).heat
        }
        XCTAssertEqual(heat(.step), .exact)
        XCTAssertEqual(heat(.preRule), .exact)
        XCTAssertEqual(heat(.fallback), .unsure)
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

    func testATrailingSlashIsNotASecondSection() {
        // Both name the same folder, and a real config.json contains both.
        let groups = RuleGroup.group([
            rule(enabled: true, dryRun: false, watch: "/Users/x/Downloads", name: "one"),
            rule(enabled: true, dryRun: false, watch: "/Users/x/Downloads/", name: "two"),
            rule(enabled: true, dryRun: false, watch: "/Users/x/./Downloads", name: "three"),
        ])
        XCTAssertEqual(groups.count, 1, "a trailing slash split one folder into two sections")
        XCTAssertEqual(groups[0].rules.count, 3)
    }

    func testTheFileSummaryIsReadOnceNotOnEveryRender() throws {
        // As a computed property this stat-ed the disk on every access, so a
        // full Inbox turned each list invalidation into one blocking read per
        // row — and two renders of the same row could disagree.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sortomat-summary-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("x.pdf")
        try Data(count: 16).write(to: file)

        let item = InboxItem(
            plan: PlannedAction(ruleID: UUID(), ruleName: "R", source: file, kind: .move,
                                destination: dir.appendingPathComponent("out/x.pdf"),
                                origin: .model, reason: "r", confidence: 0.9,
                                copyInsteadOfMove: false),
            target: dir, ruleMode: .automatic
        )
        let first = item.summary
        try Data(count: 4096).write(to: file)
        XCTAssertEqual(item.summary, first, "the snapshot must not change under the row")
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
