import Foundation

/// Parses an EPUB into metadata + an opening text sample, in-process (no `unzip`
/// subprocess). Ports the robustness of the original Python script: locate the
/// OPF via `container.xml` with a fallback to the shallowest `.opf`, tolerate
/// non-conforming XML, and skip near-empty cover/TOC documents when sampling.
struct EpubReader {
    struct Metadata {
        var title = ""
        var creators: [String] = []
        var subjects: [String] = []
        var language = ""
        var publisher = ""
        var description = ""
    }

    let metadata: Metadata
    let sample: String

    init?(url: URL, sampleLimit: Int = 4000) {
        guard let zip = ZipArchive(url: url) else { return nil }

        // Find the OPF package document.
        var opfName: String?
        if let container = zip.entry(named: "META-INF/container.xml") ?? zip.firstEntry(withSuffixes: ["container.xml"]),
           let data = zip.data(for: container),
           let root = Self.parseXML(data),
           let rootfile = (try? root.nodes(forXPath: "//*[local-name()='rootfile']"))?.first as? XMLElement,
           let full = rootfile.attribute(forName: "full-path")?.stringValue, !full.isEmpty {
            opfName = full
        }
        let opfEntry = opfName.flatMap { zip.entry(named: $0) }
            ?? zip.firstEntry(withSuffixes: [".opf"])
        guard let opfEntry,
              let opfData = zip.data(for: opfEntry),
              let opfRoot = Self.parseXML(opfData)
        else { return nil }

        self.metadata = Self.parseMetadata(opfRoot)
        self.sample = Self.extractSample(
            zip: zip, opfRoot: opfRoot, opfPath: opfEntry.name, limit: sampleLimit
        )
    }

    // MARK: - Metadata

    private static func parseMetadata(_ root: XMLElement) -> Metadata {
        var meta = Metadata()
        func dcAll(_ tag: String) -> [String] {
            let nodes = (try? root.nodes(forXPath: "//*[local-name()='\(tag)']")) ?? []
            return nodes.compactMap {
                $0.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.filter { !$0.isEmpty }
        }
        meta.title = dcAll("title").first ?? ""
        meta.creators = dcAll("creator")
        meta.subjects = dcAll("subject")
        meta.language = dcAll("language").joined(separator: ", ")
        meta.publisher = dcAll("publisher").joined(separator: ", ")
        if let desc = dcAll("description").first {
            meta.description = String(HTMLText.strip(desc).prefix(1500))
        }
        return meta
    }

    // MARK: - Text sample

    private static func extractSample(
        zip: ZipArchive, opfRoot: XMLElement, opfPath: String, limit: Int
    ) -> String {
        // manifest id -> href
        var manifest: [String: String] = [:]
        let items = (try? opfRoot.nodes(forXPath: "//*[local-name()='manifest']/*[local-name()='item']")) ?? []
        for case let item as XMLElement in items {
            if let id = item.attribute(forName: "id")?.stringValue,
               let href = item.attribute(forName: "href")?.stringValue {
                manifest[id] = href
            }
        }

        let opfDir = (opfPath as NSString).deletingLastPathComponent
        var chunks: [String] = []
        var collected = 0

        let refs = (try? opfRoot.nodes(forXPath: "//*[local-name()='spine']/*[local-name()='itemref']")) ?? []
        for case let ref as XMLElement in refs {
            guard let idref = ref.attribute(forName: "idref")?.stringValue,
                  let href = manifest[idref]?.removingPercentEncoding ?? manifest[idref]
            else { continue }

            let docPath = resolvePath(dir: opfDir, href: href)
            guard let entry = zip.entry(named: docPath),
                  let data = zip.data(for: entry) else { continue }

            let text = HTMLText.strip(TextDecoding.decode(data))
            if text.count < 200 { continue } // skip cover/title/TOC pages
            chunks.append(text)
            collected += text.count
            if collected >= limit { break }
        }
        return String(chunks.joined(separator: " ").prefix(limit))
    }

    private static func resolvePath(dir: String, href: String) -> String {
        let joined = dir.isEmpty ? href : "\(dir)/\(href)"
        // Normalize any ./ or ../ segments.
        var stack: [String] = []
        for part in joined.split(separator: "/", omittingEmptySubsequences: true) {
            if part == "." { continue }
            if part == ".." { _ = stack.popLast(); continue }
            stack.append(String(part))
        }
        return stack.joined(separator: "/")
    }

    // MARK: - Lenient XML

    private static func parseXML(_ data: Data) -> XMLElement? {
        if let doc = try? XMLDocument(data: data, options: [.nodePreserveWhitespace]) {
            return doc.rootElement()
        }
        // Retry tidily — real-world EPUBs are frequently non-conforming.
        if let doc = try? XMLDocument(data: data, options: [.documentTidyXML]) {
            return doc.rootElement()
        }
        return nil
    }
}
