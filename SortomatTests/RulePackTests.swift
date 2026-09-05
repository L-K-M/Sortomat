import XCTest
@testable import Sortomat

final class RulePackTests: XCTestCase {
    private func sampleRule() -> Rule {
        Rule(
            name: "Invoices",
            enabled: true,
            watchPath: "/Users/someone/Downloads",
            targetPath: "/Users/someone/Documents/Filed",
            prompt: "File invoices under {Year}/{Sender}.",
            extensions: ["pdf"],
            preRules: [PreRule(name: "old", match: .olderThanDays, pattern: "365", action: .skip)],
            taxonomy: ["2025", "2026"],
            confidenceThreshold: 0.7,
            dryRun: false
        )
    }

    func testExportStripsMachineLocalPaths() {
        let pack = RulePack(exporting: sampleRule())
        XCTAssertEqual(pack.rule.watchPath, "")
        XCTAssertEqual(pack.rule.targetPath, "")
        XCTAssertEqual(pack.rule.prompt, "File invoices under {Year}/{Sender}.")
        XCTAssertEqual(pack.rule.taxonomy, ["2025", "2026"])
        XCTAssertEqual(pack.rule.preRules.count, 1)
        XCTAssertEqual(pack.rule.confidenceThreshold, 0.7)
    }

    func testRoundTrip() throws {
        let pack = RulePack(exporting: sampleRule())
        let decoded = try RulePack.decode(try pack.encoded())
        XCTAssertEqual(decoded.format, RulePack.currentFormat)
        XCTAssertEqual(decoded.rule.prompt, pack.rule.prompt)
        XCTAssertEqual(decoded.rule.extensions, ["pdf"])
    }

    func testImportedRuleArrivesSafe() throws {
        let original = sampleRule()
        let pack = try RulePack.decode(try RulePack(exporting: original).encoded())
        let imported = pack.makeImportedRule()
        XCTAssertNotEqual(imported.id, original.id, "an import must never collide with existing ids")
        XCTAssertFalse(imported.enabled, "imports arrive disabled")
        XCTAssertTrue(imported.dryRun, "imports arrive in preview mode")
    }

    func testNewerFormatIsRejected() throws {
        var pack = RulePack(exporting: sampleRule())
        pack.format = RulePack.currentFormat + 1
        let data = try pack.encoded()
        XCTAssertThrowsError(try RulePack.decode(data)) { error in
            guard case RulePack.PackError.unsupportedFormat(let version) = error else {
                return XCTFail("expected unsupportedFormat, got \(error)")
            }
            XCTAssertEqual(version, RulePack.currentFormat + 1)
        }
    }
}
