import XCTest
@testable import Sortomat

final class EpubReaderTests: XCTestCase {
    private var url: URL!
    private let fm = FileManager.default

    override func tearDownWithError() throws {
        if let url { try? fm.removeItem(at: url) }
    }

    private func writeEpub(container: String, opf: String, chapter: String,
                           chapterName: String = "OEBPS/chapter1.xhtml") throws -> URL {
        var zip = ZipWriter()
        zip.add("mimetype", "application/epub+zip")
        zip.add("META-INF/container.xml", container)
        zip.add("OEBPS/content.opf", opf)
        zip.add(chapterName, chapter)
        let out = fm.temporaryDirectory.appendingPathComponent("book-\(UUID().uuidString).epub")
        try zip.data().write(to: out)
        return out
    }

    private let container = """
    <?xml version="1.0"?>
    <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
      <rootfiles>
        <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
      </rootfiles>
    </container>
    """

    private func opf(title: String, creator: String) -> String {
        """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
            <dc:title>\(title)</dc:title>
            <dc:creator>\(creator)</dc:creator>
            <dc:subject>Fantasy</dc:subject>
            <dc:language>en</dc:language>
          </metadata>
          <manifest>
            <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine>
            <itemref idref="c1"/>
          </spine>
        </package>
        """
    }

    func testParsesMetadataAndSample() throws {
        let chapterText = String(repeating: "In a hole in the ground there lived a hobbit. ", count: 10)
        let chapter = "<html><body><h1>Chapter One</h1><p>\(chapterText)</p></body></html>"
        url = try writeEpub(container: container, opf: opf(title: "The Hobbit", creator: "Tolkien"), chapter: chapter)

        let reader = try XCTUnwrap(EpubReader(url: url))
        XCTAssertEqual(reader.metadata.title, "The Hobbit")
        XCTAssertTrue(reader.metadata.creators.contains("Tolkien"))
        XCTAssertTrue(reader.metadata.subjects.contains("Fantasy"))
        XCTAssertTrue(reader.sample.contains("hobbit"))
    }

    func testFallsBackToShallowestOpfWithoutContainer() throws {
        // No container.xml entry — the reader must find the .opf by scanning.
        var zip = ZipWriter()
        zip.add("OEBPS/content.opf", opf(title: "Orphan", creator: "Nobody"))
        let chapterText = String(repeating: "Some real content here to exceed the minimum length. ", count: 6)
        zip.add("OEBPS/chapter1.xhtml", "<html><body><p>\(chapterText)</p></body></html>")
        url = fm.temporaryDirectory.appendingPathComponent("book-\(UUID().uuidString).epub")
        try zip.data().write(to: url)

        let reader = try XCTUnwrap(EpubReader(url: url))
        XCTAssertEqual(reader.metadata.title, "Orphan")
    }

    func testSkipsTinyCoverPages() throws {
        // A short first document (< 200 chars) is skipped in favor of real content.
        var zip = ZipWriter()
        zip.add("META-INF/container.xml", container)
        let opfTwo = """
        <?xml version="1.0"?>
        <package xmlns="http://www.idpf.org/2007/opf" version="3.0">
          <metadata xmlns:dc="http://purl.org/dc/elements/1.1/"><dc:title>T</dc:title></metadata>
          <manifest>
            <item id="cover" href="cover.xhtml" media-type="application/xhtml+xml"/>
            <item id="c1" href="chapter1.xhtml" media-type="application/xhtml+xml"/>
          </manifest>
          <spine><itemref idref="cover"/><itemref idref="c1"/></spine>
        </package>
        """
        zip.add("OEBPS/content.opf", opfTwo)
        zip.add("OEBPS/cover.xhtml", "<html><body><p>Cover</p></body></html>")
        let body = String(repeating: "The real story begins here and continues at length. ", count: 6)
        zip.add("OEBPS/chapter1.xhtml", "<html><body><p>\(body)</p></body></html>")
        url = fm.temporaryDirectory.appendingPathComponent("book-\(UUID().uuidString).epub")
        try zip.data().write(to: url)

        let reader = try XCTUnwrap(EpubReader(url: url))
        XCTAssertTrue(reader.sample.contains("real story"))
        XCTAssertFalse(reader.sample.hasPrefix("Cover"))
    }
}
