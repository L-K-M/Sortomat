import XCTest
@testable import Sortomat

/// The settings that stop Sortomat from being expensive, rude to a battery, or
/// impossible to switch off.
final class GuardrailTests: XCTestCase {
    override func tearDown() {
        L10n.forcedLanguage = nil
    }

    // MARK: - The brake survives a relaunch

    func testPauseIsPartOfTheStoredConfig() throws {
        var config = Config()
        XCTAssertFalse(config.paused)
        config.paused = true
        let round = try JSONDecoder().decode(Config.self, from: JSONEncoder().encode(config))
        XCTAssertTrue(round.paused, "the emergency brake must survive a relaunch")
    }

    func testAConfigWrittenBeforeTheseSettingsStillDecodes() throws {
        // Every field is optional on the way in: a config.json from an older
        // build must not make the app unlaunchable.
        let json = #"{"model":"m","apiBase":"https://example.test","rules":[]}"#
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertFalse(config.paused)
        XCTAssertEqual(config.monthlyBudget, 0, "no ceiling until someone sets one")
        XCTAssertEqual(config.currencyCode, "USD")
        XCTAssertFalse(config.onlyOnPower)
        XCTAssertTrue(config.pauseInLowPowerMode, "the default that costs nobody anything")
    }

    // MARK: - The money ceiling

    func testNoCeilingMeansNoCeiling() {
        XCTAssertTrue(AppState.withinBudget(spend: 9_999, ceiling: 0))
        XCTAssertTrue(AppState.withinBudget(spend: 9_999, ceiling: -1))
    }

    func testSpendingPastTheCeilingClosesTheValve() {
        XCTAssertTrue(AppState.withinBudget(spend: 0.99, ceiling: 1))
        XCTAssertFalse(AppState.withinBudget(spend: 1, ceiling: 1),
                       "at the ceiling is past it — the next call is what tips over")
        XCTAssertFalse(AppState.withinBudget(spend: 2, ceiling: 1))
    }

    // MARK: - The meter reads like money

    func testSpendIsFormattedAsTheChosenCurrency() {
        // Compared against a formatter built the same way rather than against
        // ASCII digits: a machine set to ar_SA renders ١٫٢٣٤٥, and asserting on
        // the literal "2345" would fail there while the code was correct.
        for locale in [Locale(identifier: "en_US"), Locale(identifier: "de_DE"),
                       Locale(identifier: "ar_SA")] {
            let dollars = AppState.money(1.2345, code: "USD", locale: locale)
            let reference = AppState.moneyFormatter(code: "USD", locale: locale)
            XCTAssertEqual(dollars, reference.string(from: NSNumber(value: 1.2345)))
            XCTAssertFalse(dollars.isEmpty, "\(locale.identifier) rendered nothing")

            let euros = AppState.money(1.2345, code: "EUR", locale: locale)
            XCTAssertNotEqual(dollars, euros,
                              "\(locale.identifier): the currency has to reach the string")
        }
    }

    func testFourDecimalsSurviveTheFormatter() {
        // A classification costs fractions of a cent; a meter that reads 0.00
        // for the first two hundred files teaches the user it doesn't work.
        let formatter = AppState.moneyFormatter(code: "USD", locale: Locale(identifier: "en_US"))
        XCTAssertEqual(formatter.minimumFractionDigits, 4)
        XCTAssertEqual(AppState.money(1.2345, code: "USD", locale: Locale(identifier: "en_US")),
                       "$1.2345")
    }

    func testAnUnknownCurrencyCodeStillProducesANumber() {
        // Nothing validates what the user types into the field, and a meter
        // that renders as nothing at all is worse than one that renders oddly.
        let text = AppState.money(0.5, code: "NOTACODE", locale: Locale(identifier: "en_US"))
        XCTAssertFalse(text.isEmpty)
    }

    func testACurrencyCodeIsNormalizedToUpperCase() {
        // The settings field is free text; `NumberFormatter` wants ISO 4217.
        var config = Config()
        config.currencyCode = "eur"
        XCTAssertEqual(config.currencyCode, "EUR")
    }

    // MARK: - Power

    func testEachHoldIsExplainedInEveryLanguage() {
        var config = Config()
        config.pauseInLowPowerMode = true
        config.onlyOnPower = true
        for language in L10n.supportedLanguages {
            L10n.forcedLanguage = language
            let lowPower = AppState.hold(for: config, lowPower: true, onBattery: false)
            let battery = AppState.hold(for: config, lowPower: false, onBattery: true)
            for text in [lowPower, battery] {
                XCTAssertNotNil(text, "\(language) gave no reason at all")
                XCTAssertFalse(text?.hasPrefix("hold.") ?? true,
                               "\(language) renders its key: \(text ?? "nil")")
            }
            XCTAssertNotEqual(lowPower, battery, "two different reasons, two different sentences")
            // The most power-constrained case of all was the only untested
            // one: a branch structure that treated the two as exclusive would
            // return nil here and hold the pass with no explanation at all.
            XCTAssertNotNil(AppState.hold(for: config, lowPower: true, onBattery: true),
                            "\(language): both triggers active must still name a reason")
        }
    }

    func testASettingThatIsOffHoldsNothing() {
        var config = Config()
        config.pauseInLowPowerMode = false
        config.onlyOnPower = false
        XCTAssertNil(AppState.hold(for: config, lowPower: true, onBattery: true),
                     "with both settings off nothing may hold a pass")
    }

    func testEachSettingOnlyHoldsForItsOwnCondition() {
        var lowPowerOnly = Config()
        lowPowerOnly.pauseInLowPowerMode = true
        lowPowerOnly.onlyOnPower = false
        XCTAssertNil(AppState.hold(for: lowPowerOnly, lowPower: false, onBattery: true),
                     "battery alone is not Low Power Mode")

        var powerOnly = Config()
        powerOnly.pauseInLowPowerMode = false
        powerOnly.onlyOnPower = true
        XCTAssertNil(AppState.hold(for: powerOnly, lowPower: true, onBattery: false),
                     "Low Power Mode on a plugged-in Mac is not battery")
    }

    func testPowerQueriesDoNotTrap() {
        // Named for what it actually checks. The fail-open *policy* — a
        // desktop, or an IOKit answer we can't read, counting as plugged in —
        // isn't observable through a `Bool`; asserting it needs `PowerSource`
        // behind a protocol so a failing implementation can be injected, which
        // is a follow-up. What this pins is that neither query traps on any
        // machine, CI's included.
        _ = PowerSource.isOnBattery
        _ = PowerSource.isInLowPowerMode
    }
}
