import CoreServices
import Foundation
import PDFKit

/// Builds the textual description of a file handed to the model: name, dates,
/// Spotlight metadata and — unless the rule is metadata-only — a content excerpt.
enum FileContext {
    static let sampleLimit = 4000

    private static let plainTextExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "yml", "yaml",
        "html", "htm", "log", "tex", "srt", "rtf",
    ]

    static func describe(url: URL, privacyMode: PrivacyMode = .full) -> String {
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? Int64) ?? 0
        let formatter = DateFormatter()
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

        guard privacyMode == .full else {
            lines.append("")
            lines.append("(Metadata-only rule: file contents were not read.)")
            return lines.joined(separator: "\n")
        }

        var sample = spotlight.textContent
        if sample.isEmpty { sample = extractSample(url: url) }
        if !sample.isEmpty {
            lines.append("")
            lines.append("Content excerpt:")
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
        ]
        let text = str(kMDItemTextContent)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return (fields, String(text.prefix(sampleLimit)))
    }

    // MARK: - Content extraction

    private static func extractSample(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if plainTextExtensions.contains(ext) { return readPlainText(url: url) }
        if ext == "pdf" { return readPDF(url: url) }
        if ext == "epub" { return EpubReader(url: url)?.classificationText ?? "" }
        return ""
    }

    private static func readPlainText(url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 64 * 1024)
        else { return "" }
        try? handle.close()
        return normalize(TextDecoding.decode(data))
    }

    private static func readPDF(url: URL) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var text = ""
        for index in 0..<min(document.pageCount, 5) {
            text += document.page(at: index)?.string ?? ""
            if text.count >= sampleLimit { break }
        }
        return normalize(text)
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
