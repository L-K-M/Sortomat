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

    // MARK: - Partial-tail trimming (fixed-size reads splitting characters)

    func testTrimsSplitTwoByteCharacter() {
        var data = Data("abcé".utf8) // é = 0xC3 0xA9
        data.removeLast()            // cut mid-character
        let trimmed = TextDecoding.trimmingPartialUTF8Tail(data)
        XCTAssertEqual(TextDecoding.decode(trimmed), "abc")
    }

    func testTrimsSplitThreeByteCharacter() {
        var data = Data("ab€".utf8)  // € = 0xE2 0x82 0xAC
        data.removeLast()
        XCTAssertEqual(TextDecoding.decode(TextDecoding.trimmingPartialUTF8Tail(data)), "ab")
    }

    func testTrimsSplitFourByteCharacter() {
        var data = Data("ab😀".utf8) // 4-byte scalar
        data.removeLast(2)
        XCTAssertEqual(TextDecoding.decode(TextDecoding.trimmingPartialUTF8Tail(data)), "ab")
    }

    func testCompleteTailIsUntouched() {
        let data = Data("héllo".utf8)
        XCTAssertEqual(TextDecoding.trimmingPartialUTF8Tail(data), data)
    }

    func testAsciiAndEmptyAreUntouched() {
        let ascii = Data("plain".utf8)
        XCTAssertEqual(TextDecoding.trimmingPartialUTF8Tail(ascii), ascii)
        XCTAssertEqual(TextDecoding.trimmingPartialUTF8Tail(Data()), Data())
    }

    func testNonUTF8DataPassesThrough() {
        // CP1252 text whose final byte looks nothing like a UTF-8 lead.
        let data = Data([0x48, 0x65, 0x93, 0x6C, 0x6C]) // He“ll
        XCTAssertEqual(TextDecoding.trimmingPartialUTF8Tail(data), data)
    }

    func testSplitCharacterNoLongerPoisonsWholeExcerpt() {
        // The actual bug: one split character made strict UTF-8 fail for the
        // whole buffer and everything decoded as CP1252 mojibake.
        var data = Data("Über die Wälder zög".utf8)
        data.removeLast(2) // drop the trailing "g" plus one byte of "ö" → split
        let decoded = TextDecoding.decode(TextDecoding.trimmingPartialUTF8Tail(data))
        XCTAssertTrue(decoded.hasPrefix("Über die Wälder"), "got \(decoded)")
        XCTAssertFalse(decoded.contains("Ã"), "mojibake leaked through: \(decoded)")
    }
}
