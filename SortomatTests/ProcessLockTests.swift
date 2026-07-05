import XCTest
@testable import Sortomat

final class ProcessLockTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-lock-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    func testExclusiveWhileHeldAndReacquirableAfterRelease() {
        let first = ProcessLock.acquire(directory: dir)
        XCTAssertNotNil(first)
        // flock is per open-file-description, so a second open() in the same
        // process contends just like a second process would.
        XCTAssertNil(ProcessLock.acquire(directory: dir), "the lock must be exclusive")

        first?.release()
        let second = ProcessLock.acquire(directory: dir)
        XCTAssertNotNil(second, "release must free the lock")
        second?.release()
    }

    func testDeinitReleasesTheLock() {
        do {
            let scoped = ProcessLock.acquire(directory: dir)
            XCTAssertNotNil(scoped)
        } // scoped deallocates here
        XCTAssertNotNil(ProcessLock.acquire(directory: dir),
                        "a deallocated lock must not stay held")
    }

    func testCreatesTheDirectoryIfMissing() {
        let fresh = dir.appendingPathComponent("nested/deeper")
        let lock = ProcessLock.acquire(directory: fresh)
        XCTAssertNotNil(lock)
        lock?.release()
    }
}
