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
    /// Make one string safe as a single file/directory name. Mirrors the original
    /// Python script's rules (forbidden chars, collapse whitespace, trim dots).
    static func sanitizeComponent(_ name: String, maxLength: Int = 150) -> String {
        var cleaned = name.precomposedStringWithCanonicalMapping
        cleaned = cleaned.replacingOccurrences(
            of: "[<>:\"/\\\\|?*\\x00-\\x1f]", with: " ", options: .regularExpression
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
    static func destination(
        target: URL, relativePath: String, originalExtension: String
    ) throws -> URL {
        let rawComponents = relativePath
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
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
            let suffix = "." + originalExtension.lowercased()
            if !filename.lowercased().hasSuffix(suffix) {
                filename = (filename as NSString).deletingPathExtension + suffix
            }
        }

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
}
