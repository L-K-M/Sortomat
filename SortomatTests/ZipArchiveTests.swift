import XCTest
@testable import Sortomat

final class ZipArchiveTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-zip-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    func testFakeEOCDSignatureInCommentDoesNotWinOverTheRealRecord() throws {
        // Build a valid one-entry archive, then give its EOCD a 22-byte
        // comment that *starts with the EOCD signature*. A backwards scan that
        // takes the first signature it meets locks onto the fake and rejects
        // the archive; the validated scan must keep going and parse normally.
        var writer = ZipWriter()
        writer.add("hello.txt", "hello zip")
        var data = writer.data()

        let eocdStart = data.count - 22
        let commentLengthField = eocdStart + 20
        data[commentLengthField] = 22       // comment length: 22 bytes (LE)
        data[commentLengthField + 1] = 0
        var comment = Data([0x50, 0x4B, 0x05, 0x06])           // fake "PK\5\6"
        comment.append(Data(repeating: 0xFF, count: 18))       // filler that can't validate
        data.append(comment)

        let url = dir.appendingPathComponent("commented.zip")
        try data.write(to: url)

        let archive = ZipArchive(url: url)
        XCTAssertNotNil(archive, "a valid archive with a hostile comment must still open")
        let entry = archive?.entry(named: "hello.txt")
        XCTAssertNotNil(entry)
        XCTAssertEqual(entry.flatMap { archive?.data(for: $0) },
                       Data("hello zip".utf8))
    }

    func testArchiveWithEmptyCommentStillParses() throws {
        var writer = ZipWriter()
        writer.add("a.txt", "A")
        let url = dir.appendingPathComponent("plain.zip")
        try writer.data().write(to: url)

        let archive = ZipArchive(url: url)
        XCTAssertEqual(archive?.entries.count, 1)
    }
}
