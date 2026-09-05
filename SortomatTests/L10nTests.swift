import XCTest
@testable import Sortomat

final class L10nTests: XCTestCase {
    override func tearDown() {
        L10n.forcedLanguage = nil
    }

    func testPluralPicksSingularAndPluralForms() {
        L10n.forcedLanguage = "en"
        XCTAssertEqual(L10n.plural("menu.pendingReview", 1), "1 change awaiting review…")
        XCTAssertEqual(L10n.plural("menu.pendingReview", 3), "3 changes awaiting review…")
        XCTAssertEqual(L10n.plural("app.status.active", 1), "Active — 1 rule")
        XCTAssertEqual(L10n.plural("app.status.active", 2), "Active — 2 rules")
    }

    func testPluralWithExtraArgumentsUsesPositionalSpecifiers() {
        L10n.forcedLanguage = "en"
        XCTAssertEqual(L10n.plural("activity.keyDeferred", 1, "Books"),
                       "[Books] 1 file needs the model, but no API key is set — pre-rules still ran.")
        XCTAssertEqual(L10n.plural("notify.failuresMore", 2, "first"), "first (and 2 more failures)")
        L10n.forcedLanguage = "de"
        XCTAssertEqual(L10n.plural("activity.keyDeferred", 3, "Bücher"),
                       "[Bücher] 3 Dateien benötigen das Modell, aber kein API-Key ist hinterlegt – Vorregeln liefen trotzdem.")
    }

    func testPluralGerman() {
        L10n.forcedLanguage = "de"
        XCTAssertEqual(L10n.plural("preview.applied", 1), "1 Änderung angewendet.")
        XCTAssertEqual(L10n.plural("preview.applied", 5), "5 Änderungen angewendet.")
    }

    /// Every plural key must exist in both forms in both tables — a missing
    /// form would render as the raw key at runtime.
    func testPluralKeyPairsAreComplete() {
        let pluralBases = ["app.status.active", "menu.pendingReview",
                           "preview.applied", "preview.dismissed",
                           "journal.undoBatchDone", "journal.undoBatchFailed",
                           "notify.filed", "notify.failuresMore", "activity.keyDeferred"]
        for base in pluralBases {
            for suffix in [".one", ".other"] {
                XCTAssertNotNil(L10n.english[base + suffix], "EN missing \(base + suffix)")
                XCTAssertNotNil(L10n.german[base + suffix], "DE missing \(base + suffix)")
            }
        }
    }

    /// Both tables must define exactly the same key set: an EN-only key shows
    /// English to German users; a DE-only key is dead weight (or worse, an
    /// English fallback that renders the raw key).
    func testTablesDefineTheSameKeys() {
        let english = Set(L10n.english.keys)
        let german = Set(L10n.german.keys)
        XCTAssertEqual(english.subtracting(german).sorted(), [],
                       "keys missing from the German table")
        XCTAssertEqual(german.subtracting(english).sorted(), [],
                       "keys missing from the English table")
    }
}
