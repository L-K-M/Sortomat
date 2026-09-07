import AppKit
import CoreText
import PDFKit
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
        // Same normalization as above: `describe` embeds the same
        // variable-spacing OCR text, so asserting the raw form here would fail
        // on exactly the runs where the assertion above passed.
        XCTAssertTrue(description.replacingOccurrences(of: " ", with: "").contains("QX7"),
                      "OCR produced: \(description)")
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
        // `limit` is what reaches the model, so it bounds the return value —
        // a bounded *multiple* would let a regression quadruple the sample and
        // still pass, and the fixture is ASCII, so the byte cut alone lands on
        // exactly 2 000 characters.
        XCTAssertLessThanOrEqual(text.count, 500,
                                 "the limit has to bound what reaches the model")
    }

    func testTheLimitBoundsTheDocumentReaderPathToo() throws {
        // The zip readers trim on the way out; the AppKit reader hands back
        // four bytes per allowed character and used to be returned untouched.
        let attributed = NSAttributedString(string: String(repeating: "lorem ipsum ", count: 2000))
        let rtf = try XCTUnwrap(attributed.rtf(from: NSRange(location: 0, length: attributed.length),
                                               documentAttributes: [:]))
        let url = dir.appendingPathComponent("long.rtf")
        try rtf.write(to: url)

        XCTAssertLessThanOrEqual(DocumentText.text(url: url, limit: 500).count, 500)
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
        let partialText = DocumentText.text(url: partial, limit: 4000)   // must not trap
        // Pinned, not merely survived: a lenient parser that started returning
        // raw tag fragments would otherwise slip through unnoticed.
        XCTAssertTrue(partialText.isEmpty || partialText.contains("unclosed"),
                      "unexpected extraction result: \(partialText)")
    }

    func testBundleSizeCapAddsUpWhatIsInsideTheBundle() throws {
        // An .rtfd is a directory, and no resource key reports what a directory
        // holds — the cap was measuring the folder entry, so it never applied
        // to the one format in the list that is a bundle.
        let bundle = dir.appendingPathComponent("Note.rtfd")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        try Data(count: 300_000).write(to: bundle.appendingPathComponent("TXT.rtf"))
        try Data(count: 200_000).write(to: bundle.appendingPathComponent("image.tiff"))

        let reported = (try? bundle.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?
            .totalFileAllocatedSize ?? 0
        XCTAssertLessThan(reported, 100_000, "the resource key is not recursive")
        XCTAssertGreaterThanOrEqual(DocumentText.bundleSize(of: bundle), 500_000)
    }

    func testBundleSizeStopsCountingOnceTheCeilingIsPassed() throws {
        let bundle = dir.appendingPathComponent("Big.rtfd")
        try fm.createDirectory(at: bundle, withIntermediateDirectories: true)
        for index in 0..<5 {
            try Data(count: 100_000).write(to: bundle.appendingPathComponent("part\(index).bin"))
        }
        let capped = DocumentText.bundleSize(of: bundle, stoppingAbove: 150_000)
        XCTAssertGreaterThan(capped, 150_000)
        // Under the bundle's real 500 KB: "over the ceiling" is also what an
        // implementation that ignored the ceiling and walked everything would
        // report, so the upper bound is what actually pins the early exit.
        XCTAssertLessThan(capped, 500_000, "counting has to stop once the ceiling is passed")
    }

    func testInlineStringWorkbooksAreNotEmpty() throws {
        // Plenty of exporters skip the shared table and write every string
        // inline, which left the sample completely empty.
        var zip = ZipWriter()
        zip.add("xl/worksheets/sheet1.xml",
                #"<worksheet><sheetData><row><c t="inlineStr"><is><t>Rechnung Nr. 4711</t></is></c>"# +
                #"<c><v>1234.5</v></c></row></sheetData></worksheet>"#)
        let url = dir.appendingPathComponent("inline.xlsx")
        try zip.data().write(to: url, options: .atomic)

        let text = DocumentText.text(url: url, limit: 4000)
        XCTAssertTrue(text.contains("Rechnung Nr. 4711"), "got: \(text)")
        // The other cell values are shared-string indices and date serials;
        // handing the model a stream of integers would be worse than nothing.
        XCTAssertFalse(text.contains("1234.5"), "got: \(text)")
    }

    func testDocumentPropertiesDoNotMaskTheInlineStringFallback() throws {
        // Almost every generator writes a creator into docProps/core.xml —
        // openpyxl included. Reading it in the same pass as the shared-string
        // table made that boilerplate count as "the table had text", so for
        // exactly the workbooks the fallback exists for the model got a tool
        // name and not one cell of the sheet.
        var zip = ZipWriter()
        zip.add("docProps/core.xml",
                #"<cp:coreProperties><dc:creator>openpyxl</dc:creator></cp:coreProperties>"#)
        zip.add("xl/worksheets/sheet1.xml",
                #"<worksheet><sheetData><row><c t="inlineStr"><is><t>Rechnung Nr. 4711</t></is></c></row></sheetData></worksheet>"#)
        let url = dir.appendingPathComponent("properties.xlsx")
        try zip.data().write(to: url, options: .atomic)

        let text = DocumentText.text(url: url, limit: 4000)
        XCTAssertTrue(text.contains("Rechnung Nr. 4711"), "got: \(text)")
    }

    func testSymlinkedFilesAreMeasuredByWhatTheyPointAt() throws {
        // `attributesOfItem` describes the link; every reader below the cap —
        // `NSAttributedString(url:)`, `ZipArchive`, `CGImageSourceCreateWithURL`
        // — follows it. A symlink to something enormous weighed a few bytes and
        // sailed through the cap that exists to stop exactly that read.
        //
        // Asserted against the gates themselves, not against `FileManager`:
        // measuring with Foundation here would pin Foundation's semantics,
        // which are true on every machine whatever this reader does, and the
        // regression would come back green.
        let small = dir.appendingPathComponent("small.rtf")
        try Data(count: 4096).write(to: small)
        let smallLink = dir.appendingPathComponent("small-link.rtf")
        try fm.createSymbolicLink(at: smallLink, withDestinationURL: small)
        XCTAssertTrue(DocumentText.sizeAllows(smallLink),
                      "a link to a small file must still be read")

        // Sparse: `truncate` sets the length without writing 64 MB, and the
        // length is what both caps read.
        let huge = dir.appendingPathComponent("huge.rtf")
        XCTAssertTrue(fm.createFile(atPath: huge.path, contents: nil))
        let handle = try FileHandle(forWritingTo: huge)
        try handle.truncate(atOffset: UInt64(DocumentText.maxDocumentBytes) + 1)
        try handle.close()
        let hugeLink = dir.appendingPathComponent("huge-link.rtf")
        try fm.createSymbolicLink(at: hugeLink, withDestinationURL: huge)

        XCTAssertFalse(DocumentText.sizeAllows(hugeLink),
                       "the cap must weigh the bytes the reader will actually read")
        XCTAssertFalse(ImageText.sizeAllows(hugeLink),
                       "the image cap had the same bug and needs the same guarantee")
        XCTAssertLessThan(
            (try? fm.attributesOfItem(atPath: hugeLink.path))?[.size] as? Int64 ?? 0, 4096,
            "sanity: the link itself weighs its target's path, which is why this is a bug at all"
        )
    }

    func testMacroAndTemplateTwinsAreReadLikeTheirSiblings() throws {
        // Same OPC package, same body part, different extension. Dropping them
        // cost the entire sample for a file the reader can already read.
        var workbook = ZipWriter()
        workbook.add("xl/sharedStrings.xml", "<sst><si><t>Vorlage Umsatz</t></si></sst>")
        let template = dir.appendingPathComponent("budget.xltx")
        try workbook.data().write(to: template, options: .atomic)
        XCTAssertTrue(DocumentText.text(url: template, limit: 4000).contains("Vorlage Umsatz"))

        var deck = ZipWriter()
        deck.add("ppt/slides/slide1.xml", "<p:sld><a:t>Quartalsbericht</a:t></p:sld>")
        let show = dir.appendingPathComponent("review.ppsx")
        try deck.data().write(to: show, options: .atomic)
        XCTAssertTrue(DocumentText.text(url: show, limit: 4000).contains("Quartalsbericht"))

        var document = ZipWriter()
        document.add("word/document.xml", "<w:document><w:t>Makro Rechnung</w:t></w:document>")
        let macro = dir.appendingPathComponent("invoice.docm")
        try document.data().write(to: macro, options: .atomic)
        XCTAssertTrue(DocumentText.text(url: macro, limit: 4000).contains("Makro Rechnung"))
    }

    func testSharedStringsStillWinWhenBothArePresent() throws {
        var zip = ZipWriter()
        zip.add("xl/sharedStrings.xml", "<sst><si><t>Umsatz Q3</t></si></sst>")
        zip.add("xl/worksheets/sheet1.xml", "<worksheet><sheetData><row><c><v>0</v></c></row></sheetData></worksheet>")
        let url = dir.appendingPathComponent("both.xlsx")
        try zip.data().write(to: url, options: .atomic)

        let text = DocumentText.text(url: url, limit: 4000)
        XCTAssertTrue(text.contains("Umsatz Q3"), "got: \(text)")
        // No standalone number: a bare "0" is a leaked shared-string index,
        // while the "3" in "Q3" is part of a word. `contains("0")` would fail
        // on any year the reader might legitimately emit one day.
        XCTAssertNil(text.range(of: #"(?<![A-Za-z])\d+"#, options: .regularExpression),
                     "numeric cell values must not leak, got: \(text)")
    }

    func testACommaInAURLPathIsNotAnOriginBoundary() {
        // Spotlight joins several origins with ", "; a comma inside one path is
        // not a separator, and cutting there turned one origin into two wrong
        // ones.
        XCTAssertEqual(
            FileContext.withoutQuery("https://example.com/docs/a,b.pdf"),
            "https://example.com/docs/a,b.pdf"
        )
        XCTAssertEqual(
            FileContext.withoutQuery("https://a.example/x,y.pdf?t=1, https://b.example/z.pdf"),
            "https://a.example/x,y.pdf, https://b.example/z.pdf"
        )
    }

    func testSpreadsheetsAndDrawingsSkipTheDocumentReader() throws {
        // An OpenDocument file is a zip; a reader that guesses "plain text"
        // returns its compressed bytes as mojibake, and that non-empty answer
        // would win over the content.xml path and be the only sample the file
        // ever produced.
        var zip = ZipWriter()
        zip.add("content.xml",
                #"<office:document-content><office:body><office:spreadsheet><text:p>Quartalszahlen</text:p></office:spreadsheet></office:body></office:document-content>"#)
        for (name, ext) in [("sheet", "ods"), ("deck", "odp"), ("plan", "odg")] {
            let url = dir.appendingPathComponent("\(name).\(ext)")
            try zip.data().write(to: url, options: .atomic)
            let text = DocumentText.text(url: url, limit: 4000)
            XCTAssertTrue(text.contains("Quartalszahlen"), "\(ext) got: \(text)")
        }
    }

    func testDownloadURLsReachTheModelWithoutTheirQueryString() {
        XCTAssertEqual(
            FileContext.withoutQuery("https://files.example.com/report.pdf?token=SECRET&sig=abc"),
            "https://files.example.com/report.pdf"
        )
        XCTAssertEqual(
            FileContext.withoutQuery("https://a.example/x.pdf?t=1, https://b.example/y.pdf#frag"),
            "https://a.example/x.pdf, https://b.example/y.pdf"
        )
        XCTAssertEqual(FileContext.withoutQuery(""), "")
        XCTAssertEqual(FileContext.withoutQuery("https://plain.example/a.pdf"),
                       "https://plain.example/a.pdf")
    }

    func testAScannerWatermarkDoesNotCountAsATextLayer() throws {
        // Scanner apps stamp a line of their own onto an image-only page. The
        // page's real content is reachable only by recognizing it, but a
        // non-empty text layer used to be taken as the whole sample.
        let png = try renderedPNG(text: "INVOICE QX7 4711", width: 900, height: 300)
        let url = dir.appendingPathComponent("scan.pdf")
        try scannedPDF(imagePNG: png, watermark: "Scanned by TestScanner").write(to: url)

        let sample = FileContext.extractSample(url: url)
        XCTAssertEqual(sample.source, .recognized, "got \(sample.source): \(sample.text)")
        XCTAssertTrue(sample.text.replacingOccurrences(of: " ", with: "").contains("QX7"),
                      "OCR produced: \(sample.text)")
    }

    func testARealTextLayerIsUsedWithoutRecognition() throws {
        let body = String(repeating: "Mietvertrag Wohnung Zuerich ", count: 8)
        let url = dir.appendingPathComponent("lease.pdf")
        try scannedPDF(imagePNG: nil, watermark: body).write(to: url)

        let sample = FileContext.extractSample(url: url)
        XCTAssertEqual(sample.source, .text, "got \(sample.source): \(sample.text)")
        XCTAssertTrue(sample.text.contains("Mietvertrag"), "got: \(sample.text)")
    }

    // MARK: - Fixture rendering

    /// A one-page PDF holding an optional image and a line of real text — the
    /// shape a scanner app produces: pixels plus a watermark.
    private func scannedPDF(imagePNG: Data?, watermark: String) throws -> Data {
        let data = NSMutableData()
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        var box = CGRect(x: 0, y: 0, width: 612, height: 792)
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        if let imagePNG {
            let source = try XCTUnwrap(CGImageSourceCreateWithData(imagePNG as CFData, nil))
            let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source, 0, nil))
            context.draw(image, in: CGRect(x: 30, y: 300, width: 552, height: 184))
        }
        // Wrapped by hand: one very long CTLine would run off the media box,
        // and glyphs drawn past the page edge are not reliably extracted back.
        var remaining = Substring(watermark)
        var baseline: CGFloat = 240
        while !remaining.isEmpty, baseline > 20 {
            let chunk = remaining.prefix(46)
            remaining = remaining.dropFirst(chunk.count)
            let attributed = NSAttributedString(
                string: String(chunk), attributes: [.font: NSFont.systemFont(ofSize: 12)]
            )
            context.textPosition = CGPoint(x: 40, y: baseline)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
            baseline -= 16
        }
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }


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
