import Foundation

// MARK: - Open vocabularies

/// The vocabularies below are `RawRepresentable` **structs**, not `String`
/// enums, and that is load-bearing rather than stylistic: `Decodable`
/// synthesis for a `String` enum *throws* on an unknown raw value. One
/// attribute written by a newer build would make the whole `Config`
/// undecodable, and `ConfigStore` would move the user's rules aside as
/// corrupt. A struct decodes anything, evaluates to "unknown" (the test is
/// false and the trace says why), and round-trips untouched on re-save.
public struct Attribute: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = (try? container.decode(String.self)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension Attribute {
    // Identity — derived from the URL alone, no syscall.
    static let name = Attribute("name")            // full name, with extension
    static let stem = Attribute("stem")            // name without the extension
    static let ext = Attribute("ext")              // lowercased, no dot
    static let relPath = Attribute("relpath")      // path below the watched folder
    static let parent = Attribute("parent")        // immediate folder name
    static let subfolder = Attribute("subfolder")  // relpath minus the last component
    static let depth = Attribute("depth")

    // Type and size.
    static let kind = Attribute("kind")
    static let uti = Attribute("uti")
    static let size = Attribute("size")
    static let isPackage = Attribute("isPackage")
    static let isHidden = Attribute("isHidden")

    // Dates. Five of them, because "the date" is the single most confusing
    // thing about the old engine: it silently meant the modification date.
    static let dateAdded = Attribute("dateAdded")
    static let dateCreated = Attribute("dateCreated")
    static let dateModified = Attribute("dateModified")
    static let dateOpened = Attribute("dateOpened")
    static let dateCaptured = Attribute("dateCaptured")

    // Finder and provenance.
    static let tags = Attribute("tags")
    static let label = Attribute("label")
    static let comment = Attribute("comment")
    static let whereFrom = Attribute("whereFrom")
    static let whereFromHost = Attribute("whereFromHost")
    static let isQuarantined = Attribute("isQuarantined")

    // Media and documents.
    static let pixelWidth = Attribute("pixelWidth")
    static let pixelHeight = Attribute("pixelHeight")
    static let megapixels = Attribute("megapixels")
    static let duration = Attribute("duration")
    static let pageCount = Attribute("pageCount")
    static let title = Attribute("title")
    static let authors = Attribute("authors")
    static let subjects = Attribute("subjects")
    static let publisher = Attribute("publisher")
    static let language = Attribute("language")

    // Content and probes.
    static let text = Attribute("text")
    static let contentHash = Attribute("contentHash")
    static let duplicateInTarget = Attribute("duplicateInTarget")

    // The model.
    static let modelSays = Attribute("modelSays")

    /// Editor order.
    static let all: [Attribute] = [
        .name, .stem, .ext, .relPath, .parent, .subfolder, .depth,
        .kind, .uti, .size, .isPackage, .isHidden,
        .dateAdded, .dateCreated, .dateModified, .dateOpened, .dateCaptured,
        .tags, .label, .comment, .whereFrom, .whereFromHost, .isQuarantined,
        .pixelWidth, .pixelHeight, .megapixels, .duration, .pageCount,
        .title, .authors, .subjects, .publisher, .language,
        .text, .contentHash, .duplicateInTarget, .modelSays
    ]
}

public struct Operator: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = (try? container.decode(String.self)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension Operator {
    // Strings.
    /// Named `equals` rather than `is`: a member called `is` needs backticks
    /// at every call site, and `.is` in a pattern reads like a type check.
    static let equals = Operator("is")
    static let isNot = Operator("isNot")
    static let contains = Operator("contains")
    static let notContains = Operator("notContains")
    static let beginsWith = Operator("beginsWith")
    static let endsWith = Operator("endsWith")
    static let matchesGlob = Operator("matchesGlob")
    static let notMatchesGlob = Operator("notMatchesGlob")
    static let matchesRegex = Operator("matchesRegex")
    static let notMatchesRegex = Operator("notMatchesRegex")
    static let isIn = Operator("in")
    static let notIn = Operator("notIn")
    static let isEmpty = Operator("isEmpty")
    static let isNotEmpty = Operator("isNotEmpty")

    // Numbers.
    static let eq = Operator("eq")
    static let ne = Operator("ne")
    static let gt = Operator("gt")
    static let gte = Operator("gte")
    static let lt = Operator("lt")
    static let lte = Operator("lte")
    static let between = Operator("between")

    // Dates.
    static let before = Operator("before")
    static let after = Operator("after")
    static let olderThan = Operator("olderThan")
    static let newerThan = Operator("newerThan")
    static let inLast = Operator("inLast")
    static let notInLast = Operator("notInLast")

    // Lists.
    static let containsAny = Operator("containsAny")
    static let containsAll = Operator("containsAll")
    static let containsNone = Operator("containsNone")

    // Booleans.
    static let isTrue = Operator("isTrue")
    static let isFalse = Operator("isFalse")

    // Types.
    static let conformsTo = Operator("conformsTo")

    // The model.
    static let saysYes = Operator("saysYes")
    static let saysNo = Operator("saysNo")
}

public struct ActionType: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = (try? container.decode(String.self)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension ActionType {
    /// Placement — exactly one of these ends a step.
    static let move = ActionType("move")
    static let copy = ActionType("copy")
    static let rename = ActionType("rename")
    static let sortIntoDatedFolder = ActionType("sortIntoDatedFolder")
    static let trash = ActionType("trash")
    static let quarantine = ActionType("quarantine")
    static let skip = ActionType("skip")

    /// Side effects — applied after a successful placement.
    static let addTags = ActionType("addTags")
    static let removeTags = ActionType("removeTags")
    static let setComment = ActionType("setComment")
    static let setLabel = ActionType("setLabel")
    static let notify = ActionType("notify")
    static let reveal = ActionType("reveal")
    static let open = ActionType("open")
    static let runShortcut = ActionType("runShortcut")

    /// Control flow and the model.
    static let askModel = ActionType("askModel")
    static let stop = ActionType("stop")
    /// `proceed`, not `continue`: the keyword would need backticks everywhere.
    static let proceed = ActionType("continue")

    /// What an unrecognized action decodes to: it does nothing, the validator
    /// flags it, and it survives a re-save unchanged.
    static let unknown = ActionType("")

    /// Actions that decide where the file ends up. A step may hold at most one.
    static let placements: Set<ActionType> = [
        .move, .copy, .rename, .sortIntoDatedFolder, .trash, .quarantine, .skip
    ]

    /// Actions applied to the file *after* it has been placed.
    static let sideEffects: Set<ActionType> = [
        .addTags, .removeTags, .setComment, .setLabel, .notify, .reveal, .open, .runShortcut
    ]
}

/// A coarse content kind. Resolved through `UTType` conformance for new rules
/// and through the legacy extension table for migrated ones.
public struct Kind: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = (try? container.decode(String.self)) ?? ""
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public extension Kind {
    static let image = Kind("image")
    static let video = Kind("video")
    static let audio = Kind("audio")
    static let pdf = Kind("pdf")
    static let archive = Kind("archive")
    static let text = Kind("text")
    static let ebook = Kind("ebook")
    static let document = Kind("document")
    static let spreadsheet = Kind("spreadsheet")
    static let presentation = Kind("presentation")
    static let code = Kind("code")
    static let font = Kind("font")
    static let diskImage = Kind("diskImage")
    static let package = Kind("package")
    static let other = Kind("other")

    static let all: [Kind] = [
        .image, .video, .audio, .pdf, .archive, .text, .ebook, .document,
        .spreadsheet, .presentation, .code, .font, .diskImage, .package, .other
    ]
}
