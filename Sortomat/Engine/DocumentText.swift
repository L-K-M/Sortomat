import AppKit
import Foundation

/// Text out of office documents without any network or third-party code:
/// Word/RTF/OpenDocument through AppKit's attributed-string reader, and
/// spreadsheets/presentations (which are zips of XML) through the in-process
/// zip reader. Previously every one of these reached the model as name +
/// metadata only, so "file this invoice" had nothing to go on.
enum DocumentText {
    /// Documents larger than this aren't parsed — the reader would load them
    /// whole, and a classification sample is a few thousand characters.
    static let maxDocumentBytes: Int64 = 64 * 1024 * 1024

    /// Extensions `text(url:)` knows how to read.
    static let richTextExtensions: Set<String> = ["rtf", "rtfd", "doc", "docx", "odt"]
    static let spreadsheetExtensions: Set<String> = ["xlsx"]
    static let presentationExtensions: Set<String> = ["pptx"]

    static func text(url: URL, limit: Int) -> String {
        let ext = url.pathExtension.lowercased()
        if spreadsheetExtensions.contains(ext) { return spreadsheetText(url: url, limit: limit) }
        if presentationExtensions.contains(ext) { return presentationText(url: url, limit: limit) }
        guard richTextExtensions.contains(ext) else { return "" }
        if let text = attributedStringText(url: url, limit: limit), !text.isEmpty { return text }
        // A .docx AppKit can't read (or one it rejects) still has its body
        // in word/document.xml.
        if ext == "docx" { return zipXMLText(url: url, entries: ["word/document.xml"], limit: limit) }
        return ""
    }

    // MARK: - AppKit document reader

    private static func attributedStringText(url: URL, limit: Int) -> String? {
        guard sizeAllows(url) else { return nil }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch url.pathExtension.lowercased() {
        case "docx": options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": options[.documentType] = NSAttributedString.DocumentType.docFormat
        case "rtf": options[.documentType] = NSAttributedString.DocumentType.rtf
        case "rtfd": options[.documentType] = NSAttributedString.DocumentType.rtfd
        default: break // OpenDocument: let the reader sniff it
        }
        guard let attributed = try? NSAttributedString(url: url, options: options, documentAttributes: nil) else {
            return nil
        }
        return String(attributed.string.prefix(limit * 4))
    }

    // MARK: - Zip-of-XML formats

    /// Excel keeps every distinct cell string in one shared table — exactly
    /// the vocabulary a classifier needs (headers, names, subjects).
    private static func spreadsheetText(url: URL, limit: Int) -> String {
        zipXMLText(url: url, entries: ["xl/sharedStrings.xml", "docProps/core.xml"], limit: limit)
    }

    /// Slides in deck order (slide1, slide2, …, not the lexical slide10-first).
    private static func presentationText(url: URL, limit: Int) -> String {
        guard sizeAllows(url), let zip = ZipArchive(url: url) else { return "" }
        let slides = zip.entries
            .filter { $0.name.hasPrefix("ppt/slides/slide") && $0.name.hasSuffix(".xml") }
            .sorted { slideNumber($0.name) < slideNumber($1.name) }
        return collect(from: slides, in: zip, limit: limit)
    }

    private static func slideNumber(_ name: String) -> Int {
        let digits = name.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits) ?? Int.max
    }

    private static func zipXMLText(url: URL, entries names: [String], limit: Int) -> String {
        guard sizeAllows(url), let zip = ZipArchive(url: url) else { return "" }
        let entries = names.compactMap { zip.entry(named: $0) }
        return collect(from: entries, in: zip, limit: limit)
    }

    private static func collect(from entries: [ZipArchive.Entry], in zip: ZipArchive, limit: Int) -> String {
        var pieces: [String] = []
        var collected = 0
        for entry in entries {
            guard let data = zip.data(for: entry) else { continue }
            // Tags become spaces, so adjacent cells/runs don't glue together;
            // XML entities decode the same way HTML ones do.
            let markup = String(TextDecoding.decode(data).prefix(HTMLText.maxInputCharacters))
            let text = HTMLText.strip(markup)
            guard !text.isEmpty else { continue }
            pieces.append(text)
            collected += text.count
            if collected >= limit { break }
        }
        return String(pieces.joined(separator: " ").prefix(limit))
    }

    private static func sizeAllows(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? 0
        return size <= maxDocumentBytes
    }
}
