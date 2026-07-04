import XCTest
@testable import Sortomat

final class SanitizerTests: XCTestCase {
    private let target = URL(fileURLWithPath: "/tmp/sortomat-target")

    // MARK: - Component sanitization

    func testStripsForbiddenCharacters() {
        XCTAssertEqual(Sanitizer.sanitizeComponent("a/b:c*d?"), "a b c d")
    }

    func testCollapsesWhitespaceAndTrimsDots() {
        XCTAssertEqual(Sanitizer.sanitizeComponent("  Hello   World . "), "Hello World")
    }

    func testEmptyBecomesUnknown() {
        XCTAssertEqual(Sanitizer.sanitizeComponent("   ...  "), "Unbekannt")
        XCTAssertEqual(Sanitizer.sanitizeComponent(".."), "Unbekannt")
    }

    func testTruncatesToMaxLength() {
        let long = String(repeating: "x", count: 400)
        XCTAssertEqual(Sanitizer.sanitizeComponent(long, maxLength: 10).count, 10)
    }

    // MARK: - Destination building & path safety

    func testBuildsNestedDestination() throws {
        let url = try Sanitizer.destination(
            target: target, relativePath: "Fantasy/Tolkien, J.R.R./Hobbit.epub",
            originalExtension: "epub"
        )
        XCTAssertEqual(url.path, "/tmp/sortomat-target/Fantasy/Tolkien, J.R.R./Hobbit.epub")
    }

    func testForcesOriginalExtension() throws {
        let url = try Sanitizer.destination(
            target: target, relativePath: "Docs/report.txt", originalExtension: "pdf"
        )
        XCTAssertEqual(url.lastPathComponent, "report.pdf")
    }

    func testRejectsTraversal() {
        XCTAssertThrowsError(try Sanitizer.destination(
            target: target, relativePath: "../../etc/passwd", originalExtension: "txt"
        ))
    }

    func testRejectsAbsolutePath() {
        XCTAssertThrowsError(try Sanitizer.destination(
            target: target, relativePath: "/etc/passwd", originalExtension: "txt"
        ))
    }

    func testRejectsHomePath() {
        XCTAssertThrowsError(try Sanitizer.destination(
            target: target, relativePath: "~/secret.txt", originalExtension: "txt"
        ))
    }

    func testRejectsEmptyPath() {
        XCTAssertThrowsError(try Sanitizer.destination(
            target: target, relativePath: "", originalExtension: "txt"
        ))
    }

    func testBackslashesTreatedAsSeparators() throws {
        let url = try Sanitizer.destination(
            target: target, relativePath: "A\\B\\c.txt", originalExtension: "txt"
        )
        XCTAssertEqual(url.path, "/tmp/sortomat-target/A/B/c.txt")
    }
}
