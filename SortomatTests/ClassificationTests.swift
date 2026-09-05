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

    func testConfidenceAsPercentNumberIsNormalized() throws {
        // A numeric 85 must mean 85 %, not "8500 % — clears every threshold".
        let c = try decode(#"{"action":"move","folder":"A","filename":"x.pdf","confidence":85}"#)
        XCTAssertEqual(c.confidence ?? 0, 0.85, accuracy: 0.0001)
    }

    func testConfidenceIsClampedToUnitRange() throws {
        let c = try decode(#"{"action":"move","folder":"A","filename":"x.pdf","confidence":850}"#)
        XCTAssertEqual(c.confidence ?? 0, 1.0, accuracy: 0.0001)
    }

    func testFractionalConfidencePassesThroughUnchanged() throws {
        let c = try decode(#"{"action":"move","folder":"A","filename":"x.pdf","confidence":0.42}"#)
        XCTAssertEqual(c.confidence ?? 0, 0.42, accuracy: 0.0001)
    }

    func testUnknownActionIsTreatedAsSkipNotMove() throws {
        for action in ["ignore", "none", "delete", "unsure"] {
            let c = try decode(#"{"action":"\#(action)","folder":"A","filename":"x.pdf"}"#)
            XCTAssertFalse(c.isMove, "action \"\(action)\" must not move a file")
        }
    }

    func testAffirmativeActionsStillMove() throws {
        for action in ["move", "copy", "file", "sort", "rename", "MOVE"] {
            let c = try decode(#"{"action":"\#(action)","folder":"A","filename":"x.pdf"}"#)
            XCTAssertTrue(c.isMove, "action \"\(action)\" should move a file")
        }
    }

    func testNoUsablePathReturnsNil() throws {
        let c = try decode(#"{"action":"move"}"#)
        XCTAssertNil(c.resolvedRelativePath())
    }


    // MARK: - Off-schema answers

    func testBooleanFalseActionIsASkip() throws {
        let c = try decode(#"{"action":false,"folder":"A","filename":"x.pdf"}"#)
        XCTAssertFalse(c.isMove, "an explicit refusal must not move the file")
    }

    func testBooleanTrueActionIsAMove() throws {
        XCTAssertTrue(try decode(#"{"action":true,"folder":"A","filename":"x.pdf"}"#).isMove)
    }

    func testNullActionIsASkip() throws {
        XCTAssertFalse(try decode(#"{"action":null,"folder":"A","filename":"x.pdf"}"#).isMove)
    }

    func testConfidenceInEveryShape() throws {
        XCTAssertEqual(Classification.parseConfidence("0,85") ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(Classification.parseConfidence(" 85 % ") ?? 0, 0.85, accuracy: 0.0001)
        XCTAssertEqual(Classification.parseConfidence("high") ?? 0, 0.9, accuracy: 0.0001)
        XCTAssertNil(Classification.parseConfidence("maybe"))
        let c = try decode(#"{"action":"move","folder":"A","filename":"x.pdf","confidence":"0,42"}"#)
        XCTAssertEqual(c.confidence ?? 0, 0.42, accuracy: 0.0001)
    }

    func testTopFolderIgnoresLeadingDotSegment() throws {
        XCTAssertEqual(try decode(#"{"action":"move","relative_path":"./Fantasy/x.epub"}"#).topFolder(), "Fantasy")
        XCTAssertEqual(try decode(#"{"action":"move","folder":"./Krimi","filename":"x.epub"}"#).topFolder(), "Krimi")
        XCTAssertEqual(Classification.topFolder(ofRelativePath: "./A/B/x.pdf"), "A")
        XCTAssertNil(Classification.topFolder(ofRelativePath: "x.pdf"))
    }
}
