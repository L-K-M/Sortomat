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
        // The fallback follows the UI language (English "Unknown" on the CI
        // runner, German "Unbekannt" on a German system).
        let unknown = L10n.t("component.unknown")
        XCTAssertEqual(Sanitizer.sanitizeComponent("   ...  "), unknown)
        XCTAssertEqual(Sanitizer.sanitizeComponent(".."), unknown)
    }

    func testTruncatesToMaxLength() {
        let long = String(repeating: "x", count: 400)
        XCTAssertEqual(Sanitizer.sanitizeComponent(long, maxLength: 10).count, 10)
    }

    // MARK: - Destination building & path safety

    func testBuildsNestedDestination() throws {
        let url = try Sanitizer.destination(
            target: target, relativePath: "Fantasy/Tolkien, John/Hobbit.epub",
            originalExtension: "epub"
        )
        XCTAssertEqual(url.path, "/tmp/sortomat-target/Fantasy/Tolkien, John/Hobbit.epub")
    }

    func testTrailingDotInComponentIsStripped() {
        // Trailing dots are unsafe on macOS/Windows and are removed.
        XCTAssertEqual(Sanitizer.sanitizeComponent("Tolkien, J.R.R."), "Tolkien, J.R.R")
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


    // MARK: - Invisible characters, dot segments, extension forcing

    func testStripsInvisibleAndBidiCharacters() {
        XCTAssertEqual(Sanitizer.sanitizeComponent("Fantasy\u{200B}"), "Fantasy")
        XCTAssertEqual(Sanitizer.sanitizeComponent("\u{202E}evil"), "evil")
        XCTAssertEqual(Sanitizer.sanitizeComponent("a\u{7F}b"), "a b")
        XCTAssertEqual(Sanitizer.sanitizeComponent("\u{FEFF}Krimi"), "Krimi")
    }

    func testDotSegmentsAreDropped() throws {
        let url = try Sanitizer.destination(
            target: target, relativePath: "./Docs/./report.pdf", originalExtension: "pdf"
        )
        XCTAssertEqual(url.path, "/tmp/sortomat-target/Docs/report.pdf")
    }

    func testDottedStemsKeepTheirSegments() {
        XCTAssertEqual(Sanitizer.forcingExtension("png", on: "Screenshot 2024-06-01 at 10.15.32"),
                       "Screenshot 2024-06-01 at 10.15.32.png")
        XCTAssertEqual(Sanitizer.forcingExtension("tar", on: "backup.2024.01.tar"), "backup.2024.01.tar")
        XCTAssertEqual(Sanitizer.forcingExtension("epub", on: "Tolkien, J.R.R"), "Tolkien, J.R.R.epub")
        XCTAssertEqual(Sanitizer.forcingExtension("pdf", on: "v1.2"), "v1.2.pdf")
    }

    func testRecognizedWrongExtensionIsReplaced() {
        XCTAssertEqual(Sanitizer.forcingExtension("pdf", on: "report.txt"), "report.pdf")
        XCTAssertEqual(Sanitizer.forcingExtension("epub", on: "Hobbit.mobi"), "Hobbit.epub")
        XCTAssertEqual(Sanitizer.forcingExtension("pdf", on: "Report.PDF"), "Report.PDF")
    }
}
