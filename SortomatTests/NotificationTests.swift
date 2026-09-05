import UserNotifications
import XCTest
@testable import Sortomat

/// The banner is the only place most people ever see Sortomat work, so what it
/// says and what its buttons do are worth pinning.
final class NotificationTests: XCTestCase {
    override func tearDown() {
        L10n.forcedLanguage = nil
    }

    private func url(_ path: String) -> URL { URL(fileURLWithPath: path) }

    // MARK: - What it says

    func testSummaryNamesTheFilesAndWhereTheyWent() {
        L10n.forcedLanguage = "en"
        let text = NotificationText.summary(of: [
            url("/Users/x/Documents/Invoices/Invoice 2024.pdf"),
            url("/Users/x/Documents/Invoices/Receipt.pdf"),
        ])
        XCTAssertTrue(text.contains("Invoice 2024.pdf"), "got: \(text)")
        XCTAssertTrue(text.contains("Receipt.pdf"), "got: \(text)")
        XCTAssertTrue(text.contains("Documents/Invoices"), "got: \(text)")
    }

    func testSummaryStopsListingAfterTwoNames() {
        L10n.forcedLanguage = "en"
        let files = (1...5).map { url("/Users/x/Docs/file\($0).pdf") }
        let text = NotificationText.summary(of: files)
        XCTAssertTrue(text.contains("file1.pdf"))
        XCTAssertTrue(text.contains("file2.pdf"))
        XCTAssertFalse(text.contains("file3.pdf"), "a banner is two lines, not five: \(text)")
        XCTAssertTrue(text.contains("3"), "the rest have to be counted, not dropped: \(text)")
    }

    func testSummaryOfNothingIsEmptyRatherThanADanglingArrow() {
        XCTAssertEqual(NotificationText.summary(of: []), "")
    }

    func testSummaryReadsInGermanToo() {
        L10n.forcedLanguage = "de"
        let files = (1...4).map { url("/Users/x/Docs/file\($0).pdf") }
        let text = NotificationText.summary(of: files)
        XCTAssertFalse(text.contains("notify."), "renders a raw key: \(text)")
        XCTAssertTrue(text.contains("2"), "got: \(text)")
    }

    // MARK: - Where they went

    func testCommonFolderIsTheDeepestSharedOne() {
        XCTAssertEqual(
            NotificationText.commonFolder(of: [
                url("/Users/x/Docs/A/one.pdf"),
                url("/Users/x/Docs/B/two.pdf"),
            ])?.path,
            "/Users/x/Docs"
        )
        XCTAssertEqual(
            NotificationText.commonFolder(of: [url("/Users/x/Docs/A/one.pdf")])?.path,
            "/Users/x/Docs/A"
        )
    }

    func testNoCommonFolderWhenTheAnswerWouldBeTheRoot() {
        // "→ /" is worse than saying nothing: it looks like an answer.
        XCTAssertNil(NotificationText.commonFolder(of: [
            url("/Users/x/one.pdf"),
            url("/Volumes/Backup/two.pdf"),
        ]))
        XCTAssertNil(NotificationText.commonFolder(of: []))
    }

    // MARK: - What the buttons do

    func testUndoActionCarriesThePassItIsAbout() {
        let batch = UUID()
        let action = Notifier.action(for: "sortomat.action.undo",
                                     userInfo: ["batch": batch.uuidString])
        XCTAssertEqual(action, .undo(batch: batch))
    }

    func testUndoWithoutABatchDoesNothingRatherThanGuess() {
        // A banner from a build before batch ids, or from a pass that filed
        // nothing: reversing "the newest batch" on a guess could undo work the
        // user has since redone.
        XCTAssertNil(Notifier.action(for: "sortomat.action.undo", userInfo: [:]))
        XCTAssertNil(Notifier.action(for: "sortomat.action.undo", userInfo: ["batch": "not-a-uuid"]))
    }

    func testRevealActionCarriesThePath() {
        XCTAssertEqual(
            Notifier.action(for: "sortomat.action.reveal", userInfo: ["reveal": "/Users/x/Docs"]),
            .reveal(URL(fileURLWithPath: "/Users/x/Docs"))
        )
        XCTAssertNil(Notifier.action(for: "sortomat.action.reveal", userInfo: [:]))
    }

    func testClickingTheBannerItselfOpensTheApp() {
        XCTAssertEqual(
            Notifier.action(for: UNNotificationDefaultActionIdentifier, userInfo: [:]),
            .open
        )
    }

    func testDismissingDoesNothing() {
        XCTAssertNil(Notifier.action(for: UNNotificationDismissActionIdentifier, userInfo: [:]))
        XCTAssertNil(Notifier.action(for: "sortomat.action.fromAnOlderBuild", userInfo: [:]))
    }

    // MARK: - The path a notification needs

    func testAFiledEntryRemembersWhereTheFileLanded() {
        // The message is a sentence for a log; re-parsing a path out of it
        // would break in German first.
        let entry = ActivityEntry(ok: true, message: "moved", kind: .filed,
                                  placed: url("/Users/x/Docs/a.pdf"))
        XCTAssertEqual(entry.placed?.lastPathComponent, "a.pdf")
        XCTAssertNil(ActivityEntry(ok: true, message: "skipped").placed)
    }
}
