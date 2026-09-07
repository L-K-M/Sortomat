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
        // Audio ahead of video, and it has to be: `public.mpeg-4-audio`
        // conforms to `public.audio` *and*, through `public.mpeg-4`, to
        // `public.movie`. First match wins, so every `.m4a` and `.m4b`
        // resolved through Launch Services was sorting into the video folder
        // while the extension table called it audio — an audiobook library
        // filed as films. The same shape as `.docx` landing in Archives.
        (.audio, ["public.audio"]),
        (.video, ["public.movie"]),
        (.font, ["public.font"]),
        // `com.apple.installer-package` conforms to `public.archive` and to no
        // disk-image type, so a `.pkg` resolved through Launch Services landed
        // in Archives while the extension fallback said Disk Images. Named
        // explicitly, and ahead of `.archive`, both paths agree. An identifier
        // no system declares resolves to nil and is skipped, so this is free.
        (.diskImage, ["public.disk-image", "com.apple.disk-image",
                      "com.apple.installer-package"]),
        (.code, ["public.source-code", "public.shell-script", "public.script"]),
        // `public.rtf` sits with the text types, not here: the legacy table
        // this migration promises to reproduce calls `rtf` text, and it is the
        // extension fallback that must stay verbatim. RTFD — a package with
        // attachments — is a document on both paths, as it was.
        (.document, ["com.apple.rtfd",
                     "org.openxmlformats.wordprocessingml.document",
                     "com.microsoft.word.doc", "com.apple.iwork.pages.pages",
                     "org.oasis-open.opendocument.text"]),
        // After the document types, not before them. OOXML and OpenDocument
        // files are zip containers — `org.openxmlformats.wordprocessingml.document`
        // conforms to `public.zip-archive` — so with `.archive` first, every
        // `.docx` and `.odt` resolved through Launch Services sorted into
        // Archives. `.spreadsheet`, `.presentation` and `.ebook` are zip
        // containers too and were only safe because they already sat above it.
        (.archive, ["public.archive", "public.zip-archive", "org.gnu.gnu-zip-archive"]),
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

    /// `conformance` resolved once. Every entry was being turned back into a
    /// `UTType` for every candidate of every kind, for every file in a scan —
    /// a Launch Services lookup per row per file, to answer a question whose
    /// answer never changes while the app runs. (It can change if an app is
    /// installed *while* Sortomat runs, which is what a relaunch is for; the
    /// extension table answers in the meantime.)
    private static let resolvedConformance: [(Kind, [UTType])] =
        conformance.map { row in (row.0, row.1.compactMap { UTType($0) }) }

    static func kind(forUTI identifier: String?) -> Kind? {
        guard let identifier, let type = UTType(identifier) else { return nil }
        for (kind, targets) in resolvedConformance {
            for target in targets where type.conforms(to: target) { return kind }
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
            // Not every still image in an ISO container says «heic». HEIF's
            // brands are `mif1` and `msf1` as often as `heic`/`heix`
            // (ISO/IEC 23008-12), AVIF's are `avif`/`avis`, and an iTunes
            // audio file says `M4A `/`M4B `/`M4P `. Defaulting all of those to
            // video put a photo in the video folder — the wrong-bucket failure
            // this resolver exists to prevent, and only for the extensionless
            // files that reach the sniffer at all.
            if ["M4A", "M4B", "M4P"].contains(where: brand.hasPrefix) { return .audio }
            let image = ["hei", "hev", "mif", "msf", "avi", "avci"]
            return image.contains(where: brand.hasPrefix) ? .image : .video
        }
        if starts([0x50, 0x4B, 0x03, 0x04]) { return .archive }                   // zip
        if starts([0x1F, 0x8B]) { return .archive }                               // gzip
        if starts([0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return .archive }       // 7z
        // Mach-O in all three spellings, not just 64-bit little-endian: 32-bit
        // (`ce fa ed fe`) and the fat/universal header (`ca fe ba be`) are the
        // same answer, and the fat one is what a shipped binary usually is.
        if starts([0x7F, 0x45, 0x4C, 0x46])                                    // ELF
            || starts([0xCF, 0xFA, 0xED, 0xFE]) || starts([0xCE, 0xFA, 0xED, 0xFE])
            || starts([0xFE, 0xED, 0xFA, 0xCF]) || starts([0xFE, 0xED, 0xFA, 0xCE])
            || starts([0xCA, 0xFE, 0xBA, 0xBE]) {                              // universal
            return .other
        }
        // `.code`, because `sh`, `zsh`, `bash` and the rest are `.code` in the
        // extension table: a script with an extension and the same script
        // without one must not sort into two different folders.
        if starts([0x23, 0x21]) { return .code }                                  // #!
        if !bytes.contains(0), String(data: header, encoding: .utf8) != nil { return .text }
        return nil
    }
}
