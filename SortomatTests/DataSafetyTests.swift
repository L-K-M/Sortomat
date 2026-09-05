import XCTest
@testable import Sortomat

/// The fail-closed guarantees of the file-operation core.
final class DataSafetyTests: XCTestCase {
    private var root: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        root = fm.temporaryDirectory.appendingPathComponent("sortomat-safety-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Restore anything a test locked down so the directory can be removed.
        if let items = try? fm.contentsOfDirectory(atPath: root.path) {
            for item in items {
                try? fm.setAttributes([.posixPermissions: 0o644], ofItemAtPath: root.appendingPathComponent(item).path)
            }
        }
        try? fm.removeItem(at: root)
    }

    func testDirectoryCannotBeHashed() throws {
        // A read error (EISDIR here) must yield nil, never a digest of an
        // empty prefix that would compare equal to another failure.
        let dir = root.appendingPathComponent("folder")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        XCTAssertNil(ContentHash.digest(of: dir))
    }

    func testFailedCopyLeavesNoPartialTarget() throws {
        let source = root.appendingPathComponent("locked.txt")
        try "secret".write(to: source, atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: source.path)
        let dest = root.appendingPathComponent("out/locked.txt")

        XCTAssertThrowsError(try Mover.place(source: source, destination: dest, copy: true))
        XCTAssertFalse(fm.fileExists(atPath: dest.path), "a half-written copy must not keep the canonical name")
        XCTAssertTrue(fm.fileExists(atPath: source.path), "copy mode never touches the source")
    }

    func testCopyVerifyDeleteNeverDeletesAForeignOccupant() throws {
        let source = root.appendingPathComponent("in.txt")
        try "incoming".write(to: source, atomically: true, encoding: .utf8)
        let occupied = root.appendingPathComponent("out/taken.txt")
        try fm.createDirectory(at: occupied.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "someone else's file".write(to: occupied, atomically: true, encoding: .utf8)

        // copyItem refuses to overwrite; the old cleanup then removed the
        // occupant anyway — a file Sortomat never created.
        XCTAssertThrowsError(try Mover.copyVerifyDelete(source: source, to: occupied))
        XCTAssertEqual(try String(contentsOf: occupied, encoding: .utf8), "someone else's file")
        XCTAssertTrue(fm.fileExists(atPath: source.path), "the original is kept when the copy fails")
    }

    func testSameVolumeIsNotCrossVolume() {
        XCTAssertFalse(Mover.isCrossVolume(source: root.appendingPathComponent("a"),
                                           destination: root.appendingPathComponent("b/c")))
    }
}
