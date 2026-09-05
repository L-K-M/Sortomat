import XCTest
@testable import Sortomat

/// The scan must *report* files it rejected as unstable (too young / still
/// growing), so the app can schedule a short follow-up pass instead of leaving
/// the file to wait for the next periodic tick.
final class ScanStabilityTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-stability-\(UUID().uuidString)")
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

    func testYoungFileIsCountedUnstableAndLeftAlone() async throws {
        let young = dir.appendingPathComponent("watch/fresh.txt")
        try "just landed".write(to: young, atomically: true, encoding: .utf8)

        let old = dir.appendingPathComponent("watch/settled.txt")
        try "settled".write(to: old, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                             ofItemAtPath: old.path)

        let rule = Rule(
            name: "R",
            watchPath: dir.appendingPathComponent("watch").path,
            targetPath: dir.appendingPathComponent("target").path,
            preRules: [PreRule(match: .glob, pattern: "*", action: .route, routePath: "Sorted")]
        )
        let config = Config(rules: [rule], providerRequiresKey: false)

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: DecisionMemo(url: dir.appendingPathComponent("memo.json")))
        let result = await pipeline.scan(rule: rule, config: config, apiKey: "unused")

        XCTAssertEqual(result.unstableCount, 1, "the fresh file must be reported, not forgotten")
        XCTAssertTrue(fm.fileExists(atPath: young.path), "an unstable file must not move")
        XCTAssertTrue(fm.fileExists(atPath: dir.appendingPathComponent("target/Sorted/settled.txt").path),
                      "the settled file should have been routed")
    }

    func testScanResultSumAddsUnstableCounts() {
        var a = ScanResult(); a.unstableCount = 2
        var b = ScanResult(); b.unstableCount = 3
        XCTAssertEqual((a + b).unstableCount, 5)
    }
}
