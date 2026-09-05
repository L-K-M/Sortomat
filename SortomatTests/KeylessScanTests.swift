import XCTest
@testable import Sortomat

/// A missing API key must not hold deterministic sorting hostage: pre-rules
/// run and move files; only files that would need the model are deferred.
final class KeylessScanTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-keyless-\(UUID().uuidString)")
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

    /// A file old enough to pass the stability probe.
    private func plantStableFile(named name: String) throws -> URL {
        let url = dir.appendingPathComponent("watch/\(name)")
        try "content".write(to: url, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                             ofItemAtPath: url.path)
        return url
    }

    func testPreRuleRouteMovesWithoutKey() async throws {
        let file = try plantStableFile(named: "report.txt")
        let rule = Rule(
            name: "R",
            watchPath: dir.appendingPathComponent("watch").path,
            targetPath: dir.appendingPathComponent("target").path,
            preRules: [PreRule(match: .glob, pattern: "*.txt", action: .route, routePath: "Text")]
        )
        let config = Config(rules: [rule], providerRequiresKey: true)

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: DecisionMemo(url: dir.appendingPathComponent("memo.json")))
        let result = await pipeline.scan(rule: rule, config: config, apiKey: "")

        XCTAssertFalse(fm.fileExists(atPath: file.path), "the pre-rule should have moved it")
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("target/Text/report.txt").path))
        XCTAssertTrue(result.entries.allSatisfy(\.ok))
    }

    func testModelBoundFileIsDeferredWithoutKey() async throws {
        let file = try plantStableFile(named: "mystery.txt")
        let rule = Rule(
            name: "R",
            watchPath: dir.appendingPathComponent("watch").path,
            targetPath: dir.appendingPathComponent("target").path
        )
        let config = Config(rules: [rule], providerRequiresKey: true)

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: DecisionMemo(url: dir.appendingPathComponent("memo.json")))
        let result = await pipeline.scan(rule: rule, config: config, apiKey: "")

        XCTAssertTrue(fm.fileExists(atPath: file.path), "nothing may move without a decision")
        // One informational entry explaining the deferral, no failures.
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertTrue(result.entries[0].ok)

        // The deferral must not be recorded as handled: once a key exists the
        // file gets classified. (A second keyless scan defers again.)
        let again = await pipeline.scan(rule: rule, config: config, apiKey: "")
        XCTAssertEqual(again.entries.count, 1)
    }
}
