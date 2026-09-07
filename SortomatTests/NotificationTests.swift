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
        // Names with no digits in them. This test used to file `file1.pdf`
        // through `file4.pdf` and assert `contains("2")` — which "file2.pdf"
        // satisfies whether or not the count is rendered, and whether or not
        // the string is German. Assert the German phrase instead, and that the
        // English one is not what came back.
        let files = ["Rechnung", "Beleg", "Vertrag", "Notiz"].map { url("/Users/x/Docs/\($0).pdf") }
        let text = NotificationText.summary(of: files)
        XCTAssertFalse(text.contains("notify."), "renders a raw key: \(text)")
        XCTAssertTrue(text.contains("und 2 weitere"), "got: \(text)")
        XCTAssertFalse(text.contains("and 2 more"), "fell back to English: \(text)")
    }

    // MARK: - What it says after Undo

    func testUndoWithNothingLeftToDoStillSaysSomething() {
        L10n.forcedLanguage = "en"
        // The failure this guards: a banner survives in Notification Center for
        // days, `Journal.recent` folds away an already-reversed move, and so
        // pressing Undo twice — or once, tomorrow — reverses nothing. Posting
        // nothing at that point means the user pressed a button that moves
        // files and heard back silence.
        let text = NotificationText.undoResult(undone: 0, failed: 0)
        XCTAssertFalse(text.title.isEmpty, "silence is the bug")
        XCTAssertFalse(text.body.isEmpty, "says nothing happened, not why")
        XCTAssertFalse(text.title.contains("0"), "«Put 0 files back» is a non-answer: \(text.title)")
    }

    func testUndoThatMovedNothingButRefusedSomethingLeadsWithTheRefusal() {
        L10n.forcedLanguage = "en"
        let text = NotificationText.undoResult(
            undone: 0, failed: 2, firstFailure: "Couldn't undo a.pdf: something else is there now"
        )
        XCTAssertTrue(text.title.contains("2"), "got: \(text.title)")
        XCTAssertFalse(text.title.contains("Put 0"), "got: \(text.title)")
        XCTAssertTrue(text.body.contains("something else is there now"),
                      "the reason is the only actionable part: \(text.body)")
    }

    func testUndoThatFullySucceededCountsAndAddsNothing() {
        L10n.forcedLanguage = "en"
        let text = NotificationText.undoResult(undone: 3, failed: 0)
        XCTAssertTrue(text.title.contains("3"), "got: \(text.title)")
        XCTAssertEqual(text.body, "")
    }

    func testUndoThatPartlyRefusedReportsBothHalves() {
        L10n.forcedLanguage = "en"
        // Some back, some refused — the commonest way to meet a refusal, and
        // so the last place the reason should go missing.
        let text = NotificationText.undoResult(
            undone: 2, failed: 1, firstFailure: "Couldn't undo a.pdf: something else is there now"
        )
        XCTAssertTrue(text.title.contains("2"), "got: \(text.title)")
        XCTAssertTrue(text.body.contains("1"), "got: \(text.body)")
        XCTAssertTrue(text.body.contains("something else is there now"),
                      "the mixed case drops the reason: \(text.body)")
    }

    func testUndoResultReadsInGermanToo() {
        L10n.forcedLanguage = "de"
        // Assert the German, not merely the absence of a raw key: every one of
        // these strings is built on *zurücklegen*, so a fall back to the
        // English table would show. This is the same trap
        // `testSummaryReadsInGermanToo` was in.
        for text in [NotificationText.undoResult(undone: 0, failed: 0),
                     NotificationText.undoResult(undone: 0, failed: 2, firstFailure: "warum"),
                     NotificationText.undoResult(undone: 3, failed: 1, firstFailure: "warum")] {
            XCTAssertFalse(text.title.contains("notify."), "renders a raw key: \(text.title)")
            XCTAssertFalse(text.body.contains("notify."), "renders a raw key: \(text.body)")
            XCTAssertTrue(text.title.contains("zurück"), "fell back to English: \(text.title)")
        }
        // And the one body that is entirely ours to translate.
        let nothing = NotificationText.undoResult(undone: 0, failed: 0)
        XCTAssertTrue(nothing.body.contains("zurückgelegt"), "got: \(nothing.body)")
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

    func testABannerWithNothingToUndoOffersNoButtons() {
        // A destructive-looking Undo that silently does nothing erodes trust
        // faster than no button at all, and both actions need a payload.
        XCTAssertNil(Notifier.filedCategoryIdentifier(batch: nil, urls: [url("/a/x.pdf")]))
        XCTAssertNil(Notifier.filedCategoryIdentifier(batch: UUID(), urls: []))
        XCTAssertEqual(Notifier.filedCategoryIdentifier(batch: UUID(), urls: [url("/a/x.pdf")]),
                       "sortomat.filed")
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
