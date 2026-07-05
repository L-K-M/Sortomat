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

    // MARK: - Cross-volume fallback

    func testCopyVerifyDeleteMovesContentAndRemovesSource() throws {
        let source = try makeFile("in.txt", "payload")
        let dest = root.appendingPathComponent("out/there.txt")
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Mover.copyVerifyDelete(source: source, to: dest)
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "payload")
        XCTAssertFalse(fm.fileExists(atPath: source.path))
    }

    func testUnhashableFileYieldsNilDigestNotAMatch() {
        // The fail-closed guard in copyVerifyDelete relies on digest returning
        // nil (never a colliding value) for an unreadable file.
        XCTAssertNil(ContentHash.digest(of: root.appendingPathComponent("nope.bin")))
    }

    func testFullContentDigestSeesDifferencesBeyondTheDedupPrefix() throws {
        // Two files identical for the first 4 MiB and equal in size, differing
        // only afterwards: the bounded dedup digest can't tell them apart, but
        // the full-content digest used for cross-volume verification must.
        let prefix = Data(repeating: 0xAB, count: 4 * 1024 * 1024)
        var a = prefix; a.append(Data("tail-A".utf8))
        var b = prefix; b.append(Data("tail-B".utf8))
        let urlA = root.appendingPathComponent("a.bin")
        let urlB = root.appendingPathComponent("b.bin")
        try a.write(to: urlA)
        try b.write(to: urlB)

        XCTAssertEqual(ContentHash.digest(of: urlA), ContentHash.digest(of: urlB),
                       "bounded prefix digest is expected to collide here")
        XCTAssertNotEqual(ContentHash.digest(of: urlA, limit: .max),
                          ContentHash.digest(of: urlB, limit: .max),
                          "full-content digest must distinguish the files")
    }
}
