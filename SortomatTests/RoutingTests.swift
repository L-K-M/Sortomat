import XCTest
@testable import Sortomat

/// The safety valves between a model answer and a planned move.
final class RoutingTests: XCTestCase {
    private func rule(taxonomy: [String] = [], threshold: Double = 0, quarantine: String = "_Q") -> Rule {
        Rule(name: "R", targetPath: "/t", taxonomy: taxonomy,
             quarantineSubfolder: quarantine, confidenceThreshold: threshold)
    }

    func testTaxonomyIsEnforcedOnTheAppliedPath() throws {
        // `folder` names an allowed top folder, `relative_path` (which wins
        // for placement) points elsewhere: the placement path decides.
        let c = Classification(action: "move", relativePath: "Sonstiges/x.pdf",
                               folder: "Rechnungen", filename: "x.pdf", confidence: 0.9)
        let r = try Pipeline.routing(for: c, rule: rule(taxonomy: ["Rechnungen"]), fileName: "x.pdf")
        XCTAssertEqual(r.kind, .quarantine)
        XCTAssertEqual(r.origin, .taxonomy)
        XCTAssertEqual(r.relativePath, "_Q/x.pdf")
    }

    func testDotPrefixedPathPassesTaxonomy() throws {
        let c = Classification(action: "move", relativePath: "./Fantasy/x.epub", confidence: 0.9)
        let r = try Pipeline.routing(for: c, rule: rule(taxonomy: ["Fantasy"]), fileName: "x.epub")
        XCTAssertEqual(r.kind, .move)
        XCTAssertEqual(r.relativePath, "./Fantasy/x.epub")
    }

    func testMissingConfidenceIsQuarantinedWhenAThresholdIsSet() throws {
        let c = Classification(action: "move", relativePath: "A/x.pdf", confidence: nil)
        let r = try Pipeline.routing(for: c, rule: rule(threshold: 0.5), fileName: "x.pdf")
        XCTAssertEqual(r.kind, .quarantine)
        XCTAssertEqual(r.origin, .confidence)
    }

    func testMissingConfidenceIsFineWithoutAThreshold() throws {
        let c = Classification(action: "move", relativePath: "A/x.pdf", confidence: nil)
        let r = try Pipeline.routing(for: c, rule: rule(), fileName: "x.pdf")
        XCTAssertEqual(r.kind, .move)
        XCTAssertEqual(r.relativePath, "A/x.pdf")
    }

    func testLowConfidenceIsQuarantined() throws {
        let c = Classification(action: "move", relativePath: "A/x.pdf", confidence: 0.3)
        let r = try Pipeline.routing(for: c, rule: rule(threshold: 0.5), fileName: "x.pdf")
        XCTAssertEqual(r.kind, .quarantine)
        XCTAssertEqual(r.origin, .confidence)
    }

    func testEmptyQuarantineFolderFilesAtTheTargetRoot() throws {
        let c = Classification(action: "move", relativePath: "B/x.pdf", confidence: 0.9)
        let r = try Pipeline.routing(for: c, rule: rule(taxonomy: ["A"], quarantine: "  "), fileName: "x.pdf")
        XCTAssertEqual(r.kind, .quarantine)
        XCTAssertEqual(r.relativePath, "x.pdf")
    }

    func testCopyRulesRouteAsCopies() throws {
        var copyRule = rule()
        copyRule.copyInsteadOfMove = true
        let c = Classification(action: "move", relativePath: "A/x.pdf")
        XCTAssertEqual(try Pipeline.routing(for: c, rule: copyRule, fileName: "x.pdf").kind, .copy)
    }

    func testSkipCarriesAReason() throws {
        let c = Classification(action: "skip")
        let r = try Pipeline.routing(for: c, rule: rule(), fileName: "x.pdf")
        XCTAssertNil(r.relativePath)
        XCTAssertEqual(r.kind, .skip)
        XCTAssertEqual(r.reason, L10n.t("reason.ruleDoesNotApply"))
    }

    func testTheEngineSeesAFolderAndANameWhateverShapeTheModelAnswered() throws {
        // `{model.folder}` renders from the answer the engine is handed. A
        // model that replied with one `relative_path` — and a remembered
        // verdict, which carries nothing else — still named a folder.
        let byPath = Classification(action: "move", relativePath: "Bücher/Science-Fiction/x.epub",
                                    confidence: 0.9)
        let pathRouting = try Pipeline.routing(for: byPath, rule: rule(), fileName: "x.epub")
        let answer = try XCTUnwrap(Pipeline.modelAnswer(for: byPath, routing: pathRouting))
        XCTAssertEqual(answer.folder, "Bücher/Science-Fiction")
        XCTAssertEqual(answer.filename, "x.epub")
        XCTAssertEqual(answer.relativePath, "Bücher/Science-Fiction/x.epub")
        XCTAssertEqual(answer.confidence, 0.9)
        XCTAssertFalse(answer.quarantined)

        let byFields = Classification(action: "move", folder: "Fantasy", filename: "y.epub",
                                      confidence: 0.9)
        let fieldRouting = try Pipeline.routing(for: byFields, rule: rule(), fileName: "y.epub")
        let fields = try XCTUnwrap(Pipeline.modelAnswer(for: byFields, routing: fieldRouting))
        XCTAssertEqual(fields.folder, "Fantasy")
        XCTAssertEqual(fields.filename, "y.epub")

        // A bare filename is a name and no folder — never an empty folder.
        let bare = Classification(action: "move", relativePath: "z.epub", confidence: 0.9)
        let bareRouting = try Pipeline.routing(for: bare, rule: rule(), fileName: "z.epub")
        let bareAnswer = try XCTUnwrap(Pipeline.modelAnswer(for: bare, routing: bareRouting))
        XCTAssertNil(bareAnswer.folder)
        XCTAssertEqual(bareAnswer.filename, "z.epub")
    }

    func testAQuarantinedAnswerReachesTheEngineFlagged() throws {
        // The valve's verdict travels with the answer, so a step's own
        // template can never be built out of a folder the taxonomy refused.
        let c = Classification(action: "move", relativePath: "Sonstiges/x.pdf", confidence: 0.9)
        let routing = try Pipeline.routing(for: c, rule: rule(taxonomy: ["Rechnungen"]), fileName: "x.pdf")
        let answer = try XCTUnwrap(Pipeline.modelAnswer(for: c, routing: routing))
        XCTAssertTrue(answer.quarantined)
        XCTAssertEqual(answer.relativePath, "_Q/x.pdf")
    }

    func testAStepsOwnModelOptionsLayOverTheRules() {
        let base = Rule(name: "R", targetPath: "/t", prompt: "File invoices",
                        taxonomy: ["A"], confidenceThreshold: 0.5)
        XCTAssertEqual(Pipeline.applying(ModelStepOptions(), to: base), base,
                       "all-nil options are exactly the rule's own settings")
        let overridden = Pipeline.applying(
            ModelStepOptions(prompt: "Name the genre", taxonomy: ["Fantasy", "Krimi"],
                             privacyMode: .metadataOnly, confidenceThreshold: 0.9),
            to: base
        )
        XCTAssertEqual(overridden.prompt, "Name the genre")
        XCTAssertEqual(overridden.taxonomy, ["Fantasy", "Krimi"])
        XCTAssertEqual(overridden.privacyMode, .metadataOnly)
        XCTAssertEqual(overridden.confidenceThreshold, 0.9)
        XCTAssertEqual(overridden.id, base.id, "the same rule, for the memo and the ledger")
        // A blank prompt is no prompt: the rule's instruction stands.
        XCTAssertEqual(Pipeline.applying(ModelStepOptions(prompt: "  "), to: base).prompt,
                       "File invoices")
    }

    func testASkipIsNotAnAnswerTheEngineCanResumeWith() throws {
        let c = Classification(action: "skip", reason: "not a book")
        let routing = try Pipeline.routing(for: c, rule: rule(), fileName: "x.pdf")
        XCTAssertNil(Pipeline.modelAnswer(for: c, routing: routing))
    }

    func testMoveWithoutAPathIsAnError() {
        let c = Classification(action: "move")
        XCTAssertThrowsError(try Pipeline.routing(for: c, rule: rule(), fileName: "x.pdf"))
    }
}
