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


    func testPluralSingularWithExtraArgument() {
        // The form that skips %1$ is not a style choice: the formatter only
        // types the slots a specifier names, and an untyped slot doesn't
        // consume its argument — so "%2$@ (and 1 more failure)" read the Int
        // count where the message pointer belonged and crashed the app.
        L10n.forcedLanguage = "en"
        XCTAssertEqual(L10n.plural("notify.failuresMore", 1, "first"), "first (and 1 more failure)")
        L10n.forcedLanguage = "de"
        XCTAssertEqual(L10n.plural("notify.failuresMore", 1, "erster"), "erster (und 1 weiterer Fehler)")
    }

    /// Any plural form that references a later positional argument must also
    /// reference the count, in both tables — see the crash above.
    func testPositionalPluralFormsAlwaysReferenceTheCount() {
        for (language, table) in [("EN", L10n.english), ("DE", L10n.german)] {
            for (key, value) in table where key.hasSuffix(".one") || key.hasSuffix(".other") {
                if value.contains("%2$") {
                    XCTAssertTrue(value.contains("%1$"),
                                  "\(language) \(key) references %2$ without %1$: \(value)")
                }
            }
        }
    }
}
