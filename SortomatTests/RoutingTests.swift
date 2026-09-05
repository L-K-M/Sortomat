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

    func testMoveWithoutAPathIsAnError() {
        let c = Classification(action: "move")
        XCTAssertThrowsError(try Pipeline.routing(for: c, rule: rule(), fileName: "x.pdf"))
    }
}
