import Foundation
import UniformTypeIdentifiers

/// Resolves a file's coarse `Kind`.
///
/// The old engine matched a free-text field against a hand-kept extension
/// table, which meant `image, pdf` (a comma list the placeholder itself
/// advertised) matched nothing, an extensionless file could never have a kind,
/// and every new format needed a code change. Launch Services already knows
/// all of this, including types declared by apps the user has installed.
enum KindResolver {
    /// UTI identifiers are used as *strings* resolved through `UTType(_:)`, so
    /// a spelling that does not exist on this SDK returns nil and skips the
    /// entry instead of breaking the build. Order matters: the first
    /// conforming entry wins, which is why `text` sits last — source code and
    /// word-processor documents both conform to `public.text`.
    static let conformance: [(Kind, [String])] = [
        (.ebook, ["org.idpf.epub-container"] + appDeclared),
        (.pdf, ["com.adobe.pdf"]),
        (.spreadsheet, ["public.spreadsheet", "org.openxmlformats.spreadsheetml.sheet",
                        "com.microsoft.excel.xls", "com.apple.iwork.numbers.numbers",
                        "org.oasis-open.opendocument.spreadsheet"]),
        (.presentation, ["public.presentation", "org.openxmlformats.presentationml.presentation",
                         "com.microsoft.powerpoint.ppt", "com.apple.iwork.keynote.key",
                         "org.oasis-open.opendocument.presentation"]),
        (.image, ["public.image"]),
        (.video, ["public.movie"]),
        (.audio, ["public.audio"]),
        (.font, ["public.font"]),
        // `com.apple.installer-package` conforms to `public.archive` and to no
        // disk-image type, so a `.pkg` resolved through Launch Services landed
        // in Archives while the extension fallback said Disk Images. Named
        // explicitly, and ahead of `.archive`, both paths agree. An identifier
        // no system declares resolves to nil and is skipped, so this is free.
        (.diskImage, ["public.disk-image", "com.apple.disk-image",
                      "com.apple.installer-package"]),
        (.archive, ["public.archive", "public.zip-archive", "org.gnu.gnu-zip-archive"]),
        (.code, ["public.source-code", "public.shell-script", "public.script"]),
        // `public.rtf` sits with the text types, not here: the legacy table
        // this migration promises to reproduce calls `rtf` text, and it is the
        // extension fallback that must stay verbatim. RTFD — a package with
        // attachments — is a document on both paths, as it was.
        (.document, ["com.apple.rtfd",
                     "org.openxmlformats.wordprocessingml.document",
                     "com.microsoft.word.doc", "com.apple.iwork.pages.pages",
                     "org.oasis-open.opendocument.text"]),
        (.text, ["public.rtf", "public.text"])
    ]

    /// Types no *system* declares: they exist only when an app that reads
    /// them is installed. `UTType(_:)` returns nil for an unknown identifier,
    /// so listing them costs nothing and helps the machines that have Kindle
    /// — and the extension table covers every one of them regardless.
    static let appDeclared = ["com.amazon.mobi8-ebook", "com.amazon.mobipocket-ebook", "public.fb2"]

    /// The legacy table, kept verbatim so a migrated rule behaves exactly as
    /// it did, and used as the fallback whenever Launch Services knows nothing
    /// (an unindexed volume, an unknown extension).
    static let extensionTable: [Kind: Set<String>] = [
        .image: ["png", "jpg", "jpeg", "heic", "heif", "gif", "tiff", "tif", "bmp", "webp",
                 "svg", "avif", "jxl", "dng", "raw", "cr2", "nef", "arw", "psd", "orf", "rw2"],
        .video: ["mp4", "mov", "m4v", "avi", "mkv", "webm", "mpg", "mpeg", "wmv", "flv",
                 "3gp", "ts", "mts"],
        .audio: ["mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "ogg", "opus", "wma"],
        .pdf: ["pdf"],
        .archive: ["zip", "tar", "gz", "tgz", "bz2", "rar", "7z", "xz", "zst"],
        .text: ["txt", "md", "markdown", "rtf", "csv", "tsv", "log", "json", "xml", "yml", "yaml"],
        .ebook: ["epub", "mobi", "azw", "azw3", "fb2", "djvu"],
        .document: ["doc", "docx", "odt", "pages", "rtfd", "textbundle"],
        .spreadsheet: ["xls", "xlsx", "ods", "numbers"],
        .presentation: ["ppt", "pptx", "odp", "key"],
        .code: ["swift", "c", "h", "cpp", "hpp", "m", "mm", "py", "rb", "js", "ts", "tsx",
                "jsx", "go", "rs", "java", "kt", "sh", "zsh", "bash", "pl", "php", "sql"],
        .font: ["ttf", "otf", "ttc", "woff", "woff2"],
        .diskImage: ["dmg", "iso", "pkg", "img", "sparsebundle"]
    ]

    static func kind(forUTI identifier: String?) -> Kind? {
        guard let identifier, let type = UTType(identifier) else { return nil }
        for (kind, identifiers) in conformance {
            for candidate in identifiers {
                if let target = UTType(candidate), type.conforms(to: target) { return kind }
            }
        }
        return nil
    }

    static func kind(forExtension ext: String) -> Kind? {
        let lowered = ext.lowercased()
        guard !lowered.isEmpty else { return nil }
        for kind in Kind.all {
            if extensionTable[kind]?.contains(lowered) == true { return kind }
        }
        return nil
    }

    /// Whether a file's UTI conforms to another type — the escape hatch for
    /// anything the fifteen coarse kinds do not cover.
    static func conforms(_ identifier: String?, to other: String) -> Bool {
        guard let identifier, let type = UTType(identifier), let target = UTType(other) else {
            return false
        }
        return type.conforms(to: target)
    }
}

/// The first sixteen bytes, for files that have no extension at all — which
/// the old engine could never classify, because its only input *was* the
/// extension. Runs only when the extension is empty and Launch Services
/// produced nothing, so it costs nothing for normal files.
enum MagicBytes {
    static let probeLength = 16

    static func kind(sniffing header: Data) -> Kind? {
        let bytes = [UInt8](header)
        guard !bytes.isEmpty else { return nil }

        func starts(_ signature: [UInt8], at offset: Int = 0) -> Bool {
            guard bytes.count >= offset + signature.count else { return false }
            for (index, byte) in signature.enumerated() where bytes[offset + index] != byte {
                return false
            }
            return true
        }

        if starts([0x25, 0x50, 0x44, 0x46]) { return .pdf }                       // %PDF
        if starts([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .image }
        if starts([0xFF, 0xD8, 0xFF]) { return .image }                           // JPEG
        if starts([0x47, 0x49, 0x46, 0x38]) { return .image }                     // GIF8
        if starts([0x49, 0x49, 0x2A, 0x00]) || starts([0x4D, 0x4D, 0x00, 0x2A]) { return .image }
        if starts([0x52, 0x49, 0x46, 0x46]), starts([0x57, 0x45, 0x42, 0x50], at: 8) {
            return .image                                                          // RIFF…WEBP
        }
        if starts([0x66, 0x74, 0x79, 0x70], at: 4) {                              // …ftyp
            let brand = bytes.count >= 12 ? String(decoding: bytes[8..<12], as: UTF8.self) : ""
            return brand.hasPrefix("hei") || brand.hasPrefix("avi") ? .image : .video
        }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return .archive }                   // zip
        if starts([0x1F, 0x8B]) { return .archive }                               // gzip
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .archive }       // 7z
        if starts([0x7F, 0x45, 0x4C, 0x46]) || starts([0xCF, 0xFA, 0xED, 0xFE]) { return .other }
        if starts([0x23, 0x21]) { return .text }                                  // #!
        if !bytes.contains(0), String(data: header, encoding: .utf8) != nil { return .text }
        return nil
    }
}
