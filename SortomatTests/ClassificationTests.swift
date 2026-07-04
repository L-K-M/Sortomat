import XCTest
@testable import Sortomat

final class ClassificationTests: XCTestCase {
    private func decode(_ json: String) throws -> Classification {
        try JSONDecoder().decode(Classification.self, from: Data(json.utf8))
    }

    func testFolderAndFilename() throws {
        let c = try decode(#"{"action":"move","folder":"Fantasy/Tolkien","filename":"Hobbit.epub","confidence":0.9,"reason":"clear"}"#)
        XCTAssertTrue(c.isMove)
        XCTAssertEqual(c.resolvedRelativePath(), "Fantasy/Tolkien/Hobbit.epub")
        XCTAssertEqual(c.topFolder(), "Fantasy")
        XCTAssertEqual(c.confidence, 0.9)
    }

    func testRelativePathFallback() throws {
        let c = try decode(#"{"action":"move","relative_path":"A/B/x.epub"}"#)
        XCTAssertEqual(c.resolvedRelativePath(), "A/B/x.epub")
        XCTAssertEqual(c.topFolder(), "A")
    }

    func testEmptyFolderPlacesAtRoot() throws {
        let c = try decode(#"{"action":"move","folder":"","filename":"x.epub"}"#)
        XCTAssertEqual(c.resolvedRelativePath(), "x.epub")
        XCTAssertNil(c.topFolder())
    }

    func testSkip() throws {
        let c = try decode(#"{"action":"skip","reason":"not a book"}"#)
        XCTAssertFalse(c.isMove)
    }

    func testMissingActionDefaultsToMove() throws {
        let c = try decode(#"{"folder":"A","filename":"x.pdf"}"#)
        XCTAssertTrue(c.isMove)
    }

    func testConfidenceAsPercentString() throws {
        let c = try decode(#"{"action":"move","folder":"A","filename":"x.pdf","confidence":"85%"}"#)
        XCTAssertEqual(c.confidence ?? 0, 0.85, accuracy: 0.0001)
    }

    func testNoUsablePathReturnsNil() throws {
        let c = try decode(#"{"action":"move"}"#)
        XCTAssertNil(c.resolvedRelativePath())
    }
}
