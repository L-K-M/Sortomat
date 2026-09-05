import CoreServices
import Foundation
import PDFKit

/// Builds the textual description of a file handed to the model: name, dates,
/// Spotlight metadata and — unless the rule is metadata-only — a content excerpt.
enum FileContext {
    static let sampleLimit = 4000

    private static let plainTextExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "yml", "yaml",
        "log", "tex", "srt",
    ]
    private static let markupExtensions: Set<String> = ["html", "htm", "xhtml"]

    /// What `extractSample` produced, so the description can say where the
    /// excerpt came from — a model should know it is reading OCR output.
    enum SampleSource {
        case none
        case text
        case recognized   // on-device OCR of an image or a scanned PDF
    }

    static func describe(url: URL, privacyMode: PrivacyMode = .full) -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? Int64) ?? 0
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines = ["File:", "Name: \(url.lastPathComponent)"]
        lines.append("Folder: \(url.deletingLastPathComponent().lastPathComponent)")
        lines.append("Size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
        if let created = attrs[.creationDate] as? Date {
            lines.append("Created: \(formatter.string(from: created))")
        }
        if let modified = attrs[.modificationDate] as? Date {
            lines.append("Modified: \(formatter.string(from: modified))")
        }

        let spotlight = spotlightMetadata(url: url)
        for (label, value) in spotlight.fields where !value.isEmpty {
            lines.append("\(label): \(value)")
        }
        let ext = url.pathExtension.lowercased()
        if ImageText.imageExtensions.contains(ext) {
            for (label, value) in ImageText.facts(imageAt: url) {
                lines.append("\(label): \(value)")
            }
        }

        guard privacyMode == .full else {
            lines.append("")
            lines.append("(Metadata-only rule: file contents were not read.)")
            return lines.joined(separator: "\n")
        }

        var sample = spotlight.textContent
        var source: SampleSource = sample.isEmpty ? .none : .text
        if sample.isEmpty {
            let extracted = extractSample(url: url)
            sample = extracted.text
            source = extracted.source
        }
        if !sample.isEmpty {
            lines.append("")
            lines.append(source == .recognized ? "Content excerpt (text recognized on-device from the image):" : "Content excerpt:")
            lines.append(String(sample.prefix(sampleLimit)))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Spotlight

    private static func spotlightMetadata(url: URL)
        -> (fields: [(String, String)], textContent: String)
    {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
            return ([], "")
        }
        func str(_ key: CFString) -> String {
            let value = MDItemCopyAttribute(item, key)
            if let s = value as? String { return s }
            if let list = value as? [String] { return list.joined(separator: ", ") }
            return ""
        }
        let fields: [(String, String)] = [
            ("Kind", str(kMDItemKind)),
            ("Title (metadata)", str(kMDItemTitle)),
            ("Authors (metadata)", str(kMDItemAuthors)),
            ("Album/Work", str(kMDItemAlbum)),
            ("Description (metadata)", String(str(kMDItemDescription).prefix(800))),
            ("Downloaded from", str(kMDItemWhereFroms)),
        ]
        let text = str(kMDItemTextContent)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return (fields, String(text.prefix(sampleLimit)))
    }

    // MARK: - Content extraction

    /// The classification sample for a file, by type: plain text and markup,
    /// office documents, PDFs (text layer first, OCR of a scan second),
    /// e-books, and images via on-device OCR.
    static func extractSample(url: URL) -> (text: String, source: SampleSource) {
        let ext = url.pathExtension.lowercased()
        if plainTextExtensions.contains(ext) {
            return (readPlainText(url: url), .text)
        }
        if markupExtensions.contains(ext) {
            // A saved web page's first 64 KiB is mostly <head>, CSS and
            // scripts; the model should see the visible text, not the markup.
            return (normalize(HTMLText.strip(readPlainText(url: url, normalized: false))), .text)
        }
        if DocumentText.richTextExtensions.contains(ext)
            || DocumentText.spreadsheetExtensions.contains(ext)
            || DocumentText.presentationExtensions.contains(ext) {
            return (normalize(DocumentText.text(url: url, limit: sampleLimit * 2)), .text)
        }
        if ext == "pdf" { return readPDF(url: url) }
        if ext == "epub" { return (EpubReader(url: url)?.classificationText ?? "", .text) }
        if ImageText.imageExtensions.contains(ext) {
            return (normalize(ImageText.recognize(imageAt: url)), .recognized)
        }
        return ("", .none)
    }

    private static func readPlainText(url: URL, normalized: Bool = true) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 64 * 1024)
        else { return "" }
        try? handle.close()
        // The fixed-size read may have split a multi-byte UTF-8 character at
        // the boundary; trim the partial tail so the whole excerpt doesn't
        // fall back to CP1252 mojibake.
        let text = TextDecoding.decode(TextDecoding.trimmingPartialUTF8Tail(data))
        return normalized ? normalize(text) : text
    }

    private static func readPDF(url: URL) -> (text: String, source: SampleSource) {
        guard let document = PDFDocument(url: url) else { return ("", .none) }
        var text = ""
        for index in 0..<min(document.pageCount, 5) {
            text += document.page(at: index)?.string ?? ""
            if text.count >= sampleLimit { break }
        }
        let normalized = normalize(text)
        if !normalized.isEmpty { return (normalized, .text) }
        // No text layer: a scan. Read it the way a person would.
        return (normalize(ImageText.recognize(scannedPDF: document)), .recognized)
    }

    private static func normalize(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        return String(collapsed.trimmingCharacters(in: .whitespaces).prefix(sampleLimit))
    }
}

private extension EpubReader {
    /// Metadata fields plus the opening text, flattened for the model.
    var classificationText: String {
        var parts: [String] = []
        if !metadata.title.isEmpty { parts.append("Title (OPF): \(metadata.title)") }
        if !metadata.creators.isEmpty {
            parts.append("Author(s) (OPF): \(metadata.creators.joined(separator: "; "))")
        }
        if !metadata.subjects.isEmpty {
            parts.append("Subjects (OPF): \(metadata.subjects.joined(separator: ", "))")
        }
        if !metadata.language.isEmpty { parts.append("Language (OPF): \(metadata.language)") }
        if !metadata.publisher.isEmpty { parts.append("Publisher (OPF): \(metadata.publisher)") }
        if !metadata.description.isEmpty { parts.append("Description (OPF): \(metadata.description)") }
        if !sample.isEmpty { parts.append(sample) }
        return parts.joined(separator: "\n")
    }
}
