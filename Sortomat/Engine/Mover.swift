import Foundation

enum MoveOutcome: Equatable {
    case placed(URL)       // moved or copied to this final URL
    case duplicate(URL)    // an identical file already exists here
}

enum MoveError: LocalizedError {
    case sourceVanished
    case verifyFailed

    var errorDescription: String? {
        switch self {
        case .sourceVanished: return L10n.t("error.sourceVanished")
        case .verifyFailed: return L10n.t("error.verifyFailed")
        }
    }
}

/// Executes a placement decision safely: content-hash duplicate detection,
/// collision suffixes, a guard against a vanished source, and a cross-volume
/// fallback that verifies the copy before deleting the original.
enum Mover {
    /// Move or copy `source` to `destination` (creating parents), resolving
    /// collisions with ` (2)`, ` (3)` … and skipping true duplicates (same
    /// content hash), not merely same-size files.
    static func place(source: URL, destination: URL, copy: Bool) throws -> MoveOutcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: source.path) else { throw MoveError.sourceVanished }

        let target: URL
        switch try resolvePlacement(source: source, destination: destination) {
        case .duplicate(let url):
            return .duplicate(url)
        case .place(let url):
            target = url
        }

        try fm.createDirectory(
            at: target.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        if copy {
            try fm.copyItem(at: source, to: target)
            return .placed(target)
        }

        do {
            try fm.moveItem(at: source, to: target)
        } catch {
            // Only fall back to copy-then-delete for a genuine cross-volume move;
            // and only delete the original once the copy is verified intact.
            guard isCrossVolume(source: source, destination: target) else { throw error }
            try fm.copyItem(at: source, to: target)
            guard ContentHash.digest(of: source) == ContentHash.digest(of: target) else {
                try? fm.removeItem(at: target)
                throw MoveError.verifyFailed
            }
            try fm.removeItem(at: source)
        }
        return .placed(target)
    }

    private enum Placement {
        case place(URL)
        case duplicate(URL)
    }

    /// Decide the final URL: the requested destination if free, a duplicate marker
    /// if an identical file already sits there, or the next free ` (n)` variant.
    private static func resolvePlacement(source: URL, destination: URL) throws -> Placement {
        let fm = FileManager.default
        if !fm.fileExists(atPath: destination.path) {
            return .place(destination)
        }

        let sourceHash = ContentHash.digest(of: source)
        let stem = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        let dir = destination.deletingLastPathComponent()

        for index in 1...99 {
            let candidate = index == 1
                ? destination
                : dir.appendingPathComponent(ext.isEmpty ? "\(stem) (\(index))"
                                                          : "\(stem) (\(index)).\(ext)")
            if !fm.fileExists(atPath: candidate.path) {
                return .place(candidate)
            }
            if let sourceHash, ContentHash.digest(of: candidate) == sourceHash {
                return .duplicate(candidate)
            }
        }
        throw PathError.tooManyCollisions(destination.path)
    }

    private static func isCrossVolume(source: URL, destination: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeURLKey]
        let srcVol = (try? source.deletingLastPathComponent()
            .resourceValues(forKeys: keys))?.volume
        let dstVol = (try? destination.deletingLastPathComponent()
            .resourceValues(forKeys: keys))?.volume
        guard let srcVol, let dstVol else { return false }
        return srcVol.standardizedFileURL != dstVol.standardizedFileURL
    }
}
