import Foundation

enum MoveOutcome {
    case moved(URL)
    case copied(URL)
    case duplicate(URL)
}

enum MoveError: LocalizedError {
    case unsafePath(String)
    case tooManyCollisions(String)

    var errorDescription: String? {
        switch self {
        case .unsafePath(let path): return "Unsicherer Zielpfad: \(path)"
        case .tooManyCollisions(let path): return "Zu viele Namenskollisionen: \(path)"
        }
    }
}

enum Mover {
    /// Mirrors the sanitization rules of the original Python script.
    static func sanitizeComponent(_ name: String, maxLength: Int = 120) -> String {
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
        return cleaned.isEmpty ? "Unbekannt" : cleaned
    }

    /// Turns the LLM's relative path into a safe destination inside `target`,
    /// forcing the original file extension.
    static func destination(
        target: URL, relativePath: String, originalExtension: String
    ) throws -> URL {
        let rawComponents = relativePath
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard !rawComponents.isEmpty, !rawComponents.contains("..") else {
            throw MoveError.unsafePath(relativePath)
        }
        var components = rawComponents.map { sanitizeComponent($0, maxLength: 150) }
        var filename = components.removeLast()
        if !originalExtension.isEmpty {
            let suffix = "." + originalExtension.lowercased()
            if !filename.lowercased().hasSuffix(suffix) {
                // Strip whatever extension the model invented, keep the real one.
                filename = (filename as NSString).deletingPathExtension + suffix
            }
        }
        var url = target
        for component in components {
            url.appendPathComponent(component, isDirectory: true)
        }
        return url.appendingPathComponent(filename)
    }

    /// Move or copy with duplicate detection and collision suffixes.
    static func place(source: URL, destination: URL, copy: Bool) throws -> MoveOutcome {
        let fm = FileManager.default
        let sourceSize = (try? fm.attributesOfItem(atPath: source.path)[.size] as? Int64) ?? -1

        var final = destination
        if fm.fileExists(atPath: final.path) {
            let stem = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            var found: URL?
            for index in 1...99 {
                let candidate = index == 1
                    ? destination
                    : destination.deletingLastPathComponent()
                        .appendingPathComponent("\(stem) (\(index))")
                        .appendingPathExtension(ext)
                if !fm.fileExists(atPath: candidate.path) {
                    found = candidate
                    break
                }
                let existingSize =
                    (try? fm.attributesOfItem(atPath: candidate.path)[.size] as? Int64) ?? -2
                if existingSize == sourceSize {
                    return .duplicate(candidate)
                }
            }
            guard let unique = found else {
                throw MoveError.tooManyCollisions(destination.path)
            }
            final = unique
        }

        try fm.createDirectory(
            at: final.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        if copy {
            try fm.copyItem(at: source, to: final)
            return .copied(final)
        }
        do {
            try fm.moveItem(at: source, to: final)
        } catch {
            // Cross-volume move: fall back to copy + delete.
            try fm.copyItem(at: source, to: final)
            try fm.removeItem(at: source)
        }
        return .moved(final)
    }
}
