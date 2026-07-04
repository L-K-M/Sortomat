import XCTest
@testable import Sortomat

final class TextDecodingTests: XCTestCase {
    func testUTF8RoundTrip() {
        XCTAssertEqual(TextDecoding.decode(Data("héllo wörld".utf8)), "héllo wörld")
    }

    func testUTF8BOMStripped() {
        var data = Data([0xEF, 0xBB, 0xBF])
        data.append(Data("hi".utf8))
        XCTAssertEqual(TextDecoding.decode(data), "hi")
    }

    func testWindows1252Fallback() {
        // 0x93 is a lone byte that's invalid UTF-8; in CP1252 it's a left double
        // quote. Decoding must fall back rather than corrupting it.
        let data = Data([0x48, 0x65, 0x93, 0x6C, 0x6C, 0x6F]) // "He“llo"
        let text = TextDecoding.decode(data)
        XCTAssertTrue(text.contains("\u{201C}"), "got \(text)")
    }

    func testUTF16LittleEndianBOM() {
        let data = Data([0xFF, 0xFE, 0x48, 0x00, 0x69, 0x00]) // "Hi"
        XCTAssertEqual(TextDecoding.decode(data), "Hi")
    }
}
