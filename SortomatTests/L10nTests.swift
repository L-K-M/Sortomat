import Foundation
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
        // Derived from the tables rather than listed here: a hand-kept list
        // grows stale silently, and a new key with only one form would then
        // pass both this test and the key-parity test below.
        let pluralBases = Set(
            (Array(L10n.english.keys) + Array(L10n.german.keys))
                .compactMap { key -> String? in
                    if key.hasSuffix(".one") { return String(key.dropLast(4)) }
                    if key.hasSuffix(".other") { return String(key.dropLast(6)) }
                    return nil
                }
        ).sorted()
        XCTAssertFalse(pluralBases.isEmpty, "sanity: the tables do contain plural keys")
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

    /// Key parity is only half the promise. `String(format:)` reads its
    /// arguments off the *format string*, so a German translation that grew a
    /// `%@` its English original never had reads past the arguments the call
    /// site passed — and that is not a wrong word on screen, it is a crash, on
    /// German machines only, in whichever build shipped the translation.
    ///
    /// Order matters unless the string uses positional markers, which exist
    /// precisely so a translation may reorder: `%1$@ von %2$@` is a correct
    /// German rendering of `%2$@ of %1$@`, and comparing those in order would
    /// forbid the one thing positional arguments are for.
    func testEveryStringTakesTheSameArgumentsInBothLanguages() {
        for (key, english) in L10n.english {
            guard let german = L10n.german[key] else { continue }
            let left = Self.conversions(in: english)
            let right = Self.conversions(in: german)
            if english.contains("$") || german.contains("$") {
                XCTAssertEqual(left.sorted(), right.sorted(),
                               "«\(key)» takes different arguments in German: \(german)")
            } else {
                XCTAssertEqual(left, right,
                               "«\(key)» takes different arguments in German: \(german)")
            }
        }
    }

    /// The conversion characters a format string consumes, in order. `%%` is
    /// an escaped percent sign and consumes nothing.
    private static func conversions(in format: String) -> [String] {
        let pattern = "%(?:\\d+\\$)?[-+ #0]*[0-9*]*(?:\\.\\d+)?"
            + "(?:hh|h|ll|l|q|L|z|j|t)?([@dioxXufFeEgGcsp%])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let text = format as NSString
        let whole = NSRange(location: 0, length: text.length)
        return regex.matches(in: format, options: [], range: whole).compactMap { match -> String? in
            let range = match.range(at: 1)
            guard range.location != NSNotFound else { return nil }
            let conversion = text.substring(with: range)
            return conversion == "%" ? nil : conversion
        }
    }
}
