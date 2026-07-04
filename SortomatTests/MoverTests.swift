import XCTest
@testable import Sortomat

final class MoverTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("sortomat-mover-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: root)
    }

    private func makeFile(_ name: String, _ contents: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    func testMovePlacesFileAndRemovesSource() throws {
        let source = try makeFile("in.txt", "hello")
        let dest = root.appendingPathComponent("out/there.txt")
        let outcome = try Mover.place(source: source, destination: dest, copy: false)
        XCTAssertEqual(outcome, .placed(dest))
        XCTAssertTrue(fm.fileExists(atPath: dest.path))
        XCTAssertFalse(fm.fileExists(atPath: source.path))
    }

    func testCopyKeepsSource() throws {
        let source = try makeFile("in.txt", "hello")
        let dest = root.appendingPathComponent("out/there.txt")
        _ = try Mover.place(source: source, destination: dest, copy: true)
        XCTAssertTrue(fm.fileExists(atPath: dest.path))
        XCTAssertTrue(fm.fileExists(atPath: source.path))
    }

    func testCollisionGetsSuffixWhenContentDiffers() throws {
        let dest = root.appendingPathComponent("out/there.txt")
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "existing".write(to: dest, atomically: true, encoding: .utf8)

        let source = try makeFile("in.txt", "different content")
        let outcome = try Mover.place(source: source, destination: dest, copy: false)
        XCTAssertEqual(placedURL(outcome)?.lastPathComponent, "there (2).txt")
    }

    private func placedURL(_ outcome: MoveOutcome) -> URL? {
        if case .placed(let url) = outcome { return url }
        return nil
    }

    func testIdenticalContentIsDuplicateNotSecondCopy() throws {
        let dest = root.appendingPathComponent("out/there.txt")
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "same bytes".write(to: dest, atomically: true, encoding: .utf8)

        let source = try makeFile("in.txt", "same bytes")
        let outcome = try Mover.place(source: source, destination: dest, copy: false)
        if case .duplicate = outcome {} else { XCTFail("expected duplicate, got \(outcome)") }
        // Source is left in place; no " (2)" file created.
        XCTAssertTrue(fm.fileExists(atPath: source.path))
        XCTAssertFalse(fm.fileExists(atPath: root.appendingPathComponent("out/there (2).txt").path))
    }

    func testEqualSizeDifferentContentIsNotDuplicate() throws {
        // Two files of identical byte length but different bytes must not collide
        // into a false duplicate (the size-only bug this fixes).
        let dest = root.appendingPathComponent("out/there.txt")
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "AAAAA".write(to: dest, atomically: true, encoding: .utf8)

        let source = try makeFile("in.txt", "BBBBB") // same length, different bytes
        let outcome = try Mover.place(source: source, destination: dest, copy: false)
        XCTAssertEqual(placedURL(outcome)?.lastPathComponent, "there (2).txt")
    }

    func testVanishedSourceThrows() {
        let source = root.appendingPathComponent("missing.txt")
        let dest = root.appendingPathComponent("out/there.txt")
        XCTAssertThrowsError(try Mover.place(source: source, destination: dest, copy: false)) { error in
            XCTAssertEqual(error as? MoveError, .sourceVanished)
        }
    }
}
