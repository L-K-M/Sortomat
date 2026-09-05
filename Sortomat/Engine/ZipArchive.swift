import Compression
import Foundation

/// A minimal, in-process ZIP reader (central-directory based, stored + deflate).
/// Replaces shelling out to `/usr/bin/unzip`, which could deadlock the pipeline
/// on a malformed archive and is a prerequisite for ever sandboxing the app
/// (PLAN Phase 1). Big enough for EPUBs; not a general-purpose zip library
/// (zip64 archives are declined rather than mis-read).
struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16          // 0 = stored, 8 = deflate
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    private let bytes: [UInt8]
    let entries: [Entry]

    /// Per-entry decompression cap — bounds memory against a hostile archive.
    static let maxEntryBytes = 16 * 1024 * 1024

    init?(url: URL, maxArchiveBytes: Int = 200 * 1024 * 1024) {
        guard let data = try? Data(contentsOf: url), data.count <= maxArchiveBytes else {
            return nil
        }
        self.bytes = [UInt8](data)
        guard let entries = Self.readCentralDirectory(bytes) else { return nil }
        self.entries = entries
    }

    /// First entry whose lowercased name ends with one of `suffixes`, preferring
    /// the shallowest (fewest path separators) — used to locate `container.xml`
    /// or the shallowest `.opf`.
    func firstEntry(withSuffixes suffixes: [String]) -> Entry? {
        entries
            .filter { entry in
                let lower = entry.name.lowercased()
                return suffixes.contains { lower.hasSuffix($0) }
            }
            .min { lhs, rhs in
                let l = (lhs.name.filter { $0 == "/" }.count, lhs.name.count)
                let r = (rhs.name.filter { $0 == "/" }.count, rhs.name.count)
                return l < r
            }
    }

    /// Case-insensitive lookup, tolerant of a leading `./`.
    func entry(named name: String) -> Entry? {
        let want = name.hasPrefix("./") ? String(name.dropFirst(2)) : name
        return entries.first { $0.name.caseInsensitiveCompare(want) == .orderedSame }
    }

    /// Decompress an entry's data, capped at `maxEntryBytes`. Returns nil for
    /// unsupported methods, oversized entries, or corrupt data. Both sizes are
    /// checked: for a stored entry the bytes returned are `compressedSize`, so
    /// a hostile central directory declaring a small uncompressed size with a
    /// huge compressed size must not bypass the cap.
    func data(for entry: Entry) -> Data? {
        guard entry.uncompressedSize <= Self.maxEntryBytes,
              entry.compressedSize <= Self.maxEntryBytes else { return nil }
        guard let dataStart = localDataOffset(for: entry) else { return nil }
        let end = dataStart + entry.compressedSize
        guard end <= bytes.count, dataStart <= end else { return nil }
        let compressed = Array(bytes[dataStart..<end])

        switch entry.method {
        case 0:
            return Data(compressed)
        case 8:
            return Self.inflate(compressed, expectedSize: entry.uncompressedSize)
        default:
            return nil
        }
    }

    // MARK: - Parsing

    private func localDataOffset(for entry: Entry) -> Int? {
        let base = entry.localHeaderOffset
        guard base + 30 <= bytes.count,
              Self.u32(bytes, base) == 0x0403_4b50 else { return nil }
        let nameLen = Int(Self.u16(bytes, base + 26))
        let extraLen = Int(Self.u16(bytes, base + 28))
        return base + 30 + nameLen + extraLen
    }

    private static func readCentralDirectory(_ bytes: [UInt8]) -> [Entry]? {
        guard let eocd = findEOCD(bytes) else { return nil }
        let count = Int(u16(bytes, eocd + 10))
        var offset = Int(u32(bytes, eocd + 16))
        // 0xFFFFFFFF signals zip64, which we don't handle.
        guard offset != 0xFFFF_FFFF, count != 0xFFFF else { return nil }

        var result: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(bytes, offset) == 0x0201_4b50 else {
                break
            }
            let method = u16(bytes, offset + 10)
            let compSize = Int(u32(bytes, offset + 20))
            let uncompSize = Int(u32(bytes, offset + 24))
            let nameLen = Int(u16(bytes, offset + 28))
            let extraLen = Int(u16(bytes, offset + 30))
            let commentLen = Int(u16(bytes, offset + 32))
            let localOffset = Int(u32(bytes, offset + 42))
            let nameStart = offset + 46
            guard nameStart + nameLen <= bytes.count else { break }
            let name = String(decoding: bytes[nameStart..<nameStart + nameLen], as: UTF8.self)
            result.append(Entry(
                name: name, method: method, compressedSize: compSize,
                uncompressedSize: uncompSize, localHeaderOffset: localOffset
            ))
            offset = nameStart + nameLen + extraLen + commentLen
        }
        return result.isEmpty ? nil : result
    }

    /// Scan backwards for the End-Of-Central-Directory signature (`PK\5\6`).
    /// A candidate only wins outright if its comment-length field reaches
    /// exactly to the end of the file — a *fake* signature embedded in the
    /// real EOCD's comment won't line up, so the scan keeps going instead of
    /// rejecting a perfectly valid archive. Archives with trailing junk (no
    /// candidate validates) fall back to the first signature found.
    private static func findEOCD(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        var i = bytes.count - 22
        let lowerBound = max(0, bytes.count - 22 - 65_536) // max comment length
        var firstSignature: Int?
        while i >= lowerBound {
            if u32(bytes, i) == 0x0605_4b50 {
                let commentLen = Int(u16(bytes, i + 20))
                if i + 22 + commentLen == bytes.count { return i }
                if firstSignature == nil { firstSignature = i }
            }
            i -= 1
        }
        return firstSignature
    }

    private static func inflate(_ input: [UInt8], expectedSize: Int) -> Data? {
        guard !input.isEmpty, expectedSize > 0 else { return nil }
        var dst = Data(count: expectedSize)
        let written = dst.withUnsafeMutableBytes { dstRaw -> Int in
            guard let dstBase = dstRaw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return input.withUnsafeBufferPointer { src -> Int in
                guard let srcBase = src.baseAddress else { return 0 }
                return compression_decode_buffer(
                    dstBase, expectedSize, srcBase, src.count, nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return written == expectedSize ? dst : dst.prefix(written)
    }

    // MARK: - Little-endian readers (bounds-checked by callers)

    private static func u16(_ b: [UInt8], _ i: Int) -> UInt16 {
        guard i + 1 < b.count else { return 0 }
        return UInt16(b[i]) | (UInt16(b[i + 1]) << 8)
    }

    private static func u32(_ b: [UInt8], _ i: Int) -> UInt32 {
        guard i + 3 < b.count else { return 0 }
        return UInt32(b[i]) | (UInt32(b[i + 1]) << 8)
            | (UInt32(b[i + 2]) << 16) | (UInt32(b[i + 3]) << 24)
    }
}
