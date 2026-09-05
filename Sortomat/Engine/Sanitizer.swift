import Foundation

enum PathError: LocalizedError {
    case unsafePath(String)
    case tooManyCollisions(String)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path): return L10n.t("error.unsafePath", path)
        case .tooManyCollisions(let path): return L10n.t("error.tooManyCollisions", path)
        }
    }
}

/// Turns model/pre-rule output into a *safe* destination inside a target folder.
/// This is the highest-risk area of the app (an irreversible move to the wrong
/// place), so it is deliberately strict and fully unit-tested.
enum Sanitizer {
    /// Everything that is recognizably a file extension. Extension forcing
    /// replaces only these: a model that answers `report.txt` for a PDF gets
    /// `report.pdf`, while name content that merely contains dots —
    /// `Screenshot at 10.15.32`, `backup.2024.01`, `Tolkien, J.R.R` — keeps
    /// every segment and gets the real extension appended.
    static let knownExtensions: Set<String> = {
        var all = Set(DeterministicEngine.kindExtensions.values.joined())
        all.formUnion([
            "txt", "md", "markdown", "json", "xml", "yml", "yaml", "html", "htm", "log",
            "tex", "srt", "rtf", "rtfd", "csv", "tsv", "odp", "dmg", "pkg", "app", "iso",
            "svg", "psd", "ai", "dng", "raw", "cr2", "nef", "arw", "avif",
            "swift", "py", "js", "ts", "rb", "go", "rs", "c", "h", "cpp", "java", "sh",
            "css", "ics", "vcf", "eml", "msg", "ttf", "otf", "woff", "woff2", "exe",
            "torrent", "sortomatrule",
        ])
        return all
    }()

    /// Make one string safe as a single file/directory name. Mirrors the original
    /// Python script's rules (forbidden chars, collapse whitespace, trim dots).
    static func sanitizeComponent(_ name: String, maxLength: Int = 150) -> String {
        var cleaned = name.precomposedStringWithCanonicalMapping
        // Forbidden path characters, C0 controls, DEL — and every Unicode
        // *format* character (zero-width spaces and joiners, bidi overrides,
        // the BOM): invisible in Finder, so a prompt-injected name could split
        // files across two folders that look identical, or render reversed.
        cleaned = cleaned.replacingOccurrences(
            of: "[<>:\"/\\\\|?*\\x00-\\x1f\\x7f]|\\p{Cf}", with: " ", options: .regularExpression
        )
        cleaned = cleaned.replacingOccurrences(
            of: "\\s+", with: " ", options: .regularExpression
        )
        cleaned = cleaned.trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        cleaned = truncated(cleaned, characters: maxLength)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        // Never let a component become empty, "." or ".." after sanitizing.
        // The fallback name follows the UI language (it used to be German for
        // everyone).
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return L10n.t("component.unknown")
        }
        return cleaned
    }

    /// APFS and HFS+ cap a single path component at 255 *bytes*, not
    /// characters. A 150-character CJK or emoji title is 450–600 bytes, so the
    /// grapheme cap alone let a perfectly sanitized name still fail the move
    /// with `ENAMETOOLONG` — every pass, forever, for the same file.
    static let maxComponentBytes = 255

    /// A whole file name trimmed to fit one path component, dropping graphemes
    /// from the *stem* so the extension always survives — it is how macOS, and
    /// every rule in this app, recognizes what the file is.
    ///
    /// `sanitizeComponent` caps the name it is given, but the real extension is
    /// forced on *afterwards*: a 252-byte CJK title plus `.epub` is a 257-byte
    /// component, and the `ENAMETOOLONG` this cap exists to prevent came back
    /// for exactly the common case.
    static func fittingComponent(_ filename: String, bytes: Int = maxComponentBytes) -> String {
        guard filename.utf8.count > bytes else { return filename }
        let ext = (filename as NSString).pathExtension
        let suffix = ext.isEmpty ? "" : "." + ext
        let stem = String(filename.dropLast(suffix.count))
        let trimmed = truncated(stem, characters: stem.count, bytes: bytes - suffix.utf8.count)
        // An extension long enough to leave no room for a stem at all: keep a
        // fitting prefix of the whole name rather than returning ".epub".
        guard !trimmed.isEmpty else { return truncated(filename, characters: filename.count) }
        return trimmed + suffix
    }

    /// Trimmed to both limits, cutting on grapheme boundaries so a truncation
    /// can never split a character (or an emoji's joiner sequence) in half.
    static func truncated(_ text: String, characters: Int,
                          bytes: Int = maxComponentBytes) -> String {
        var result = String(text.prefix(characters))
        while result.utf8.count > bytes, !result.isEmpty {
            // One grapheme at a time: a byte-wise cut would land inside a
            // multi-byte character, and the remainder is what gets written to
            // disk. Names this long are rare enough that the loop is cheaper
            // than the arithmetic to avoid it.
            result = String(result.dropLast())
        }
        return result
    }

    /// Build a safe absolute destination under `target` from a relative path,
    /// forcing the file's original extension. Rejects absolute paths and any
    /// `..` traversal *before* sanitizing (so a crafted "../.." can't escape).
    /// Bare `.` segments (`./Docs/x.pdf`, a common model path style) are
    /// dropped rather than turned into an "Unknown" folder.
    static func destination(
        target: URL, relativePath: String, originalExtension: String
    ) throws -> URL {
        let rawComponents = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { $0 != "." }
        guard !rawComponents.isEmpty,
              !rawComponents.contains(".."),
              !relativePath.hasPrefix("/"),
              !relativePath.hasPrefix("~")
        else {
            throw PathError.unsafePath(relativePath)
        }

        var components = rawComponents.map { sanitizeComponent($0) }
        var filename = components.removeLast()
        if !originalExtension.isEmpty {
            filename = forcingExtension(originalExtension, on: filename)
        }
        // After the extension, not before: forcing one on can push a name that
        // fitted back over the byte limit.
        filename = fittingComponent(filename)

        var url = target
        for component in components {
            url.appendPathComponent(component, isDirectory: true)
        }
        url = url.appendingPathComponent(filename)

        // Defense in depth: the fully standardized path must still live under the
        // target after all component processing.
        let base = target.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(base + "/") else {
            throw PathError.unsafePath(relativePath)
        }
        return url
    }

    /// `filename` with the file's real extension: unchanged when it already
    /// ends in it, with a *recognized* wrong extension replaced, and otherwise
    /// appended — so dotted name content survives (the old unconditional
    /// `deletingPathExtension` silently renamed `… at 10.15.32.png` to
    /// `… at 10.15.png`).
    static func forcingExtension(_ originalExtension: String, on filename: String) -> String {
        let suffix = "." + originalExtension.lowercased()
        if filename.lowercased().hasSuffix(suffix) { return filename }
        let current = (filename as NSString).pathExtension
        if !current.isEmpty, knownExtensions.contains(current.lowercased()) {
            return (filename as NSString).deletingPathExtension + suffix
        }
        return filename + suffix
    }
}
