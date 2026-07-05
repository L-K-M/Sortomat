import XCTest
@testable import Sortomat

/// The pipeline's per-session preview memory must be droppable per rule: an
/// edited rule re-plans its files instead of serving stale suggestions.
final class PreviewHygieneTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-hygiene-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("watch"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("target"), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    private func makeRule() throws -> Rule {
        let file = dir.appendingPathComponent("watch/doc.txt")
        try "content".write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                             ofItemAtPath: file.path)
        return Rule(
            name: "R",
            watchPath: dir.appendingPathComponent("watch").path,
            targetPath: dir.appendingPathComponent("target").path,
            preRules: [PreRule(match: .glob, pattern: "*", action: .route, routePath: "Sorted")],
            dryRun: true
        )
    }

    func testForgettingPreviewsMakesTheRuleRePlan() async throws {
        let rule = try makeRule()
        let config = Config(rules: [rule], providerRequiresKey: false)
        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")))

        let first = await pipeline.scan(rule: rule, config: config, apiKey: "")
        XCTAssertEqual(first.pending.count, 1)

        // Same session, nothing changed: the preview memory suppresses a re-plan.
        let second = await pipeline.scan(rule: rule, config: config, apiKey: "")
        XCTAssertEqual(second.pending.count, 0)

        // The rule was edited: its preview memory is dropped and it re-plans.
        await pipeline.forgetPreviews(ruleID: rule.id)
        let third = await pipeline.scan(rule: rule, config: config, apiKey: "")
        XCTAssertEqual(third.pending.count, 1)
    }

    func testForgettingOneRuleLeavesOthersAlone() async throws {
        let rule = try makeRule()
        let config = Config(rules: [rule], providerRequiresKey: false)
        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")))

        _ = await pipeline.scan(rule: rule, config: config, apiKey: "")
        await pipeline.forgetPreviews(ruleID: UUID()) // some other rule
        let again = await pipeline.scan(rule: rule, config: config, apiKey: "")
        XCTAssertEqual(again.pending.count, 0, "an unrelated rule's reset must not re-plan this one")
    }
}
