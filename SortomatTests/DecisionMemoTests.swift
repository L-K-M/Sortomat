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
            memo.record(ruleID: rule, model: "m", ext: "epub", digest: "abc", action: "move",
                        relativePath: "Books/x.epub", reason: "novel", confidence: 0.9)
            memo.save()
        }
        let reloaded = DecisionMemo(url: memoFile)
        let hit = reloaded.lookup(ruleID: rule, model: "m", ext: "epub", digest: "abc")
        XCTAssertEqual(hit?.relativePath, "Books/x.epub")
        XCTAssertEqual(hit?.action, "move")
        XCTAssertNil(reloaded.lookup(ruleID: UUID(), model: "m", ext: "epub", digest: "abc"),
                     "the memo is per-rule: another rule may decide differently")
        XCTAssertNil(reloaded.lookup(ruleID: rule, model: "stronger", ext: "epub", digest: "abc"),
                     "a verdict from one model must not be replayed under another")
        XCTAssertNil(reloaded.lookup(ruleID: rule, model: "m", ext: "pdf", digest: "abc"),
                     "identical bytes under a different extension were routed differently")
    }

    func testForgetDropsOnlyThatRule() {
        let memo = DecisionMemo(url: memoFile)
        let a = UUID(), b = UUID()
        memo.record(ruleID: a, model: "m", ext: "txt", digest: "d", action: "move",
                    relativePath: "X", reason: nil, confidence: nil)
        memo.record(ruleID: b, model: "m", ext: "txt", digest: "d", action: "skip",
                    relativePath: nil, reason: nil, confidence: nil)
        memo.forget(ruleID: a)
        XCTAssertNil(memo.lookup(ruleID: a, model: "m", ext: "txt", digest: "d"))
        XCTAssertNotNil(memo.lookup(ruleID: b, model: "m", ext: "txt", digest: "d"))

        memo.removeAll()
        XCTAssertNil(memo.lookup(ruleID: b, model: "m", ext: "txt", digest: "d"),
                     "removeAll drops every rule's verdicts")
    }

    func testEvictionDropsTheOldest() {
        let memo = DecisionMemo(url: memoFile)
        let rule = UUID()
        let base = Date(timeIntervalSinceNow: -Double(DecisionMemo.maxEntries + 10))
        for index in 0...(DecisionMemo.maxEntries) {
            memo.record(ruleID: rule, model: "m", ext: "txt", digest: "d\(index)", action: "move",
                        relativePath: "X", reason: nil, confidence: nil,
                        now: base.addingTimeInterval(Double(index)))
        }
        XCTAssertLessThanOrEqual(memo.count, DecisionMemo.maxEntries)
        XCTAssertNil(memo.lookup(ruleID: rule, model: "m", ext: "txt", digest: "d0"),
                     "the oldest entry must be evicted")
        XCTAssertNotNil(memo.lookup(ruleID: rule, model: "m", ext: "txt",
                                    digest: "d\(DecisionMemo.maxEntries)"),
                        "the newest entry must survive")
    }

    /// End-to-end: a remembered verdict plans the file with no model, no key,
    /// and no valid API base — the memo path must never touch the network.
    func testMemoHitPlansWithoutAnyModelCall() async throws {
        let file = dir.appendingPathComponent("watch/book.epub")
        try "identical bytes".write(to: file, atomically: true, encoding: .utf8)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -24 * 60 * 60)],
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
        memo.record(ruleID: rule.id, model: config.model, ext: "epub", digest: digest, action: "move",
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
        await pipeline.rememberForTesting(ruleID: rule, model: "m", ext: "txt", digest: "d",
                                          action: "move", relativePath: "A/x.txt")

        await pipeline.persist()

        XCTAssertTrue(fm.fileExists(atPath: ledgerURL.path), "the ledger must be written")
        XCTAssertTrue(fm.fileExists(atPath: memoFile.path), "the decision memo must be written")
    }

    /// A symlink reports its own few bytes to `attributesOfItem`, so the size
    /// cap used to let a link to a huge file through and hash the target whole.
    func testDigestCapFollowsSymlinks() throws {
        let big = dir.appendingPathComponent("big.bin")
        try Data(count: 1024).write(to: big)
        let link = dir.appendingPathComponent("link.bin")
        try fm.createSymbolicLink(at: link, withDestinationURL: big)

        // The digest folds in the size, so a link sized like a link (rather
        // than like its target) would hash differently from the file itself.
        XCTAssertEqual(DecisionMemo.digest(of: link), DecisionMemo.digest(of: big))

        // Why the cap probes with stat(2) and neither of the obvious
        // alternatives: both of those size the link, not the target.
        var info = stat()
        XCTAssertEqual(stat(link.path, &info), 0)
        XCTAssertEqual(info.st_size, 1024, "stat must traverse the link")
        let linkAttributes = (try? fm.attributesOfItem(atPath: link.path)) ?? [:]
        let lstatSize = linkAttributes[.size] as? Int64
        XCTAssertTrue(lstatSize != 1024, "attributesOfItem sizes the link — unusable for the cap")
        let resourceSize = (try? link.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        XCTAssertTrue(resourceSize != 1024, "resource values size the link — unusable for the cap")
    }

    /// The cap exists so a huge file is never hashed just to look up a verdict;
    /// a symlink must not be a way around it.
    func testDigestRefusesFilesOverTheCapThroughALink() throws {
        let huge = dir.appendingPathComponent("huge.bin")
        XCTAssertTrue(fm.createFile(atPath: huge.path, contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        // Sparse: the bytes are never written, only the size is set.
        try handle.truncate(atOffset: UInt64(DecisionMemo.maxHashedBytes) + 1)
        try handle.close()
        let link = dir.appendingPathComponent("huge-link.bin")
        try fm.createSymbolicLink(at: link, withDestinationURL: huge)

        XCTAssertNil(DecisionMemo.digest(of: huge))
        XCTAssertNil(DecisionMemo.digest(of: link), "a link must not smuggle its target past the cap")
    }

    /// Editing a rule drops its previews so it re-plans — which only works if
    /// the memo forgets too, since `decide` consults the memo before the model.
    func testForgettingPreviewsAlsoForgetsMemoizedVerdicts() async throws {
        let file = dir.appendingPathComponent("watch/doc.txt")
        try "bytes".write(to: file, atomically: true, encoding: .utf8)
        let rule = Rule(name: "R",
                        watchPath: dir.appendingPathComponent("watch").path,
                        targetPath: dir.appendingPathComponent("target").path)
        let memo = DecisionMemo(url: memoFile)
        let digest = try XCTUnwrap(DecisionMemo.digest(of: file))
        memo.record(ruleID: rule.id, model: "m", ext: "txt", digest: digest, action: "move",
                    relativePath: "A/doc.txt", reason: nil, confidence: nil)

        let pipeline = Pipeline(ledger: Ledger(url: dir.appendingPathComponent("ledger.json")),
                                memo: memo)
        await pipeline.forgetPreviews(ruleID: rule.id)

        XCTAssertNil(memo.lookup(ruleID: rule.id, model: "m", ext: "txt", digest: digest),
                     "a rewritten rule must not keep serving its old verdict for free")
    }
}
