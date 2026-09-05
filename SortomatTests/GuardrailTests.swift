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
        let dollars = AppState.money(1.2345, code: "USD")
        XCTAssertTrue(dollars.contains("1"), "got: \(dollars)")
        XCTAssertTrue(dollars.contains("2345"), "four decimals: a classification costs fractions of a cent")
        let euros = AppState.money(1.2345, code: "EUR")
        XCTAssertNotEqual(dollars, euros, "the currency has to reach the string")
        XCTAssertFalse(euros.contains("$"), "got: \(euros)")
    }

    func testAnUnknownCurrencyCodeStillProducesANumber() {
        // Nothing validates what the user types into the field, and a meter
        // that renders as nothing at all is worse than one that renders oddly.
        let text = AppState.money(0.5, code: "NOTACODE")
        XCTAssertFalse(text.isEmpty)
        XCTAssertTrue(text.contains("0"), "got: \(text)")
    }

    // MARK: - Power

    func testEachHoldIsExplainedInBothLanguages() {
        var config = Config()
        config.pauseInLowPowerMode = true
        config.onlyOnPower = true
        for language in ["en", "de"] {
            L10n.forcedLanguage = language
            let lowPower = AppState.hold(for: config, lowPower: true, onBattery: false)
            let battery = AppState.hold(for: config, lowPower: false, onBattery: true)
            for text in [lowPower, battery] {
                XCTAssertNotNil(text, "\(language) gave no reason at all")
                XCTAssertFalse(text?.hasPrefix("hold.") ?? true,
                               "\(language) renders its key: \(text ?? "nil")")
            }
            XCTAssertNotEqual(lowPower, battery, "two different reasons, two different sentences")
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

    func testPowerQueriesFailOpen() {
        // A desktop has no battery and an IOKit answer can be unreadable;
        // refusing to work because a power query failed would be a worse bug
        // than the one the setting prevents. Both answers are booleans that
        // must not trap on any machine, CI included.
        _ = PowerSource.isOnBattery
        _ = PowerSource.isInLowPowerMode
    }
}
