import Foundation

/// Best-effort text decoding for content that isn't guaranteed UTF-8 (EPUB
/// chapters, stray .txt files). Ports the Python script's codec handling: honor
/// a BOM, then a declared encoding, then UTF-8, then Windows-1252 (what most
/// "ISO-8859-1"-declared files really are), and finally Latin-1 which never fails.
enum TextDecoding {
    private static let latin1Aliases: Set<String> = [
        "iso-8859-1", "iso8859-1", "iso_8859-1", "8859-1", "latin-1", "latin1",
        "l1", "cp819", "ascii", "us-ascii",
    ]

    static func decode(_ data: Data, declared: String? = nil) -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        // `.utf16` reads the BOM to pick endianness and strips it (unlike the
        // fixed-endian variants, which would leave a U+FEFF at the start).
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            return String(data: data, encoding: .utf16) ?? fallback(data)
        }

        var candidates: [String.Encoding] = []
        if let declared, let enc = encoding(for: declared) { candidates.append(enc) }
        candidates.append(contentsOf: [.utf8, .windowsCP1252])
        for encoding in candidates {
            if let s = String(data: data, encoding: encoding) { return s }
        }
        return fallback(data)
    }

    private static func encoding(for name: String) -> String.Encoding? {
        let lower = name.lowercased()
        if latin1Aliases.contains(lower) { return .windowsCP1252 }
        switch lower {
        case "utf-8", "utf8": return .utf8
        case "utf-16", "utf16": return .utf16
        case "windows-1252", "cp1252": return .windowsCP1252
        default: return nil
        }
    }

    private static func fallback(_ data: Data) -> String {
        String(data: data, encoding: .isoLatin1) ?? String(decoding: data, as: UTF8.self)
    }
}
