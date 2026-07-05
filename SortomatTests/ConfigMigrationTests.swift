import XCTest
@testable import Sortomat

final class ConfigMigrationTests: XCTestCase {
    func testDecodesLegacyRuleWithDefaults() throws {
        // A rule serialized by the original prototype (only the old fields).
        let json = """
        {
          "id": "11111111-1111-1111-1111-111111111111",
          "name": "Old rule",
          "watchPath": "/w",
          "targetPath": "/t",
          "prompt": "sort things",
          "extensions": ["epub"],
          "copyInsteadOfMove": true,
          "enabled": true
        }
        """
        let rule = try JSONDecoder().decode(Rule.self, from: Data(json.utf8))
        XCTAssertEqual(rule.name, "Old rule")
        XCTAssertEqual(rule.extensions, ["epub"])
        XCTAssertTrue(rule.copyInsteadOfMove)
        // New fields fall back to sensible defaults instead of failing to decode.
        XCTAssertEqual(rule.priority, 0)
        XCTAssertFalse(rule.recursive)
        XCTAssertEqual(rule.privacyMode, .full)
        XCTAssertTrue(rule.preRules.isEmpty)
        XCTAssertTrue(rule.taxonomy.isEmpty)
        XCTAssertEqual(rule.confidenceThreshold, 0)
    }

    func testDecodesLegacyConfig() throws {
        let json = """
        {
          "model": "mistral-small-latest",
          "apiBase": "https://api.mistral.ai",
          "scanIntervalSeconds": 90,
          "rules": []
        }
        """
        let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
        XCTAssertEqual(config.model, "mistral-small-latest")
        XCTAssertEqual(config.scanIntervalSeconds, 90)
        // New fields default.
        XCTAssertTrue(config.providerRequiresKey)
        XCTAssertEqual(config.maxConcurrentClassifications, 2)
    }

    func testEmptyObjectDecodesToDefaults() throws {
        let config = try JSONDecoder().decode(Config.self, from: Data("{}".utf8))
        XCTAssertEqual(config, Config())
    }

    func testRoundTrip() throws {
        var config = Config()
        config.rules = [RuleTemplate.ebooks.makeRule()]
        config.perScanBudget = 25
        let data = try JSONEncoder().encode(config)
        let decoded = try JSONDecoder().decode(Config.self, from: data)
        XCTAssertEqual(decoded, config)
    }

    func testCorruptConfigIsBackedUpNotSilentlyDiscarded() throws {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory
            .appendingPathComponent("sortomat-config-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: dir) }

        let file = dir.appendingPathComponent("config.json")
        try Data(#"{"rules": [{"name": "Precious"#.utf8).write(to: file) // torn write

        let config = ConfigStore.load(from: file)
        XCTAssertEqual(config, Config(), "an unreadable config loads as defaults")

        let backups = try fm.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasPrefix("config.json.corrupt-") }
        XCTAssertEqual(backups.count, 1, "the broken file must be preserved as a backup")
        let backupData = try Data(contentsOf: dir.appendingPathComponent(backups[0]))
        XCTAssertTrue(String(decoding: backupData, as: UTF8.self).contains("Precious"))
    }
}
