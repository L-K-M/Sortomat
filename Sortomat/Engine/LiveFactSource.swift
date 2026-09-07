import CoreServices
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// The fact source that actually reads the disk. Every tier is loaded at most
/// once, and only when a condition asks for it — a rule that never mentions
/// contents never opens the file.
struct LiveFactSource: FactSource {
    let url: URL
    /// The rule's target folder, for `duplicateInTarget`.
    let targetPath: String
    /// Shared across one scan pass, so a target folder is enumerated once.
    let targetIndex: TargetIndex?

    init(url: URL, targetPath: String = "", targetIndex: TargetIndex? = nil) {
        self.url = url
        self.targetPath = targetPath
        self.targetIndex = targetIndex
    }

    // MARK: - stat

    func statFacts() -> StatFacts {
        let keys: Set<URLResourceKey> = [
            .fileSizeKey, .totalFileSizeKey, .isPackageKey, .isHiddenKey, .contentTypeKey,
            .addedToDirectoryDateKey, .creationDateKey, .contentModificationDateKey,
            .tagNamesKey, .labelNumberKey
        ]
        guard let values = try? url.resourceValues(forKeys: keys) else { return StatFacts() }
        // A package's own "file size" is the folder record's, not the
        // document's, so a size condition has to add up what is inside.
        let size = values.isPackage == true
            ? LiveFactSource.packageBytes(url)
            : values.fileSize.map { Double($0) }
        return StatFacts(
            size: size,
            isPackage: values.isPackage,
            isHidden: values.isHidden,
            uti: values.contentType?.identifier,
            dateAdded: values.addedToDirectoryDate,
            dateCreated: values.creationDate,
            dateModified: values.contentModificationDate,
            tags: values.tagNames,
            label: values.labelNumber.map { Double($0) }
        )
    }

    static func packageBytes(_ url: URL) -> Double? {
        // A box rather than a captured `var`: the error handler is an escaping
        // closure and is `@Sendable` on some SDKs, where mutating a captured
        // local is an error rather than a warning.
        final class Walk { var failed = false }
        let walk = Walk()
        var bytes = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey], options: [],
            errorHandler: { _, _ in walk.failed = true; return true }
        ) else { return nil }
        for case let child as URL in enumerator {
            bytes += (try? child.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        }
        // A half-read package is not a small package. Reporting the bytes we
        // happened to reach would quietly answer "under 5 MB" for a bundle
        // whose unreadable half is a gigabyte.
        return walk.failed ? nil : Double(bytes)
    }

    // MARK: - Spotlight

    func metadataFacts() -> MetadataFacts {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else {
            return MetadataFacts()
        }
        func string(_ key: CFString) -> String? {
            let value = MDItemCopyAttribute(item, key)
            if let text = value as? String, !text.isEmpty { return text }
            if let list = value as? [String], !list.isEmpty { return list.joined(separator: ", ") }
            return nil
        }
        func strings(_ key: CFString) -> [String]? {
            let value = MDItemCopyAttribute(item, key)
            if let list = value as? [String], !list.isEmpty { return list }
            if let text = value as? String, !text.isEmpty { return [text] }
            return nil
        }
        func number(_ key: CFString) -> Double? {
            (MDItemCopyAttribute(item, key) as? NSNumber)?.doubleValue
        }
        func date(_ key: CFString) -> Date? {
            MDItemCopyAttribute(item, key) as? Date
        }

        return MetadataFacts(
            dateOpened: date(kMDItemLastUsedDate),
            comment: string(kMDItemFinderComment),
            whereFrom: strings(kMDItemWhereFroms),
            // Reading the quarantine xattr needs `getxattr`; until that is
            // wired the attribute is honestly unavailable rather than wrong.
            isQuarantined: nil,
            duration: number(kMDItemDurationSeconds),
            pageCount: number(kMDItemNumberOfPages),
            title: string(kMDItemTitle),
            authors: strings(kMDItemAuthors),
            subjects: strings(kMDItemKeywords),
            language: string(kMDItemLanguages)
        )
    }

    // MARK: - Headers

    func headerFacts() -> HeaderFacts {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            guard let document = PDFDocument(url: url) else { return HeaderFacts() }
            let created = document.documentAttributes?[PDFDocumentAttribute.creationDateAttribute] as? Date
            return HeaderFacts(dateCaptured: created, pageCount: Double(document.pageCount))
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any]
        else { return HeaderFacts() }

        let width = (properties[kCGImagePropertyPixelWidth as String] as? NSNumber)?.doubleValue
        let height = (properties[kCGImagePropertyPixelHeight as String] as? NSNumber)?.doubleValue
        var captured: Date?
        if let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any],
           let taken = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String {
            captured = TemplateDates.exifDate(taken)
        }
        if captured == nil,
           let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any],
           let stamped = tiff[kCGImagePropertyTIFFDateTime as String] as? String {
            captured = TemplateDates.exifDate(stamped)
        }
        return HeaderFacts(pixelWidth: width, pixelHeight: height, dateCaptured: captured)
    }

    // MARK: - Content

    func contentFacts() -> ContentFacts {
        let sample = FileContext.extractSample(url: url)
        let text = sample.text.isEmpty ? nil : sample.text
        return ContentFacts(text: text, contentHash: ContentHash.digest(of: url))
    }

    // MARK: - Kind

    func kind() -> Kind? {
        let ext = url.pathExtension.lowercased()
        let identifier = (try? url.resourceValues(forKeys: [.contentTypeKey]))?
            .contentType?.identifier
        if let resolved = KindResolver.kind(forUTI: identifier) { return resolved }
        if let resolved = KindResolver.kind(forExtension: ext) { return resolved }
        // Only a file with no extension is worth sniffing: for everything else
        // Launch Services and the table have already had their say.
        guard ext.isEmpty, let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: MagicBytes.probeLength) else { return nil }
        return MagicBytes.kind(sniffing: header)
    }

    func isDuplicateInTarget() -> Bool {
        guard let targetIndex else { return false }
        return targetIndex.contains(url)
    }
}

/// "Is this file already filed?" — answered by enumerating the target folder
/// once per pass and hashing only the files whose *size* matches a candidate,
/// so a target with fifty thousand files costs one enumeration and almost no
/// hashing.
final class TargetIndex {
    private let root: URL
    private var sizes: [Int64: [URL]]?
    private var digests: [URL: String] = [:]

    init(root: URL) {
        self.root = root
    }

    func contains(_ url: URL) -> Bool {
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              let candidates = index()[Int64(size)], !candidates.isEmpty,
              let digest = ContentHash.digest(of: url, limit: .max) else { return false }
        for candidate in candidates where candidate != url {
            if digestOf(candidate) == digest { return true }
        }
        return false
    }

    private func digestOf(_ url: URL) -> String? {
        if let cached = digests[url] { return cached }
        guard let digest = ContentHash.digest(of: url, limit: .max) else { return nil }
        digests[url] = digest
        return digest
    }

    private func index() -> [Int64: [URL]] {
        if let sizes { return sizes }
        var built: [Int64: [URL]] = [:]
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        if let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard let values = try? url.resourceValues(forKeys: Set(keys)),
                      values.isRegularFile == true, let size = values.fileSize else { continue }
                built[Int64(size), default: []].append(url)
            }
        }
        sizes = built
        return built
    }
}
