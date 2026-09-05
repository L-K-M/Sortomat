import AppKit
import Foundation

/// Text out of office documents without any network or third-party code:
/// Word and RTF through AppKit's attributed-string reader, and the zip-of-XML
/// formats — OOXML spreadsheets and decks, and every OpenDocument file —
/// through the in-process zip reader. Previously every one of these reached
/// the model as name + metadata only, so "file this invoice" had nothing to
/// go on.
enum DocumentText {
    /// Documents larger than this aren't parsed — the reader would load them
    /// whole, and a classification sample is a few thousand characters.
    static let maxDocumentBytes: Int64 = 64 * 1024 * 1024
    /// Markup beyond this per zip entry is ignored: only a few thousand
    /// characters ever reach the model.
    static let maxMarkupCharacters = 512 * 1024

    /// Extensions `text(url:)` knows how to read.
    static let richTextExtensions: Set<String> = ["rtf", "rtfd", "doc", "docx", "docm", "odt"]
    /// The macro and template twins are byte-for-byte their plain siblings —
    /// same OPC zip, same `xl/sharedStrings.xml`, same `xl/worksheets/sheetN.xml`.
    /// Only the extension differs, and dropping them cost the whole sample.
    static let spreadsheetExtensions: Set<String> = ["xlsx", "xlsm", "xltx", "xltm"]
    /// Likewise `pptm` (macros) and `ppsx` (opens as a slideshow): the body is
    /// `ppt/slides/slideN.xml` in all three.
    static let presentationExtensions: Set<String> = ["pptx", "pptm", "ppsx"]
    /// Every OpenDocument format keeps its body in one `content.xml`, so text,
    /// spreadsheet and presentation all read the same way.
    static let openDocumentExtensions: Set<String> = ["odt", "ods", "odp", "odg"]

    static func text(url: URL, limit: Int) -> String {
        let ext = url.pathExtension.lowercased()
        if spreadsheetExtensions.contains(ext) { return spreadsheetText(url: url, limit: limit) }
        if presentationExtensions.contains(ext) { return presentationText(url: url, limit: limit) }
        guard richTextExtensions.contains(ext) || openDocumentExtensions.contains(ext) else {
            return ""
        }
        if let text = attributedStringText(url: url, limit: limit), !text.isEmpty {
            // `limit` is what reaches the model, so it bounds the return value
            // here rather than four times over: the readers cut at four bytes
            // per allowed character only to keep the *intermediate* small.
            return String(text.prefix(limit))
        }
        // What AppKit cannot read (or rejects) is still a zip with the body in
        // a known entry. Whether the reader handles OpenDocument at all varies;
        // going through the zip makes the answer the same either way.
        if ext == "docx" || ext == "docm" {
            return zipXMLText(url: url, entries: ["word/document.xml"], limit: limit)
        }
        if openDocumentExtensions.contains(ext) {
            return zipXMLText(url: url, entries: ["content.xml", "meta.xml"], limit: limit)
        }
        return ""
    }

    // MARK: - AppKit document reader

    private static func attributedStringText(url: URL, limit: Int) -> String? {
        guard sizeAllows(url) else { return nil }
        var options: [NSAttributedString.DocumentReadingOptionKey: Any] = [:]
        switch url.pathExtension.lowercased() {
        case "docx", "docm": options[.documentType] = NSAttributedString.DocumentType.officeOpenXML
        case "doc": options[.documentType] = NSAttributedString.DocumentType.docFormat
        case "rtf": options[.documentType] = NSAttributedString.DocumentType.rtf
        case "rtfd": options[.documentType] = NSAttributedString.DocumentType.rtfd
        // Name the format instead of letting the reader sniff it: an
        // OpenDocument file is a zip, and a sniff that guesses "plain text"
        // returns the compressed bytes as mojibake — which is non-empty, so it
        // would win over the `content.xml` path below and be the *only* sample
        // this file ever produces.
        case "odt": options[.documentType] = NSAttributedString.DocumentType.openDocument
        // `.openDocument` is the text format; there is no reader for the
        // spreadsheet, presentation and drawing ones, so go straight to the zip.
        case "ods", "odp", "odg": return nil
        default: break
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
        // Read separately. Reading both in one pass and falling back only when
        // the *combined* result was empty made `docProps/core.xml` — which
        // almost always carries a creator name, `openpyxl` included — count as
        // evidence that the shared table had text. So for exactly the files the
        // fallback exists for, the model got the document properties and not
        // one cell of the sheet.
        let strings = zipXMLText(url: url, entries: ["xl/sharedStrings.xml"], limit: limit)
        let properties = zipXMLText(url: url, entries: ["docProps/core.xml"], limit: limit)
        let body = strings.isEmpty ? inlineWorksheetText(url: url, limit: limit) : strings
        if body.isEmpty { return properties }
        if properties.isEmpty { return body }
        return String((body + " " + properties).prefix(limit))
    }

    /// The fallback for exporters that skip the shared table and write every
    /// string inline (`<is><t>…</t></is>`), which leaves the workbook above
    /// with no text at all.
    ///
    /// Only the inline runs are taken, not the worksheet wholesale: a cell's
    /// other values are shared-string *indices* and date serial numbers, so
    /// reading the sheet as markup would hand the model a stream of integers
    /// that mean nothing without the style table to decode them.
    private static func inlineWorksheetText(url: URL, limit: Int) -> String {
        guard sizeAllows(url), let zip = ZipArchive(url: url) else { return "" }
        let sheets = zip.entries
            .filter { $0.name.hasPrefix("xl/worksheets/sheet") && $0.name.hasSuffix(".xml") }
            .sorted { partNumber($0.name) < partNumber($1.name) }
            // First three sheets only: a workbook can hold hundreds, and a
            // classification sample is a few thousand characters. Text that
            // lives only on sheet 4 is lost — deliberately, against reading
            // every sheet of every workbook that reaches the model.
            .prefix(3)
        return collect(from: Array(sheets), in: zip, limit: limit) { inlineStrings(in: $0) }
    }

    /// The contents of every `<is>…</is>` run, joined; everything outside them
    /// dropped.
    private static func inlineStrings(in markup: String) -> String {
        var pieces: [Substring] = []
        var rest = Substring(markup)
        while let open = rest.range(of: "<is>"),
              let close = rest[open.upperBound...].range(of: "</is>") {
            pieces.append(rest[open.upperBound..<close.lowerBound])
            rest = rest[close.upperBound...]
        }
        return pieces.joined(separator: " ")
    }

    /// Slides in deck order (slide1, slide2, …, not the lexical slide10-first).
    private static func presentationText(url: URL, limit: Int) -> String {
        guard sizeAllows(url), let zip = ZipArchive(url: url) else { return "" }
        let slides = zip.entries
            .filter { $0.name.hasPrefix("ppt/slides/slide") && $0.name.hasSuffix(".xml") }
            .sorted { partNumber($0.name) < partNumber($1.name) }
        return collect(from: slides, in: zip, limit: limit)
    }

    /// The first run of digits in a part name — `slide10.xml` is the tenth
    /// slide, not the second.
    private static func partNumber(_ name: String) -> Int {
        let digits = name.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits) ?? Int.max
    }

    private static func zipXMLText(url: URL, entries names: [String], limit: Int) -> String {
        guard sizeAllows(url), let zip = ZipArchive(url: url) else { return "" }
        let entries = names.compactMap { zip.entry(named: $0) }
        return collect(from: entries, in: zip, limit: limit)
    }

    private static func collect(
        from entries: [ZipArchive.Entry], in zip: ZipArchive, limit: Int,
        keeping select: (String) -> String = { $0 }
    ) -> String {
        var pieces: [String] = []
        var collected = 0
        for entry in entries {
            if Task.isCancelled { break }
            guard let data = zip.data(for: entry) else { continue }
            // Tags become spaces, so adjacent cells/runs don't glue together;
            // XML entities decode the same way HTML ones do.
            // Cap the *bytes* decoded, not just the characters kept: a
            // 50 MB shared-string table would otherwise be materialized whole
            // before being cut down to a few hundred thousand characters.
            let bounded = TextDecoding.trimmingPartialUTF8Tail(
                Data(data.prefix(maxMarkupCharacters * 4))
            )
            let markup = String(TextDecoding.decode(bounded).prefix(maxMarkupCharacters))
            let text = HTMLText.strip(select(markup))
            guard !text.isEmpty else { continue }
            pieces.append(text)
            collected += text.count
            if collected >= limit { break }
        }
        return String(pieces.joined(separator: " ").prefix(limit))
    }

    /// Internal rather than private so a test can pin it: this cap has had the
    /// symlink bug once already, and a test that measures with `FileManager`
    /// instead of calling this pins Foundation's behaviour, not the reader's.
    static func sizeAllows(_ url: URL) -> Bool {
        // Resolve first: `attributesOfItem` and `resourceValues` describe the
        // *link*, while every reader below them — `NSAttributedString(url:)`,
        // `ZipArchive`, `FileHandle` — follows it. A symlink to a four-gigabyte
        // file therefore weighed a few bytes and sailed through the cap that
        // exists to stop exactly that read.
        let target = url.resolvingSymlinksInPath()
        // An .rtfd is a *directory*, and no resource key answers for what a
        // directory contains: `totalFileAllocatedSize` reports the folder entry
        // itself — a few kilobytes however much wrapped RTF and TIFF data the
        // bundle holds — so the cap has to add the contents up, or it does not
        // apply to the one format in this list that is a bundle.
        if (try? target.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            return bundleSize(of: target, stoppingAbove: maxDocumentBytes) <= maxDocumentBytes
        }
        let size = (try? FileManager.default.attributesOfItem(atPath: target.path))?[.size] as? Int64 ?? 0
        return size <= maxDocumentBytes
    }

    /// Bytes held by the files inside a bundle. Stops as soon as `ceiling` is
    /// passed: a bundle of a million files must not cost a million stats just
    /// to be rejected, so the answer is "over the ceiling", not the true total.
    static func bundleSize(of url: URL, stoppingAbove ceiling: Int64 = .max) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: []
        ) else { return .max }
        var total: Int64 = 0
        for case let child as URL in enumerator {
            total += Int64((try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            if total > ceiling { return total }
        }
        return total
    }
}
