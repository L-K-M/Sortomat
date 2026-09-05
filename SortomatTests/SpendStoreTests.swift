import XCTest
@testable import Sortomat

final class SpendStoreTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-spend-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    private var file: URL { dir.appendingPathComponent("spend.json") }

    func testMonthKeyFormat() {
        var comps = DateComponents()
        comps.year = 2026; comps.month = 7; comps.day = 5
        let date = Calendar(identifier: .gregorian).date(from: comps)!
        XCTAssertEqual(SpendStore.monthKey(for: date), "2026-07")
    }

    func testRoundTripWithinTheSameMonth() {
        let now = Date()
        let stored = SpendStore(month: SpendStore.monthKey(for: now), input: 1200, output: 340)
        stored.save(to: file)
        let loaded = SpendStore.load(from: file, now: now)
        XCTAssertEqual(loaded, stored)
        XCTAssertEqual(loaded.usage.input, 1200)
        XCTAssertEqual(loaded.usage.output, 340)
    }

    func testStaleMonthResetsToZero() {
        SpendStore(month: "2020-01", input: 999, output: 999).save(to: file)
        let now = Date()
        let loaded = SpendStore.load(from: file, now: now)
        XCTAssertEqual(loaded.month, SpendStore.monthKey(for: now))
        XCTAssertEqual(loaded.input, 0)
        XCTAssertEqual(loaded.output, 0)
    }

    func testMissingOrTornFileYieldsZero() throws {
        let loaded = SpendStore.load(from: file)
        XCTAssertEqual(loaded.input, 0)

        try Data("{not json".utf8).write(to: file)
        let torn = SpendStore.load(from: file)
        XCTAssertEqual(torn.input, 0)
    }
}
