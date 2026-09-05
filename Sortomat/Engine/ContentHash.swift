import CryptoKit
import Foundation

/// Streaming content hashing, used for real duplicate detection (two different
/// files that happen to share a byte count must not be treated as duplicates —
/// PLAN Phase 1). Hashes only a bounded prefix by default so very large media
/// files don't force a full read on every scan.
enum ContentHash {
    /// Hash up to `limit` bytes of the file (plus its exact size), returning a
    /// hex digest, or nil if the file can't be read. Size is folded in so two
    /// files sharing a prefix but differing in length still hash differently.
    ///
    /// Fails closed: a read error *mid-file* yields nil, never a valid-looking
    /// digest of whatever prefix happened to arrive. Three guards rest on that
    /// contract — the cross-volume verify, dedup, and the copy-undo divergence
    /// check — and a NAS dropping mid-read used to satisfy all three with a
    /// digest of zero bytes.
    static func digest(of url: URL, limit: Int = 4 * 1024 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var remaining = limit
        do {
            while remaining > 0 {
                guard let chunk = try handle.read(upToCount: min(remaining, 1 << 16)),
                      !chunk.isEmpty else { break }
                hasher.update(data: chunk)
                remaining -= chunk.count
            }
        } catch {
            return nil
        }
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int64
        else { return nil }
        var sizeLE = size.littleEndian
        hasher.update(data: Data(bytes: &sizeLE, count: MemoryLayout<Int64>.size))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
