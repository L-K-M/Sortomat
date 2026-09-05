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
/// path that verifies the copy before deleting the original.
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
            try copyCleaningUpOnFailure(source: source, to: target)
            return .placed(target)
        }

        // Foundation's `moveItem` quietly degrades to an *unverified*
        // copy-then-delete when source and destination sit on different
        // volumes — exactly the posture this app promises not to have. Detect
        // that case up front and take the verified path instead of waiting
        // for an error that normally never comes.
        if isCrossVolume(source: source, destination: target) {
            try copyVerifyDelete(source: source, to: target)
            return .placed(target)
        }

        do {
            try fm.moveItem(at: source, to: target)
        } catch {
            // A move that still fails with a cross-device error (a mount point
            // or firmlink inside the tree) gets the verified fallback; any
            // other error surfaces as-is.
            guard isCrossDeviceError(error) else { throw error }
            try copyVerifyDelete(source: source, to: target)
        }
        return .placed(target)
    }

    /// Copy `source` to `target`, removing a half-written target on failure
    /// (disk full, NAS drop) so the canonical name isn't left holding a
    /// truncated file forever. Only a target *this call created* is cleaned
    /// up: an occupant that appeared after the placement was resolved is not
    /// ours to delete — `copyItem` refuses to overwrite it, and so do we.
    static func copyCleaningUpOnFailure(source: URL, to target: URL) throws {
        let fm = FileManager.default
        let existedBefore = occupied(target)
        do {
            try fm.copyItem(at: source, to: target)
        } catch {
            if !existedBefore { try? fm.removeItem(at: target) }
            throw error
        }
    }

    /// Cross-volume path: copy, verify the copy over its *entire* content, and
    /// only then delete the original. Fails closed — when either side can't be
    /// hashed (`digest` returns nil), the copy is discarded and the original
    /// kept, because `nil == nil` must never count as a successful verification.
    static func copyVerifyDelete(source: URL, to target: URL) throws {
        let fm = FileManager.default
        try copyCleaningUpOnFailure(source: source, to: target)
        guard let sourceDigest = treeDigest(of: source),
              let targetDigest = treeDigest(of: target),
              sourceDigest == targetDigest
        else {
            try? fm.removeItem(at: target)
            throw MoveError.verifyFailed
        }
        try fm.removeItem(at: source)
    }

    /// Full-content digest of a file — or, for a package, of every file inside
    /// it keyed by relative path, so a document bundle is verified as a whole
    /// before its original is deleted. Nil when anything can't be read.
    static func treeDigest(of root: URL) -> String? {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory) else { return nil }
        if !isDirectory.boolValue { return ContentHash.digest(of: root, limit: .max) }
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: []) else {
            return nil
        }
        let base = root.standardizedFileURL.path
        var lines: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let digest = ContentHash.digest(of: url, limit: .max) else { return nil }
            lines.append(String(url.standardizedFileURL.path.dropFirst(base.count)) + "|" + digest)
        }
        lines.sort()
        return ContentHash.digest(ofString: lines.joined(separator: "\n"))
    }

    private enum Placement {
        case place(URL)
        case duplicate(URL)
    }

    /// Decide the final URL: the requested destination if free, a duplicate marker
    /// if an identical file already sits there, or the next free ` (n)` variant.
    private static func resolvePlacement(source: URL, destination: URL) throws -> Placement {
        if !occupied(destination) {
            return .place(destination)
        }

        // Nil for a package: a directory has no prefix digest, so the
        // comparison below goes straight to the whole-tree digest.
        let sourcePrefix = ContentHash.digest(of: source)
        let stem = destination.deletingPathExtension().lastPathComponent
        let ext = destination.pathExtension
        let dir = destination.deletingLastPathComponent()

        for index in 1...99 {
            let candidate = index == 1
                ? destination
                : dir.appendingPathComponent(ext.isEmpty ? "\(stem) (\(index))"
                                                          : "\(stem) (\(index)).\(ext)")
            if !occupied(candidate) {
                return .place(candidate)
            }
            if isDuplicate(candidate, of: source, prefixDigest: sourcePrefix) {
                return .duplicate(candidate)
            }
        }
        throw PathError.tooManyCollisions(destination.path)
    }

    /// Whether two items are byte-for-byte the same — for a package, every file
    /// inside it. The bounded prefix digest (size + first 4 MiB) is the cheap
    /// pre-filter that excludes almost everything for one small read; only an
    /// item that survives it is read in full. A prefix match alone is not
    /// enough: calling a distinct file a duplicate records it as done and it is
    /// then never filed again — a silent loss, and exactly the trade-off the
    /// bounded hash was never meant to make. A package has no prefix digest
    /// (it is a directory), so it goes straight to the full comparison. Fails
    /// closed: an unreadable side is never a duplicate, so the item gets a
    /// ` (n)` suffix instead of disappearing from the queue.
    private static func isDuplicate(_ candidate: URL, of source: URL, prefixDigest: String?) -> Bool {
        if let prefixDigest, ContentHash.digest(of: candidate) != prefixDigest { return false }
        guard let full = treeDigest(of: source), treeDigest(of: candidate) == full else { return false }
        return true
    }

    /// Whether *anything* sits at this path. `fileExists` follows symlinks, so
    /// a dangling link answered "free" — and the subsequent move threw, every
    /// scan, forever. `attributesOfItem` has lstat semantics: the link itself
    /// counts, so a dangling link gets a ` (n)` suffix like any other occupant.
    static func occupied(_ url: URL) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: url.path)) != nil
    }

    static func isCrossVolume(source: URL, destination: URL) -> Bool {
        let keys: Set<URLResourceKey> = [.volumeURLKey]
        let srcVol = (try? source.deletingLastPathComponent()
            .resourceValues(forKeys: keys))?.volume
        let dstVol = (try? destination.deletingLastPathComponent()
            .resourceValues(forKeys: keys))?.volume
        guard let srcVol, let dstVol else { return false }
        return srcVol.standardizedFileURL != dstVol.standardizedFileURL
    }

    private static func isCrossDeviceError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EXDEV) { return true }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            return isCrossDeviceError(underlying)
        }
        return false
    }
}
