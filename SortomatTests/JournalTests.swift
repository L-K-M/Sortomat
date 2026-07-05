import XCTest
@testable import Sortomat

final class JournalTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-journal-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        setenv("SORTOMAT_CONFIG_DIR", dir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("SORTOMAT_CONFIG_DIR")
        try? fm.removeItem(at: dir)
    }

    func testRecordThenReadBack() {
        let entry = JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: "/a/x.txt",
                                 destinationPath: "/b/x.txt", wasCopy: false, reason: "r")
        Journal.record(entry)
        let recent = Journal.recent()
        XCTAssertEqual(recent.first?.id, entry.id)
    }

    func testUndoMoveRestoresSource() throws {
        let source = dir.appendingPathComponent("original/x.txt")
        let dest = dir.appendingPathComponent("sorted/x.txt")
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "content".write(to: dest, atomically: true, encoding: .utf8)

        let entry = JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                 destinationPath: dest.path, wasCopy: false, reason: "r")
        try Journal.undo(entry)
        XCTAssertTrue(fm.fileExists(atPath: source.path))
        XCTAssertFalse(fm.fileExists(atPath: dest.path))
    }

    func testUndoCopyRemovesCopy() throws {
        let source = dir.appendingPathComponent("original/x.txt")
        let dest = dir.appendingPathComponent("sorted/x.txt")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "content".write(to: source, atomically: true, encoding: .utf8)
        try "content".write(to: dest, atomically: true, encoding: .utf8)

        let entry = JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                 destinationPath: dest.path, wasCopy: true, reason: "r")
        try Journal.undo(entry)
        XCTAssertFalse(fm.fileExists(atPath: dest.path))  // copy removed
        XCTAssertTrue(fm.fileExists(atPath: source.path)) // original untouched
    }

    func testUndoRefusesToClobberReappearedSource() throws {
        let source = dir.appendingPathComponent("original/x.txt")
        let dest = dir.appendingPathComponent("sorted/x.txt")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "new".write(to: source, atomically: true, encoding: .utf8)
        try "moved".write(to: dest, atomically: true, encoding: .utf8)

        let entry = JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                 destinationPath: dest.path, wasCopy: false, reason: "r")
        XCTAssertThrowsError(try Journal.undo(entry))
    }

    func testUndoCopyRefusesWhenCopyWasModified() throws {
        // The copy diverged from the original (the user edited it) — undo must
        // not silently delete their work.
        let source = dir.appendingPathComponent("original/x.txt")
        let dest = dir.appendingPathComponent("sorted/x.txt")
        try fm.createDirectory(at: source.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "original".write(to: source, atomically: true, encoding: .utf8)
        try "edited since the copy".write(to: dest, atomically: true, encoding: .utf8)

        let entry = JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                 destinationPath: dest.path, wasCopy: true, reason: "r")
        XCTAssertThrowsError(try Journal.undo(entry))
        XCTAssertTrue(fm.fileExists(atPath: dest.path), "the diverged copy must survive")
    }

    func testUndoneEntryDisappearsFromRecent() throws {
        let source = dir.appendingPathComponent("original/x.txt")
        let dest = dir.appendingPathComponent("sorted/x.txt")
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "content".write(to: dest, atomically: true, encoding: .utf8)

        let entry = JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                 destinationPath: dest.path, wasCopy: false, reason: "r")
        Journal.record(entry)
        XCTAssertTrue(Journal.recent().contains(where: { $0.id == entry.id }))

        try Journal.undo(entry)
        // Neither the undone entry nor its tombstone may resurface with a
        // live Undo button after a reload.
        let after = Journal.recent()
        XCTAssertFalse(after.contains(where: { $0.id == entry.id }))
        XCTAssertFalse(after.contains(where: { $0.undoOf != nil }))
    }

    func testLegacyJournalLineWithoutUndoFieldStillDecodes() throws {
        let json = #"{"id":"22222222-2222-2222-2222-222222222222","date":700000000,"ruleID":"11111111-1111-1111-1111-111111111111","ruleName":"R","sourcePath":"/a","destinationPath":"/b","wasCopy":false,"reason":"r"}"#
        let entry = try JSONDecoder().decode(JournalEntry.self, from: Data(json.utf8))
        XCTAssertNil(entry.undoOf)
    }
}
