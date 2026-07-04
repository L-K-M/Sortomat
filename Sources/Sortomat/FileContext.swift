import CoreServices
import Foundation
import PDFKit

/// Builds a textual description of a file for the LLM: name, dates,
/// Spotlight metadata, and a content excerpt where we can get one.
enum FileContext {
    static let sampleLimit = 4000

    private static let plainTextExtensions: Set<String> = [
        "txt", "md", "markdown", "csv", "tsv", "json", "xml", "yml", "yaml",
        "html", "htm", "log", "tex", "srt",
    ]

    static func describe(url: URL) -> String {
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let attrs = (try? FileManager.default.attributesOfItem(atPath: url.path)) ?? [:]
        let size = (attrs[.size] as? Int64) ?? 0
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines = ["Datei:", "Name: \(name)"]
        lines.append("Grösse: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
        if let created = attrs[.creationDate] as? Date {
            lines.append("Erstellt: \(formatter.string(from: created))")
        }
        if let modified = attrs[.modificationDate] as? Date {
            lines.append("Geändert: \(formatter.string(from: modified))")
        }

        let spotlight = spotlightMetadata(url: url)
        for (label, value) in spotlight.fields where !value.isEmpty {
            lines.append("\(label): \(value)")
        }

        var sample = spotlight.textContent
        if sample.isEmpty { sample = extractSample(url: url, ext: ext) }
        if !sample.isEmpty {
            lines.append("")
            lines.append("Inhaltsauszug:")
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
            ("Art", str(kMDItemKind)),
            ("Titel (Metadaten)", str(kMDItemTitle)),
            ("Autoren (Metadaten)", str(kMDItemAuthors)),
            ("Album/Werk", str(kMDItemAlbum)),
            ("Beschreibung (Metadaten)", String(str(kMDItemDescription).prefix(800))),
        ]
        let text = str(kMDItemTextContent)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return (fields, String(text.prefix(sampleLimit)))
    }

    // MARK: - Content extraction fallbacks

    private static func extractSample(url: URL, ext: String) -> String {
        if plainTextExtensions.contains(ext) {
            return readPlainText(url: url)
        }
        if ext == "pdf" {
            return readPDF(url: url)
        }
        if ext == "epub" {
            return readEPUB(url: url)
        }
        return ""
    }

    private static func readPlainText(url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url),
              let data = try? handle.read(upToCount: 16_384)
        else { return "" }
        try? handle.close()
        let text = String(decoding: data, as: UTF8.self)
        return normalize(text)
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

    private static func readEPUB(url: URL) -> String {
        // OPF metadata (title, creator, subjects, description) …
        var parts: [String] = []
        let opfData = runUnzip(archive: url, patterns: ["*.opf"], maxBytes: 262_144)
        if let doc = try? XMLDocument(data: opfData, options: [.documentTidyXML]) {
            let tags = [
                ("title", "Titel (OPF)"), ("creator", "Autor (OPF)"),
                ("subject", "Schlagwörter (OPF)"), ("description", "Beschreibung (OPF)"),
            ]
            for (tag, label) in tags {
                let nodes = (try? doc.nodes(forXPath: "//*[local-name()='\(tag)']")) ?? []
                let values = nodes.compactMap { $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
                if !values.isEmpty {
                    parts.append("\(label): \(values.joined(separator: "; ").prefix(600))")
                }
            }
        }
        // … plus a rough text sample from the first content documents.
        let htmlData = runUnzip(
            archive: url, patterns: ["*.xhtml", "*.html", "*.htm"], maxBytes: 262_144
        )
        if !htmlData.isEmpty {
            let html = String(decoding: htmlData, as: UTF8.self)
            let stripped = html
                .replacingOccurrences(
                    of: "<(script|style)[^>]*>.*?</\\1>", with: " ",
                    options: [.regularExpression, .caseInsensitive]
                )
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            parts.append(normalize(stripped))
        }
        return parts.joined(separator: "\n")
    }

    private static func runUnzip(archive: URL, patterns: [String], maxBytes: Int) -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path] + patterns
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return Data()
        }
        var collected = Data()
        let handle = stdout.fileHandleForReading
        while collected.count < maxBytes {
            let chunk = handle.availableData
            if chunk.isEmpty { break }
            collected.append(chunk)
        }
        if process.isRunning { process.terminate() }
        // Drain so the process can exit, then reap it.
        DispatchQueue.global(qos: .utility).async {
            _ = try? handle.readToEnd()
            process.waitUntilExit()
        }
        return collected.prefix(maxBytes)
    }

    private static func normalize(_ text: String) -> String {
        let collapsed = text.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        return String(collapsed.trimmingCharacters(in: .whitespaces).prefix(sampleLimit))
    }
}
