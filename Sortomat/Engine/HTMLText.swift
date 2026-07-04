import Foundation

/// Cheap, dependency-free (X)HTML → visible-text extraction. Good enough for
/// building a classification sample; not a full HTML parser.
enum HTMLText {
    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'",
        "nbsp": " ", "auml": "ä", "ouml": "ö", "uuml": "ü", "szlig": "ß",
        "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "eacute": "é", "egrave": "è",
        "agrave": "à", "ccedil": "ç", "mdash": "—", "ndash": "–",
        "hellip": "…", "rsquo": "'", "lsquo": "'", "ldquo": "\u{201C}",
        "rdquo": "\u{201D}", "laquo": "«", "raquo": "»",
    ]

    static func strip(_ html: String) -> String {
        var text = html.replacingOccurrences(
            of: "<(script|style)[^>]*>.*?</\\1>", with: " ",
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
            guard char == "&",
                  let semicolon = input[index...].firstIndex(of: ";"),
                  input.distance(from: index, to: semicolon) <= 12
            else {
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
