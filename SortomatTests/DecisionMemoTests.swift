import XCTest
@testable import Sortomat

final class DecisionMemoTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-memo-\(UUID().uuidString)")
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

    private var memoFile: URL { dir.appendingPathComponent("memo.json") }

    func testRecordLookupAndPersistence() {
        let rule = UUID()
        do {
            let memo = DecisionMemo(url: memoFile)
            memo.record(ruleID: rule, digest: "abc", action: "move",
                        relativePath: "Books/x.epub", reason: "novel", confidence: 0.9)
            memo.save()
        }
        let reloaded = DecisionMemo(url: memoFile)
        let hit = reloaded.lookup(ruleID: rule, digest: "abc")
        XCTAssertEqual(hit?.relativePath, "Books/x.epub")
        XCTAssertEqual(hit?.action, "move")
        XCTAssertNil(reloaded.lookup(ruleID: UUID(), digest: "abc"),
                     "the memo is per-rule: another rule may decide differently")
    }

    func testForgetDropsOnlyThatRule() {
        let memo = DecisionMemo(url: memoFile)
        let a = UUID(), b = UUID()
        memo.record(ruleID: a, digest: "d", action: "move", relativePath: "X", reason: nil, confidence: nil)
        memo.record(ruleID: b, digest: "d", action: "skip", relativePath: nil, reason: nil, confidence: nil)
        memo.forget(ruleID: a)
        XCTAssertNil(memo.lookup(ruleID: a, digest: "d"))
        XCTAssertNotNil(memo.lookup(ruleID: b, digest: "d"))
    }

    func testEvictionDropsTheOldest() {
        let memo = DecisionMemo(url: memoFile)
        let rule = UUID()
        let base = Date(timeIntervalSinceNow: -Double(DecisionMemo.maxEntries + 10))
        for index in 0...(DecisionMemo.maxEntries) {
            memo.record(ruleID: rule, digest: "d\(index)", action: "move",
                        relativePath: "X", reason: nil, confidence: nil,
                        now: base.addingTimeInterval(Double(index)))
        }
        XCTAssertLessThanOrEqual(memo.count, DecisionMemo.maxEntries)
        XCTAssertNil(memo.lookup(ruleID: rule, digest: "d0"), "the oldest entry must be evicted")
        XCTAssertNotNil(memo.lookup(ruleID: rule, digest: "d\(DecisionMemo.maxEntries)"),
                        "the newest entry must survive")
    }

    /// End-to-end: a remembered verdict plans the file with no model, no key,
    /// and no valid API base — the memo path must never touch the network.
    func testMemoHitPlansWithoutAnyModelCall() async throws {
        let file = dir.appendingPathComponent("watch/book.epub")
        try "identical bytes".write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -60)],
                             ofItemAtPath: file.path)

        let rule = Rule(
            name: "R",
            watchPath: dir.appendingPathComponent("watch").path,
            targetPath: dir.appendingPathComponent("target").path,
            dryRun: true
        )
        // An empty apiBase makes any accidental classify attempt throw loudly.
        var config = Config(rules: [rule], apiBase: "", providerRequiresKey: false)
        config.rules = [rule]

        let memo = DecisionMemo(url: memoFile)
        let digest = try XCTUnwrap(ContentHash.digest(of: file, limit: .max))
        memo.record(ruleID: rule.id, digest: digest, action: "move",
                    relativePath: "Books/book.epub", reason: "seen before", confidence: 0.95)

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: memo)
        let result = await pipeline.scan(rule: rule, config: config, apiKey: "")

        XCTAssertEqual(result.pending.count, 1)
        XCTAssertEqual(result.pending.first?.destination?.lastPathComponent, "book.epub")
        XCTAssertTrue(result.pending.first?.destination?.path.contains("/Books/") ?? false)
        XCTAssertEqual(result.usage.input + result.usage.output, 0, "a memo hit costs nothing")
        XCTAssertTrue(result.entries.allSatisfy(\.ok),
                      "no classify attempt may have failed — the memo answered")
    }


    /// `persist()` composes three jobs from three different review branches —
    /// pruning the ledger, saving it, and saving the memo. Dropping any one of
    /// them still compiles and still passes every other test, so assert that
    /// one call writes both files.
    func testPersistWritesBothTheLedgerAndTheMemo() async {
        let ledgerURL = dir.appendingPathComponent("ledger.json")
        let pipeline = Pipeline(ledger: Ledger(url: ledgerURL),
                                memo: DecisionMemo(url: memoFile))
        let rule = UUID()
        await pipeline.markUndone(ruleID: rule, sourcePath: dir.appendingPathComponent("watch/x.txt").path)
        await pipeline.rememberForTesting(ruleID: rule, digest: "d", action: "move", relativePath: "A/x.txt")

        await pipeline.persist()

        XCTAssertTrue(fm.fileExists(atPath: ledgerURL.path), "the ledger must be written")
        XCTAssertTrue(fm.fileExists(atPath: memoFile.path), "the decision memo must be written")
    }
}
