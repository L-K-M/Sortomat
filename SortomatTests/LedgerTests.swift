import XCTest
@testable import Sortomat

final class LedgerTests: XCTestCase {
    private var url: URL!
    override func setUp() {
        url = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString).json")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
    }

    func testUnseenIsProcessable() {
        let ledger = Ledger(url: url)
        XCTAssertTrue(ledger.shouldProcess(ruleID: UUID(), fingerprint: "f"))
    }

    func testSkippedIsNotReprocessed() {
        let ledger = Ledger(url: url)
        let rule = UUID()
        ledger.record(ruleID: rule, fingerprint: "f", status: .skipped)
        XCTAssertFalse(ledger.shouldProcess(ruleID: rule, fingerprint: "f"))
    }

    func testFailureRetriesAfterInterval() {
        let ledger = Ledger(url: url, failRetryInterval: 1800)
        let rule = UUID()
        let now = Date()
        ledger.record(ruleID: rule, fingerprint: "f", status: .failed, now: now)
        XCTAssertFalse(ledger.shouldProcess(ruleID: rule, fingerprint: "f", now: now.addingTimeInterval(60)))
        XCTAssertTrue(ledger.shouldProcess(ruleID: rule, fingerprint: "f", now: now.addingTimeInterval(2000)))
    }

    func testPerRuleKeyingAvoidsCrossPoisoning() {
        let ledger = Ledger(url: url)
        let ruleA = UUID(), ruleB = UUID()
        ledger.record(ruleID: ruleA, fingerprint: "f", status: .skipped)
        // Rule B must still be able to process the same file.
        XCTAssertTrue(ledger.shouldProcess(ruleID: ruleB, fingerprint: "f"))
    }

    func testForgetClearsRule() {
        let ledger = Ledger(url: url)
        let rule = UUID()
        ledger.record(ruleID: rule, fingerprint: "f", status: .skipped)
        ledger.forget(ruleID: rule)
        XCTAssertTrue(ledger.shouldProcess(ruleID: rule, fingerprint: "f"))
    }

    func testPersistenceRoundTrip() {
        let rule = UUID()
        do {
            let ledger = Ledger(url: url)
            ledger.record(ruleID: rule, fingerprint: "f", status: .done)
            ledger.save()
        }
        let reloaded = Ledger(url: url)
        XCTAssertFalse(reloaded.shouldProcess(ruleID: rule, fingerprint: "f"))
    }

    func testSaveSkipsRewriteWhenClean() {
        let ledger = Ledger(url: url)
        ledger.record(ruleID: UUID(), fingerprint: "f", status: .done)
        ledger.save()
        // Nothing changed since: a second save must not rewrite the file.
        try? FileManager.default.removeItem(at: url)
        ledger.save()
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "a clean ledger must not rewrite its file")
        // A new record makes it dirty again.
        ledger.record(ruleID: UUID(), fingerprint: "g", status: .skipped)
        ledger.save()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testPruneDropsOldEntriesForVanishedFiles() {
        let fm = FileManager.default
        let existing = fm.temporaryDirectory.appendingPathComponent("ledger-live-\(UUID().uuidString).txt")
        try? Data("x".utf8).write(to: existing)
        defer { try? fm.removeItem(at: existing) }

        let ledger = Ledger(url: url)
        let rule = UUID()
        let old = Date(timeIntervalSinceNow: -60 * 86_400)
        let vanishedFingerprint = "/definitely/gone/file.txt|123|456"
        let liveFingerprint = "\(existing.path)|1|456"

        ledger.record(ruleID: rule, fingerprint: vanishedFingerprint, status: .skipped, now: old)
        ledger.record(ruleID: rule, fingerprint: liveFingerprint, status: .skipped, now: old)
        ledger.record(ruleID: rule, fingerprint: "/also/gone/young.txt|1|2", status: .skipped)

        ledger.prune()

        XCTAssertTrue(ledger.shouldProcess(ruleID: rule, fingerprint: vanishedFingerprint),
                      "old entry for a vanished file must be pruned")
        XCTAssertFalse(ledger.shouldProcess(ruleID: rule, fingerprint: liveFingerprint),
                       "an entry for a file that still exists must survive, however old")
        XCTAssertFalse(ledger.shouldProcess(ruleID: rule, fingerprint: "/also/gone/young.txt|1|2"),
                       "young entries are kept even when the file is gone")
    }
}
