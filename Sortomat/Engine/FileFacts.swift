import Foundation

/// One value the engine may know about a file.
enum FactValue: Equatable {
    case string(String)
    case strings([String])
    case number(Double)
    case date(Date)
    case bool(Bool)
    case kind(Kind)

    /// The trace rendering: short, and never the whole extracted document.
    func display(limit: Int = 200) -> String {
        switch self {
        case .string(let value):
            return value.count > limit ? String(value.prefix(limit)) + "…" : value
        case .strings(let values): return values.joined(separator: ", ")
        case .number(let value): return NumberText.canonical(value)
        case .date(let value):
            return TemplateDates.string(value, format: "yyyy-MM-dd HH:mm", timeZone: .current)
        case .bool(let value): return value ? "true" : "false"
        case .kind(let value): return value.rawValue
        }
    }
}

/// How much a fact costs to obtain. The evaluator uses this to order the
/// conditions inside a group, so a free name test rejects a file before an
/// OCR pass is ever considered.
enum FactCost: Int, Comparable {
    case free = 0        // derived from the URL alone
    case stat = 1        // one batched resourceValues call
    case metadata = 2    // Spotlight or an extended attribute
    case header = 3      // image properties, PDF page count
    case content = 4     // full text extraction, including OCR
    case probe = 5       // touches the target folder
    case model = 6       // a paid call — never inside evaluate()

    static func < (lhs: FactCost, rhs: FactCost) -> Bool { lhs.rawValue < rhs.rawValue }

    var name: String {
        switch self {
        case .free: return "free"
        case .stat: return "stat"
        case .metadata: return "metadata"
        case .header: return "header"
        case .content: return "content"
        case .probe: return "probe"
        case .model: return "model"
        }
    }
}

/// Why a fact was not available. Kept distinct from "the test failed", because
/// "this photo has no capture date" and "this photo was taken in 2019" are
/// different answers to "why didn't my rule fire".
enum FactLookup: Equatable {
    case available(FactValue)
    case unavailable
    case blockedByPrivacy
    case tooExpensive
    case unknownAttribute
    case needsModel
}

// MARK: - Tiers

struct StatFacts: Equatable {
    var size: Double?
    var isPackage: Bool?
    var isHidden: Bool?
    var uti: String?
    var dateAdded: Date?
    var dateCreated: Date?
    var dateModified: Date?
    var tags: [String]?
    var label: Double?

    init(size: Double? = nil, isPackage: Bool? = nil, isHidden: Bool? = nil,
         uti: String? = nil, dateAdded: Date? = nil, dateCreated: Date? = nil,
         dateModified: Date? = nil, tags: [String]? = nil, label: Double? = nil) {
        self.size = size
        self.isPackage = isPackage
        self.isHidden = isHidden
        self.uti = uti
        self.dateAdded = dateAdded
        self.dateCreated = dateCreated
        self.dateModified = dateModified
        self.tags = tags
        self.label = label
    }
}

struct MetadataFacts: Equatable {
    var dateOpened: Date?
    var comment: String?
    var whereFrom: [String]?
    var isQuarantined: Bool?
    var duration: Double?
    var pageCount: Double?
    var title: String?
    var authors: [String]?
    var subjects: [String]?
    var language: String?

    init(dateOpened: Date? = nil, comment: String? = nil, whereFrom: [String]? = nil,
         isQuarantined: Bool? = nil, duration: Double? = nil, pageCount: Double? = nil,
         title: String? = nil, authors: [String]? = nil, subjects: [String]? = nil,
         language: String? = nil) {
        self.dateOpened = dateOpened
        self.comment = comment
        self.whereFrom = whereFrom
        self.isQuarantined = isQuarantined
        self.duration = duration
        self.pageCount = pageCount
        self.title = title
        self.authors = authors
        self.subjects = subjects
        self.language = language
    }
}

struct HeaderFacts: Equatable {
    var pixelWidth: Double?
    var pixelHeight: Double?
    var dateCaptured: Date?
    var pageCount: Double?
    var tooLarge: Bool

    init(pixelWidth: Double? = nil, pixelHeight: Double? = nil, dateCaptured: Date? = nil,
         pageCount: Double? = nil, tooLarge: Bool = false) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.dateCaptured = dateCaptured
        self.pageCount = pageCount
        self.tooLarge = tooLarge
    }
}

struct ContentFacts: Equatable {
    var text: String?
    var title: String?
    var authors: [String]?
    var subjects: [String]?
    var publisher: String?
    var language: String?
    var contentHash: String?
    var tooLarge: Bool

    init(text: String? = nil, title: String? = nil, authors: [String]? = nil,
         subjects: [String]? = nil, publisher: String? = nil, language: String? = nil,
         contentHash: String? = nil, tooLarge: Bool = false) {
        self.text = text
        self.title = title
        self.authors = authors
        self.subjects = subjects
        self.publisher = publisher
        self.language = language
        self.contentHash = contentHash
        self.tooLarge = tooLarge
    }
}

/// Where facts come from. The pipeline hands in a source that reads the disk;
/// tests hand in a stub, which is what makes the whole engine testable with no
/// file system at all — and what makes "test this rule against a file" free.
protocol FactSource {
    func statFacts() -> StatFacts
    func metadataFacts() -> MetadataFacts
    func headerFacts() -> HeaderFacts
    func contentFacts() -> ContentFacts
    func kind() -> Kind?
    func isDuplicateInTarget() -> Bool
}

/// A source that knows nothing. Useful on its own for name-only evaluation
/// (the editor's "imagine a file called…") and as a base for test stubs.
struct EmptyFactSource: FactSource {
    func statFacts() -> StatFacts { StatFacts() }
    func metadataFacts() -> MetadataFacts { MetadataFacts() }
    func headerFacts() -> HeaderFacts { HeaderFacts() }
    func contentFacts() -> ContentFacts { ContentFacts() }
    func kind() -> Kind? { nil }
    func isDuplicateInTarget() -> Bool { false }
}

// MARK: - The cache

/// Everything the engine may know about one file, computed at most once and
/// only when a condition actually asks. A rule that never mentions contents
/// never opens the file.
final class FileFacts {
    enum ContentPolicy { case allowed, blocked }

    let url: URL
    let watchRoot: URL
    let now: Date
    let contentPolicy: ContentPolicy

    private let source: FactSource
    private var statCache: StatFacts?
    private var metadataCache: MetadataFacts?
    private var headerCache: HeaderFacts?
    private var contentCache: ContentFacts?
    private var kindCache: Kind??
    private var duplicateCache: Bool?

    init(url: URL, watchRoot: URL, now: Date = Date(),
         source: FactSource = EmptyFactSource(),
         contentPolicy: ContentPolicy = .allowed) {
        self.url = url
        self.watchRoot = watchRoot
        self.now = now
        self.source = source
        self.contentPolicy = contentPolicy
    }

    // MARK: Free tier

    var name: String { url.lastPathComponent }
    var stem: String { url.deletingPathExtension().lastPathComponent }
    var ext: String { url.pathExtension.lowercased() }
    var parent: String { url.deletingLastPathComponent().lastPathComponent }

    /// The path below the watched folder — `Invoices/2026/x.pdf`. Falls back to
    /// the file name when the file is not under the root at all.
    var relativePath: String {
        let base = watchRoot.standardizedFileURL.path
        let full = url.standardizedFileURL.path
        if full.hasPrefix(base + "/") { return String(full.dropFirst(base.count + 1)) }
        return name
    }

    var subfolder: String {
        let relative = relativePath
        guard let slash = relative.lastIndex(of: "/") else { return "" }
        return String(relative[relative.startIndex..<slash])
    }

    var depth: Double {
        let folder = subfolder
        return folder.isEmpty ? 0 : Double(folder.split(separator: "/").count)
    }

    // MARK: Lazy tiers

    private func stat() -> StatFacts {
        if let statCache { return statCache }
        let facts = source.statFacts()
        statCache = facts
        return facts
    }

    private func metadata() -> MetadataFacts {
        if let metadataCache { return metadataCache }
        let facts = source.metadataFacts()
        metadataCache = facts
        return facts
    }

    private func header() -> HeaderFacts {
        if let headerCache { return headerCache }
        let facts = source.headerFacts()
        headerCache = facts
        return facts
    }

    private func content() -> ContentFacts? {
        guard contentPolicy == .allowed else { return nil }
        if let contentCache { return contentCache }
        let facts = source.contentFacts()
        contentCache = facts
        return facts
    }

    private func resolvedKind() -> Kind? {
        if let kindCache { return kindCache }
        let value = source.kind()
        kindCache = .some(value)
        return value
    }

    private func duplicateInTarget() -> Bool {
        if let duplicateCache { return duplicateCache }
        let value = source.isDuplicateInTarget()
        duplicateCache = value
        return value
    }

    // MARK: Lookup

    func cost(of attribute: Attribute) -> FactCost { Self.cost(of: attribute) }

    /// Static because the answer is a property of the attribute, not of the
    /// file: the validator has to know what a condition would cost before
    /// there is any file to ask about.
    static func cost(of attribute: Attribute) -> FactCost {
        switch attribute {
        case .name, .stem, .ext, .relPath, .parent, .subfolder, .depth:
            return .free
        case .size, .isPackage, .isHidden, .uti, .kind,
             .dateAdded, .dateCreated, .dateModified, .tags, .label:
            return .stat
        case .dateOpened, .comment, .whereFrom, .whereFromHost, .isQuarantined,
             .duration, .pageCount:
            return .metadata
        case .pixelWidth, .pixelHeight, .megapixels, .dateCaptured:
            return .header
        case .title, .authors, .subjects, .publisher, .language, .text:
            return .content
        case .contentHash, .duplicateInTarget:
            return .probe
        case .modelSays:
            return .model
        default:
            return .free
        }
    }

    /// The one entry point. Never throws, never blocks on the model, and
    /// distinguishes "no such fact for this file" from "this rule is not
    /// allowed to look".
    func lookup(_ attribute: Attribute) -> FactLookup {
        switch attribute {
        case .name: return .available(.string(name))
        case .stem: return .available(.string(stem))
        case .ext: return .available(.string(ext))
        case .relPath: return .available(.string(relativePath))
        case .parent: return .available(.string(parent))
        case .subfolder: return .available(.string(subfolder))
        case .depth: return .available(.number(depth))

        case .size: return wrap(stat().size.map { FactValue.number($0) })
        case .isPackage: return wrap(stat().isPackage.map { FactValue.bool($0) })
        case .isHidden: return wrap(stat().isHidden.map { FactValue.bool($0) })
        case .uti: return wrap(stat().uti.map { FactValue.string($0) })
        case .kind: return wrap(resolvedKind().map { FactValue.kind($0) })
        case .dateAdded: return wrap(stat().dateAdded.map { FactValue.date($0) })
        case .dateCreated: return wrap(stat().dateCreated.map { FactValue.date($0) })
        case .dateModified: return wrap(stat().dateModified.map { FactValue.date($0) })
        case .tags: return wrap(stat().tags.map { FactValue.strings($0) })
        case .label: return wrap(stat().label.map { FactValue.number($0) })

        case .dateOpened: return wrap(metadata().dateOpened.map { FactValue.date($0) })
        case .comment: return wrap(metadata().comment.map { FactValue.string($0) })
        case .whereFrom:
            return wrap(metadata().whereFrom.map { FactValue.string($0.joined(separator: "\n")) })
        case .whereFromHost:
            let host = metadata().whereFrom?.compactMap { URLComponents(string: $0)?.host }.first
            return wrap(host.map { FactValue.string($0) })
        case .isQuarantined: return wrap(metadata().isQuarantined.map { FactValue.bool($0) })
        case .duration: return wrap(metadata().duration.map { FactValue.number($0) })
        case .pageCount:
            if let pages = metadata().pageCount { return .available(.number(pages)) }
            return wrap(header().pageCount.map { FactValue.number($0) })

        case .pixelWidth: return headerValue(header().pixelWidth.map { FactValue.number($0) })
        case .pixelHeight: return headerValue(header().pixelHeight.map { FactValue.number($0) })
        case .megapixels:
            let facts = header()
            guard let width = facts.pixelWidth, let height = facts.pixelHeight else {
                return headerValue(nil)
            }
            return .available(.number((width * height / 1_000_000 * 100).rounded() / 100))
        case .dateCaptured: return headerValue(header().dateCaptured.map { FactValue.date($0) })

        case .title:
            if let title = metadata().title { return .available(.string(title)) }
            return contentValue { $0.title.map { FactValue.string($0) } }
        case .authors:
            if let authors = metadata().authors { return .available(.strings(authors)) }
            return contentValue { $0.authors.map { FactValue.strings($0) } }
        case .subjects:
            if let subjects = metadata().subjects { return .available(.strings(subjects)) }
            return contentValue { $0.subjects.map { FactValue.strings($0) } }
        case .language:
            if let language = metadata().language { return .available(.string(language)) }
            return contentValue { $0.language.map { FactValue.string($0) } }
        case .publisher:
            return contentValue { $0.publisher.map { FactValue.string($0) } }
        case .text:
            return contentValue { $0.text.map { FactValue.string($0) } }
        case .contentHash:
            return contentValue { $0.contentHash.map { FactValue.string($0) } }

        case .duplicateInTarget: return .available(.bool(duplicateInTarget()))
        case .modelSays: return .needsModel

        default: return .unknownAttribute
        }
    }

    private func wrap(_ value: FactValue?) -> FactLookup {
        value.map { FactLookup.available($0) } ?? .unavailable
    }

    private func headerValue(_ value: FactValue?) -> FactLookup {
        if let value { return .available(value) }
        return header().tooLarge ? .tooExpensive : .unavailable
    }

    private func contentValue(_ pick: (ContentFacts) -> FactValue?) -> FactLookup {
        guard let facts = content() else { return .blockedByPrivacy }
        if let value = pick(facts) { return .available(value) }
        return facts.tooLarge ? .tooExpensive : .unavailable
    }
}
