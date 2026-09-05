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
        let png = try renderedPNG(text: "INVOICE QX7 4711", width: 900, height: 300)
        let url = dir.appendingPathComponent("receipt.png")
        try png.write(to: url)

        let facts = ImageText.facts(imageAt: url)
        XCTAssertTrue(facts.contains { $0.0 == "Dimensions" && $0.1 == "900×300" }, "facts: \(facts)")

        let recognized = ImageText.recognize(imageAt: url)
        // Vision sometimes breaks a short token as "Q X7"; the question is
        // whether it read the glyphs, not how it spaced them.
        let normalized = recognized.replacingOccurrences(of: " ", with: "")
        XCTAssertTrue(normalized.contains("QX7"), "OCR produced: \(recognized)")

        let description = FileContext.describe(url: url)
        XCTAssertTrue(description.contains(FileContext.ocrNotice),
                      "the model must know it's reading OCR")
        XCTAssertTrue(description.contains("QX7"))
        // A token no metadata field can contain by accident: a bare number
        // would match a byte count like "14711 bytes" and fail for nothing.
        XCTAssertFalse(FileContext.describe(url: url, privacyMode: .metadataOnly).contains("QX7"),
                       "metadata-only rules must not read contents, OCR included")
    }

    func testOpenDocumentBodyIsRead() throws {
        // Whether AppKit's reader handles OpenDocument varies; the zip path
        // makes the answer the same either way.
        var zip = ZipWriter()
        zip.add("content.xml",
                #"<office:document-content><office:body><office:text><text:p>Kündigung Mietvertrag</text:p></office:text></office:body></office:document-content>"#)
        let url = dir.appendingPathComponent("letter.odt")
        try zip.data().write(to: url, options: .atomic)

        XCTAssertTrue(DocumentText.text(url: url, limit: 4000).contains("Kündigung Mietvertrag"))
    }

    func testMacroWorkbooksReadLikeOrdinaryOnes() throws {
        var zip = ZipWriter()
        zip.add("xl/sharedStrings.xml", "<sst><si><t>Umsatz Q3</t></si></sst>")
        let url = dir.appendingPathComponent("budget.xlsm")
        try zip.data().write(to: url, options: .atomic)

        XCTAssertTrue(DocumentText.text(url: url, limit: 4000).contains("Umsatz Q3"))
    }

    func testExtractionRespectsTheLimit() throws {
        var zip = ZipWriter()
        zip.add("word/document.xml",
                "<w:document><w:t>" + String(repeating: "lorem ipsum ", count: 2000) + "</w:t></w:document>")
        let url = dir.appendingPathComponent("long.docx")
        try zip.data().write(to: url, options: .atomic)

        let text = DocumentText.text(url: url, limit: 500)
        XCTAssertFalse(text.isEmpty)
        // `limit` bounds what the *classifier* is given, and the readers cut
        // at four bytes per allowed character before the caller trims again —
        // so the guarantee is a bounded multiple, not an exact count.
        XCTAssertLessThanOrEqual(text.count, 500 * 4,
                                 "the limit has to bound what reaches the model")
    }

    func testMalformedOfficeFilesReturnNothingRatherThanTrapping() throws {
        // The zip fallback is where a force-unwrap would hide, and these are
        // the inputs a real Downloads folder produces.
        let notAZip = dir.appendingPathComponent("broken.docx")
        try Data("definitely not a zip".utf8).write(to: notAZip, options: .atomic)
        XCTAssertEqual(DocumentText.text(url: notAZip, limit: 4000), "")

        let empty = dir.appendingPathComponent("empty.xlsx")
        try Data().write(to: empty, options: .atomic)
        XCTAssertEqual(DocumentText.text(url: empty, limit: 4000), "")

        var truncated = ZipWriter()
        truncated.add("content.xml", "<office:text><text:p>unclosed")
        let partial = dir.appendingPathComponent("partial.odt")
        try truncated.data().write(to: partial, options: .atomic)
        _ = DocumentText.text(url: partial, limit: 4000)   // must not trap
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
