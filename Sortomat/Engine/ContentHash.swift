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
    static func digest(of url: URL, limit: Int = 4 * 1024 * 1024) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        var remaining = limit
        while remaining > 0 {
            let chunk = (try? handle.read(upToCount: min(remaining, 1 << 16))) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
            remaining -= chunk.count
        }
        // fstat on the handle we just read from: it describes exactly the file
        // whose bytes went into the hasher. `attributesOfItem` would describe
        // whatever the path names — for a symlink, the link itself — so the
        // digest mixed a target's content with a link's 100-odd bytes and a
        // link hashed differently from the file it points at.
        var info = stat()
        let size: Int64 = fstat(handle.fileDescriptor, &info) == 0 ? Int64(info.st_size) : -1
        var sizeLE = size.littleEndian
        hasher.update(data: Data(bytes: &sizeLE, count: MemoryLayout<Int64>.size))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
