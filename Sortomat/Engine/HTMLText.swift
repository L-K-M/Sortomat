import Foundation

/// Cheap, dependency-free (X)HTML → visible-text extraction. Good enough for
/// building a classification sample; not a full HTML parser.
enum HTMLText {
    /// Markup beyond this is ignored: only a few thousand characters of text
    /// ever reach the model, and a multi-megabyte chapter (or a hostile one)
    /// must not hold the scan hostage in the regexes below.
    static let maxInputCharacters = 512 * 1024

    /// An entity body (`amp`, `#x1F600`) is at most this many characters; the
    /// semicolon search is bounded to it so a chapter full of bare ampersands
    /// costs O(n), not O(n²).
    static let maxEntityLength = 12

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "auml": "ä", "ouml": "ö", "uuml": "ü", "szlig": "ß",
        "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "eacute": "é", "egrave": "è",
        "agrave": "à", "ccedil": "ç", "mdash": "—", "ndash": "–",
        "hellip": "…", "rsquo": "'", "lsquo": "'", "ldquo": "\u{201C}",
        "rdquo": "\u{201D}", "laquo": "«", "raquo": "»",
    ]

    static func strip(_ html: String) -> String {
        let bounded = html.utf8.count > maxInputCharacters
            ? String(html.prefix(maxInputCharacters))
            : html
        // (?s) — dot must match newlines, or any multi-line <style>/<script>
        // body (i.e. nearly all of them) survives into the "visible text".
        var text = bounded.replacingOccurrences(
            of: "(?s)<(script|style)[^>]*>.*?</\\1>", with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        text = text.replacingOccurrences(
            of: "<[^>]+>", with: " ", options: .regularExpression
        )
        text = decodeEntities(text)
        text = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func decodeEntities(_ input: String) -> String {
        guard input.contains("&") else { return input }
        var result = ""
        result.reserveCapacity(input.count)
        var index = input.startIndex

        while index < input.endIndex {
            let char = input[index]
            guard char == "&" else {
                result.append(char)
                index = input.index(after: index)
                continue
            }
            // Look for the closing semicolon only within the longest possible
            // entity — `input[index...].firstIndex(of:)` scanned the whole
            // remainder for every bare ampersand.
            let windowEnd = input.index(index, offsetBy: maxEntityLength + 2, limitedBy: input.endIndex)
                ?? input.endIndex
            guard let semicolon = input[index..<windowEnd].firstIndex(of: ";") else {
                result.append(char)
                index = input.index(after: index)
                continue
            }
            let body = String(input[input.index(after: index)..<semicolon])
            if let decoded = decodeEntityBody(body) {
                result.append(decoded)
                index = input.index(after: semicolon)
            } else {
                result.append(char)
                index = input.index(after: index)
            }
        }
        return result
    }

    private static func decodeEntityBody(_ body: String) -> String? {
        if body.hasPrefix("#") {
            let numeric = body.dropFirst()
            let scalarValue: UInt32?
            if numeric.hasPrefix("x") || numeric.hasPrefix("X") {
                scalarValue = UInt32(numeric.dropFirst(), radix: 16)
            } else {
                scalarValue = UInt32(numeric)
            }
            if let value = scalarValue, let scalar = Unicode.Scalar(value) {
                return String(scalar)
            }
            return nil
        }
        return namedEntities[body]
    }
}
