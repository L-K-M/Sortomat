import AppKit
import XCTest
@testable import Sortomat

/// Office documents, spreadsheets, presentations and images must yield
/// classifiable text without leaving the machine.
final class TextExtractionTests: XCTestCase {
    private var dir: URL!
    private let fm = FileManager.default

    override func setUpWithError() throws {
        dir = fm.temporaryDirectory.appendingPathComponent("sortomat-extract-\(UUID().uuidString)")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? fm.removeItem(at: dir)
    }

    func testRTFIsReadThroughTheDocumentReader() throws {
        let attributed = NSAttributedString(string: "Invoice from ACME Corporation, total 42.00 CHF")
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length),
                                               documentAttributes: [:]))
        let url = dir.appendingPathComponent("invoice.rtf")
        try rtf.write(to: url)

        let text = DocumentText.text(url: url, limit: 4000)
        XCTAssertTrue(text.contains("ACME Corporation"), "got: \(text)")
        XCTAssertTrue(FileContext.describe(url: url).contains("ACME Corporation"))
    }

    func testSpreadsheetSharedStringsAreExtracted() throws {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", "<Types/>")
        zip.add("xl/sharedStrings.xml",
                #"<sst xmlns="x"><si><t>Quarterly &amp; Revenue</t></si><si><t>Zürich</t></si></sst>"#)
        let url = dir.appendingPathComponent("numbers.xlsx")
        try zip.data().write(to: url)

        let text = DocumentText.text(url: url, limit: 4000)
        XCTAssertTrue(text.contains("Quarterly & Revenue"), "got: \(text)")
        XCTAssertTrue(text.contains("Zürich"))
    }

    func testPresentationSlidesComeInDeckOrder() throws {
        var zip = ZipWriter()
        zip.add("ppt/slides/slide10.xml", "<p:sld><a:t>Tenth slide</a:t></p:sld>")
        zip.add("ppt/slides/slide2.xml", "<p:sld><a:t>Second slide</a:t></p:sld>")
        zip.add("ppt/slides/slide1.xml", "<p:sld><a:t>Opening slide</a:t></p:sld>")
        let url = dir.appendingPathComponent("deck.pptx")
        try zip.data().write(to: url)

        let text = DocumentText.text(url: url, limit: 4000)
        let first = try XCTUnwrap(text.range(of: "Opening"))
        let second = try XCTUnwrap(text.range(of: "Second"))
        let tenth = try XCTUnwrap(text.range(of: "Tenth"))
        XCTAssertTrue(first.lowerBound < second.lowerBound && second.lowerBound < tenth.lowerBound, "got: \(text)")
    }

    func testMinimalDocxFallsBackToTheZipReader() throws {
        // Too bare for AppKit's importer, but the body XML is right there.
        var zip = ZipWriter()
        zip.add("word/document.xml",
                #"<w:document><w:body><w:p><w:r><w:t>Mietvertrag Wohnung</w:t></w:r></w:p></w:body></w:document>"#)
        let url = dir.appendingPathComponent("lease.docx")
        try zip.data().write(to: url)

        XCTAssertTrue(DocumentText.text(url: url, limit: 4000).contains("Mietvertrag Wohnung"))
    }

    func testHTMLFilesYieldVisibleTextNotMarkup() throws {
        let url = dir.appendingPathComponent("page.html")
        try """
        <html><head><title>T</title><style>body { color: red }</style>
        <script>window.x = 1;</script></head>
        <body><h1>Annual report 2024</h1><p>Revenue grew.</p></body></html>
        """.write(to: url, atomically: true, encoding: .utf8)

        let description = FileContext.describe(url: url)
        XCTAssertTrue(description.contains("Annual report 2024"))
        XCTAssertFalse(description.contains("color: red"))
        XCTAssertFalse(description.contains("window.x"))
    }

    func testImageFactsAndOCR() throws {
        let png = try renderedPNG(text: "INVOICE 4711", width: 900, height: 300)
        let url = dir.appendingPathComponent("receipt.png")
        try png.write(to: url)

        let facts = ImageText.facts(imageAt: url)
        XCTAssertTrue(facts.contains { $0.0 == "Dimensions" && $0.1 == "900×300" }, "facts: \(facts)")

        let recognized = ImageText.recognize(imageAt: url)
        XCTAssertTrue(recognized.contains("4711"), "OCR produced: \(recognized)")

        let description = FileContext.describe(url: url)
        XCTAssertTrue(description.contains("recognized on-device"), "the model must know it's reading OCR")
        XCTAssertTrue(description.contains("4711"))
        XCTAssertFalse(FileContext.describe(url: url, privacyMode: .metadataOnly).contains("4711"),
                       "metadata-only rules must not read contents, OCR included")
    }

    // MARK: - Fixture rendering

    private func renderedPNG(text: String, width: Int, height: Int) throws -> Data {
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: width, height: height).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 96, weight: .bold),
            .foregroundColor: NSColor.black,
        ]
        (text as NSString).draw(at: NSPoint(x: 40, y: 90), withAttributes: attributes)
        NSGraphicsContext.restoreGraphicsState()
        return try XCTUnwrap(rep.representation(using: .png, properties: [:]))
    }
}
