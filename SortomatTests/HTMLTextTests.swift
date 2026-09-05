import XCTest
@testable import Sortomat

final class HTMLTextTests: XCTestCase {
    func testStripsTags() {
        XCTAssertEqual(HTMLText.strip("<p>Hello <b>world</b></p>"), "Hello world")
    }

    func testDropsScriptAndStyle() {
        XCTAssertEqual(HTMLText.strip("<style>x{}</style><p>Text</p><script>y()</script>"), "Text")
    }

    func testDropsMultilineScriptAndStyle() {
        // Real-world style/script blocks span lines; without dotall matching
        // their bodies leaked into the "visible text" sent to the model.
        let html = """
        <html><head><style type="text/css">
        body { margin: 0; }
        p { font-family: serif; }
        </style></head>
        <body><p>Chapter One</p>
        <script>
        function f() { return 42; }
        </script></body></html>
        """
        XCTAssertEqual(HTMLText.strip(html), "Chapter One")
    }

    func testDecodesNamedEntities() {
        XCTAssertEqual(HTMLText.decodeEntities("a &amp; b &lt; c &gt; d"), "a & b < c > d")
    }

    func testDecodesNumericEntities() {
        XCTAssertEqual(HTMLText.decodeEntities("&#65;&#x42;C"), "ABC")
    }

    func testLeavesBareAmpersandAlone() {
        XCTAssertEqual(HTMLText.decodeEntities("Tom & Jerry"), "Tom & Jerry")
    }

    func testCollapsesWhitespace() {
        XCTAssertEqual(HTMLText.strip("<p>a\n\n   b\t c</p>"), "a b c")
    }


    func testBareAmpersandsCostLinearTime() {
        // Every `&` used to scan the whole remainder for a `;` — a chapter of
        // ampersands with no semicolons was quadratic and stalled the scan.
        let input = String(repeating: "&", count: 50_000) + " end"
        XCTAssertEqual(HTMLText.decodeEntities(input), input)
    }

    func testDistantSemicolonDoesNotMakeAnEntity() {
        XCTAssertEqual(HTMLText.decodeEntities("Tom & Jerry; friends"), "Tom & Jerry; friends")
        XCTAssertEqual(HTMLText.decodeEntities("&amp; and &unknownentity; stay"), "& and &unknownentity; stay")
    }

    func testStripBoundsHugeInput() {
        let html = "<p>" + String(repeating: "x", count: HTMLText.maxInputCharacters + 5_000) + "</p>"
        XCTAssertLessThanOrEqual(HTMLText.strip(html).count, HTMLText.maxInputCharacters)
    }
}
