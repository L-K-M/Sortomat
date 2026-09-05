import XCTest
@testable import Sortomat

/// What a pass costs when nothing is happening, and what it leaves behind.
final class PassEfficiencyTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-perf-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Undo appends a tombstone; keep it out of the developer's real
        // journal.
        setenv("SORTOMAT_CONFIG_DIR", dir.path, 1)
    }

    override func tearDownWithError() throws {
        unsetenv("SORTOMAT_CONFIG_DIR")
        try? fm.removeItem(at: dir)
    }

    private func plant(_ name: String, bytes: Int = 8, ageSeconds: TimeInterval = 60) throws -> URL {
        let url = dir.appendingPathComponent(name)
        try Data(count: bytes).write(to: url)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -ageSeconds)],
                             ofItemAtPath: url.path)
        return url
    }

    // MARK: - One pause per pass, not one per file

    func testTheStabilityProbeWaitsOnceForTheWholePass() async throws {
        // The probe used to run per file: at the default concurrency of 2, a
        // thousand-file backlog spent about six minutes asleep on every pass.
        // Forty files must cost one pause, not forty.
        let files = try (0..<40).map { try plant("settled\($0).bin") }
        let start = Date()
        let settled = await Pipeline.settledPaths(among: files)
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(settled.count, files.count)
        XCTAssertLessThan(elapsed, 3, "40 files must not cost 40 pauses")
        XCTAssertGreaterThan(elapsed, 0.5, "sanity: it did wait once")
    }

    func testAFileWrittenAMomentAgoIsNotSettled() async throws {
        let fresh = try plant("fresh.bin", ageSeconds: 0)
        let old = try plant("old.bin", ageSeconds: 60)
        let settled = await Pipeline.settledPaths(among: [fresh, old], pause: 1_000_000)
        XCTAssertFalse(settled.contains(fresh.path), "still in flight whatever its size says")
        XCTAssertTrue(settled.contains(old.path))
    }

    func testAFileWithAFutureTimestampIsNotParkedForever() async throws {
        // A bad camera clock or a sloppy downloader stamps the future; the
        // size comparison still catches a file that is actually growing.
        let url = dir.appendingPathComponent("tomorrow.bin")
        try Data(count: 8).write(to: url)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 86_400)],
                             ofItemAtPath: url.path)
        let settled = await Pipeline.settledPaths(among: [url], pause: 1_000_000)
        XCTAssertTrue(settled.contains(url.path))
    }

    func testAGrowingFileIsNotSettled() async throws {
        let url = try plant("growing.bin", bytes: 8)
        async let settled = Pipeline.settledPaths(among: [url], pause: 400_000_000)
        try await Task.sleep(nanoseconds: 100_000_000)
        try Data(count: 4096).write(to: url)
        let result = await settled
        XCTAssertFalse(result.contains(url.path), "a file that grew mid-probe is still being written")
    }

    func testProbingNothingCostsNothing() async {
        let start = Date()
        let settled = await Pipeline.settledPaths(among: [])
        XCTAssertTrue(settled.isEmpty)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.3, "an empty folder must not sleep")
    }

    // MARK: - The interval a slider promises

    func testTimerIntervalIsClampedNotTrapped() {
        XCTAssertEqual(AppState.timerNanoseconds(for: 60), 60_000_000_000)
        XCTAssertEqual(AppState.timerNanoseconds(for: 1), 10_000_000_000, "floor")
        XCTAssertEqual(AppState.timerNanoseconds(for: 1_000_000), 86_400_000_000_000, "ceiling")
        // A hand-edited config.json can hold anything; a NaN would trap the
        // UInt64 conversion at launch.
        XCTAssertEqual(AppState.timerNanoseconds(for: .nan), 60_000_000_000)
        XCTAssertEqual(AppState.timerNanoseconds(for: .infinity), 60_000_000_000)
    }

    // MARK: - Undo leaves no skeleton behind

    func testPruningNormalizesTildePathsOnBothSides() throws {
        // Expanding the target root but not the destination compared a tilde
        // path against an expanded one: `hasPrefix` was false and the pruning
        // silently never ran, in exactly the case the expansion was added for.
        // Calls the pruning directly — `undo` itself would refuse a tilde
        // destination earlier, at its `fileExists` check.
        let relative = "sortomat-prune-\(UUID().uuidString)"
        let target = URL(fileURLWithPath: "\(NSHomeDirectory())/\(relative)")
        let nested = target.appendingPathComponent("Fantasy")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: target) }

        // The state undo leaves behind: the file is gone, the folders are not.
        Journal.pruneEmptyFolders(under: JournalEntry(
            ruleID: UUID(), ruleName: "R", sourcePath: "/in/book.epub",
            destinationPath: "~/\(relative)/Fantasy/book.epub", wasCopy: false, reason: "r",
            targetPath: "~/\(relative)"
        ))
        XCTAssertFalse(fm.fileExists(atPath: nested.path), "a tilde journal prunes like any other")
        XCTAssertTrue(fm.fileExists(atPath: target.path), "but never the target root itself")
    }

    func testUndoPrunesTheFoldersTheMoveCreated() throws {
        let target = dir.appendingPathComponent("target")
        let nested = target.appendingPathComponent("Fantasy/Tolkien")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        let placed = nested.appendingPathComponent("book.epub")
        try "book".write(to: placed, atomically: true, encoding: .utf8)
        let source = dir.appendingPathComponent("in/book.epub")

        let entry = JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                 destinationPath: placed.path, wasCopy: false, reason: "r",
                                 targetPath: target.path)
        try Journal.undo(entry)

        XCTAssertTrue(fm.fileExists(atPath: source.path))
        XCTAssertFalse(fm.fileExists(atPath: nested.path), "the empty Author folder goes")
        XCTAssertFalse(fm.fileExists(atPath: target.appendingPathComponent("Fantasy").path),
                       "and the empty Genre folder above it")
        XCTAssertTrue(fm.fileExists(atPath: target.path), "but never the user's own target folder")
    }

    func testPruningStopsAtTheFirstFolderThatStillHoldsSomething() throws {
        let target = dir.appendingPathComponent("target")
        let genre = target.appendingPathComponent("Fantasy")
        let author = genre.appendingPathComponent("Tolkien")
        try fm.createDirectory(at: author, withIntermediateDirectories: true)
        try "keep".write(to: genre.appendingPathComponent("other.epub"),
                         atomically: true, encoding: .utf8)
        let placed = author.appendingPathComponent("book.epub")
        try "book".write(to: placed, atomically: true, encoding: .utf8)
        let source = dir.appendingPathComponent("in/book.epub")

        try Journal.undo(JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                      destinationPath: placed.path, wasCopy: false, reason: "r",
                                      targetPath: target.path))

        XCTAssertFalse(fm.fileExists(atPath: author.path))
        XCTAssertTrue(fm.fileExists(atPath: genre.appendingPathComponent("other.epub").path),
                      "a folder with anything else in it is somebody's, not ours")
    }

    func testAJournalWrittenBeforeTargetPathPrunesNothing() throws {
        let target = dir.appendingPathComponent("target")
        let nested = target.appendingPathComponent("Fantasy")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        let placed = nested.appendingPathComponent("book.epub")
        try "book".write(to: placed, atomically: true, encoding: .utf8)
        let source = dir.appendingPathComponent("in/book.epub")

        // No targetPath: an entry from an older build has no root to stop at,
        // so it keeps the old leave-it-behind behaviour rather than guessing.
        try Journal.undo(JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                      destinationPath: placed.path, wasCopy: false, reason: "r"))
        XCTAssertTrue(fm.fileExists(atPath: nested.path))
    }

    func testAFinderDroppingDidNotMakeTheFolderNonEmpty() throws {
        let target = dir.appendingPathComponent("target")
        let nested = target.appendingPathComponent("Fantasy")
        try fm.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data().write(to: nested.appendingPathComponent(".DS_Store"))
        let placed = nested.appendingPathComponent("book.epub")
        try "book".write(to: placed, atomically: true, encoding: .utf8)
        let source = dir.appendingPathComponent("in/book.epub")

        try Journal.undo(JournalEntry(ruleID: UUID(), ruleName: "R", sourcePath: source.path,
                                      destinationPath: placed.path, wasCopy: false, reason: "r",
                                      targetPath: target.path))
        XCTAssertFalse(fm.fileExists(atPath: nested.path),
                       "a lone .DS_Store is not somebody's file")
    }

    // MARK: - Names that fit on the disk

    func testComponentTruncationRespectsTheByteLimitToo() {
        // 150 CJK characters is 450 bytes; APFS caps a component at 255, so a
        // perfectly sanitized name still failed the move with ENAMETOOLONG —
        // every pass, forever, for the same file.
        let long = String(repeating: "書", count: 200)
        let cleaned = Sanitizer.sanitizeComponent(long)
        XCTAssertLessThanOrEqual(cleaned.utf8.count, Sanitizer.maxComponentBytes)
        XCTAssertFalse(cleaned.isEmpty)
    }

    func testTruncationNeverSplitsACharacter() {
        let emoji = String(repeating: "👩‍👩‍👧‍👦", count: 40)
        let cleaned = Sanitizer.sanitizeComponent(emoji)
        XCTAssertLessThanOrEqual(cleaned.utf8.count, Sanitizer.maxComponentBytes)
        XCTAssertFalse(cleaned.isEmpty)
        // Every family emoji is 25 bytes; an exact multiple is the proof that
        // the cut landed between graphemes and not inside a joiner sequence.
        XCTAssertEqual(cleaned.utf8.count, cleaned.count * 25,
                       "a truncation split a character: \(cleaned.utf8.count) bytes, \(cleaned.count) characters")
    }

    func testTheForcedExtensionFitsInsideTheByteLimitToo() throws {
        // The sanitizer capped the *name*; the real extension was forced on
        // afterwards, so a 252-byte CJK title plus ".epub" was a 257-byte
        // component and ENAMETOOLONG came straight back.
        let long = String(repeating: "書", count: 200)
        let url = try Sanitizer.destination(target: URL(fileURLWithPath: "/t"),
                                            relativePath: "\(long).epub",
                                            originalExtension: "epub")
        let component = url.lastPathComponent
        XCTAssertLessThanOrEqual(component.utf8.count, Sanitizer.maxComponentBytes)
        XCTAssertTrue(component.hasSuffix(".epub"), "the extension is how the file is recognized")
    }

    func testAnExtensionTooLongForAnyStemStillProducesAName() {
        // Degenerate, but a component that came back as just ".ext" — or
        // empty — would fail the move rather than shorten the name.
        let absurd = "a." + String(repeating: "x", count: 400)
        let fitted = Sanitizer.fittingComponent(absurd)
        XCTAssertFalse(fitted.isEmpty)
        XCTAssertLessThanOrEqual(fitted.utf8.count, Sanitizer.maxComponentBytes)
    }

    func testAsciiNamesAreStillCutAtTheCharacterLimit() {
        let long = String(repeating: "a", count: 400)
        XCTAssertEqual(Sanitizer.sanitizeComponent(long).count, 150)
    }
}
