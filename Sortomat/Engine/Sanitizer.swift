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
        cleaned = String(cleaned.prefix(maxLength))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        // Never let a component become empty, "." or ".." after sanitizing.
        if cleaned.isEmpty || cleaned == "." || cleaned == ".." {
            return "Unbekannt"
        }
        return cleaned
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
