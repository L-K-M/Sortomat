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
}
