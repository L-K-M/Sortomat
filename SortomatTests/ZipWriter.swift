import Compression
import Foundation

/// A minimal ZIP writer (stored or deflated entries), used only by tests to
/// build fixture EPUBs/archives so the reader can be exercised without
/// shelling out. CRC fields are left zero — `ZipArchive` doesn't verify them.
struct ZipWriter {
    private struct Item {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let offset: Int
    }

    private var items: [Item] = []
    private var buffer = Data()

    mutating func add(_ name: String, _ contents: Data, deflate: Bool = false) {
        // `compression_encode_buffer` answers 0 both for "the output didn't
        // fit" and for an outright failure. Emitting that as a deflate entry
        // writes an archive whose payload is empty, and the test then fails for
        // a reason that has nothing to do with the reader under test — so fall
        // back to storing the bytes instead.
        var payload = contents
        var method: UInt16 = 0
        if deflate, !contents.isEmpty {
            let compressed = Self.deflate(contents)
            if !compressed.isEmpty {
                payload = compressed
                method = 8
            }
        }
        let offset = buffer.count
        var header = Data()
        header.le32(0x0403_4b50)   // local file header signature
        header.le16(20)            // version needed
        header.le16(0)             // flags
        header.le16(method)        // method: stored or deflate
        header.le16(0)             // mod time
        header.le16(0)             // mod date
        header.le32(0)             // crc-32 (unchecked)
        header.le32(UInt32(payload.count))  // compressed size
        header.le32(UInt32(contents.count)) // uncompressed size
        let nameBytes = Array(name.utf8)
        header.le16(UInt16(nameBytes.count))
        header.le16(0)             // extra length
        header.append(contentsOf: nameBytes)
        buffer.append(header)
        buffer.append(payload)
        items.append(Item(name: name, method: method, compressedSize: payload.count,
                          uncompressedSize: contents.count, offset: offset))
    }

    mutating func add(_ name: String, _ text: String) {
        add(name, Data(text.utf8))
    }

    func data() -> Data {
        var out = buffer
        let cdStart = out.count
        for item in items {
            var entry = Data()
            entry.le32(0x0201_4b50) // central directory signature
            entry.le16(20)          // version made by
            entry.le16(20)          // version needed
            entry.le16(0)           // flags
            entry.le16(item.method)
            entry.le16(0)           // mod time
            entry.le16(0)           // mod date
            entry.le32(0)           // crc-32
            entry.le32(UInt32(item.compressedSize))
            entry.le32(UInt32(item.uncompressedSize))
            let nameBytes = Array(item.name.utf8)
            entry.le16(UInt16(nameBytes.count))
            entry.le16(0)           // extra
            entry.le16(0)           // comment
            entry.le16(0)           // disk number
            entry.le16(0)           // internal attrs
            entry.le32(0)           // external attrs
            entry.le32(UInt32(item.offset))
            entry.append(contentsOf: nameBytes)
            out.append(entry)
        }
        let cdSize = out.count - cdStart

        var eocd = Data()
        eocd.le32(0x0605_4b50)      // end of central directory signature
        eocd.le16(0)                // disk number
        eocd.le16(0)                // cd start disk
        eocd.le16(UInt16(items.count))
        eocd.le16(UInt16(items.count))
        eocd.le32(UInt32(cdSize))
        eocd.le32(UInt32(cdStart))
        eocd.le16(0)                // comment length
        out.append(eocd)
        return out
    }

    /// Raw deflate (what zip method 8 stores) via the Compression framework —
    /// `COMPRESSION_ZLIB` there means deflate without the zlib header, the
    /// same format `ZipArchive.inflate` decodes.
    static func deflate(_ data: Data) -> Data {
        guard !data.isEmpty else { return data }
        // Deflate wraps incompressible input in stored blocks of at most 64 KiB,
        // each costing five bytes of header — so the output can exceed the
        // input, and a fixed 1 KiB of slack is not enough for a large fixture.
        let capacity = data.count + data.count / 64 + 1024
        var dst = Data(count: capacity)
        let written = dst.withUnsafeMutableBytes { dstRaw -> Int in
            guard let dstBase = dstRaw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { srcRaw -> Int in
                guard let srcBase = srcRaw.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        return dst.prefix(written)
    }
}

private extension Data {
    mutating func le16(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }
    mutating func le32(_ value: UInt32) {
        le16(UInt16(value & 0xffff))
        le16(UInt16((value >> 16) & 0xffff))
    }
}
