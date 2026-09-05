import XCTest
@testable import Sortomat

/// Approving a preview must execute against the file the suggestion was made
/// for — not whatever sits at that path by the time the user clicks Apply.
final class ApplyRevalidationTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-revalidate-\(UUID().uuidString)")
        try fm.createDirectory(at: dir.appendingPathComponent("watch"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dir.appendingPathComponent("target"), withIntermediateDirectories: true)
        // The Pipeline journals every placement and opens the decision memo
        // through ConfigStore. Without this the suite appends to the real
        // ~/Library/Application Support/Sortomat/journal.jsonl, and a
        // developer's History tab fills up with vanished test files.
        setenv("SORTOMAT_CONFIG_DIR", dir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("SORTOMAT_CONFIG_DIR")
        try? fm.removeItem(at: dir)
    }

    private func makeRule() -> Rule {
        Rule(
            name: "R",
            watchPath: dir.appendingPathComponent("watch").path,
            targetPath: dir.appendingPathComponent("target").path
        )
    }

    private func makePlan(rule: Rule, source: URL, fingerprint: String?) -> PlannedAction {
        PlannedAction(
            ruleID: rule.id, ruleName: rule.name, source: source, kind: .move,
            destination: dir.appendingPathComponent("target/filed.txt"),
            origin: .preRule, reason: "test", confidence: nil,
            copyInsteadOfMove: false, fingerprint: fingerprint
        )
    }

    func testApplyRefusesWhenFileChangedSincePlanning() async throws {
        let source = dir.appendingPathComponent("watch/doc.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        let rule = makeRule()
        let plan = makePlan(rule: rule, source: source, fingerprint: Ledger.fingerprint(source))

        // The file is replaced (different size) between preview and approval.
        try "replaced with much longer content".write(to: source, atomically: true, encoding: .utf8)

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: DecisionMemo(url: dir.appendingPathComponent("memo.json")))
        let entries = await pipeline.applyApproved([plan], rules: [rule.id: rule])

        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].ok)
        XCTAssertTrue(fm.fileExists(atPath: source.path), "the changed file must stay put")
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("target/filed.txt").path))
    }

    func testApplyProceedsWhenFingerprintMatches() async throws {
        let source = dir.appendingPathComponent("watch/doc.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        let rule = makeRule()
        let plan = makePlan(rule: rule, source: source, fingerprint: Ledger.fingerprint(source))

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: DecisionMemo(url: dir.appendingPathComponent("memo.json")))
        let entries = await pipeline.applyApproved([plan], rules: [rule.id: rule])

        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].ok)
        XCTAssertFalse(fm.fileExists(atPath: source.path))
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("target/filed.txt").path))
    }

    func testLegacyPlanWithoutFingerprintStillApplies() async throws {
        let source = dir.appendingPathComponent("watch/doc.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        let rule = makeRule()
        let plan = makePlan(rule: rule, source: source, fingerprint: nil)

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: DecisionMemo(url: dir.appendingPathComponent("memo.json")))
        let entries = await pipeline.applyApproved([plan], rules: [rule.id: rule])

        XCTAssertEqual(entries.count, 1)
        XCTAssertTrue(entries[0].ok)
        XCTAssertFalse(fm.fileExists(atPath: source.path), "a legacy plan must still move the file")
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("target/filed.txt").path))
    }

    /// The other half of the window the fingerprint guards: the file is gone by
    /// the time the user clicks Apply. Reporting success for a move that never
    /// happened would journal a placement that can't be undone.
    func testApplyRefusesWhenFileVanishedSincePlanning() async throws {
        let source = dir.appendingPathComponent("watch/doc.txt")
        try "original".write(to: source, atomically: true, encoding: .utf8)
        let rule = makeRule()
        let plan = makePlan(rule: rule, source: source, fingerprint: Ledger.fingerprint(source))

        try fm.removeItem(at: source)

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: DecisionMemo(url: dir.appendingPathComponent("memo.json")))
        let entries = await pipeline.applyApproved([plan], rules: [rule.id: rule])

        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].ok)
        XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent("target/filed.txt").path))
    }
}
