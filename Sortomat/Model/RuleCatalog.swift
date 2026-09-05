import Foundation

/// Pure data the rule editor renders. There is no `switch` over attributes
/// anywhere in the UI, so adding one is a single line here.
///
/// Labels live in this file rather than in `L10n` on purpose: they are a
/// closed, mechanical vocabulary that grows with the engine, and keeping them
/// out of the main table keeps the key-parity test about *prose*.
enum RuleCatalog {
    enum ValueShape {
        /// No value at all: `isEmpty`, `isTrue`, …
        case none
        case text
        case number
        case duration
        case date
        case list
        case kind
    }

    struct AttributeSpec {
        let attribute: Attribute
        let shape: ValueShape
        let operators: [Operator]
        let example: String
        /// True for the facts a metadata-only rule is not allowed to read.
        let needsContent: Bool
    }

    // MARK: - Operator sets

    static let stringOperators: [Operator] = [
        .contains, .notContains, .equals, .isNot, .beginsWith, .endsWith,
        .matchesGlob, .notMatchesGlob, .matchesRegex, .notMatchesRegex,
        .isIn, .notIn, .isEmpty, .isNotEmpty
    ]
    static let numberOperators: [Operator] = [.eq, .ne, .gt, .gte, .lt, .lte, .between]
    static let dateOperators: [Operator] = [
        .olderThan, .newerThan, .before, .after, .isEmpty, .isNotEmpty
    ]
    static let listOperators: [Operator] = [
        .contains, .notContains, .containsAny, .containsAll, .containsNone, .isEmpty, .isNotEmpty
    ]
    static let boolOperators: [Operator] = [.isTrue, .isFalse]
    static let kindOperators: [Operator] = [.equals, .isNot, .isIn, .notIn]

    // MARK: - Attributes

    static let attributes: [AttributeSpec] = [
        AttributeSpec(attribute: .name, shape: .text, operators: stringOperators,
                      example: "Rechnung*.pdf", needsContent: false),
        AttributeSpec(attribute: .stem, shape: .text, operators: stringOperators,
                      example: "Rechnung ACME", needsContent: false),
        AttributeSpec(attribute: .ext, shape: .text, operators: stringOperators,
                      example: "pdf", needsContent: false),
        AttributeSpec(attribute: .kind, shape: .kind, operators: kindOperators,
                      example: "image", needsContent: false),
        AttributeSpec(attribute: .size, shape: .number, operators: numberOperators,
                      example: "5MB", needsContent: false),
        AttributeSpec(attribute: .dateAdded, shape: .duration, operators: dateOperators,
                      example: "30d", needsContent: false),
        AttributeSpec(attribute: .dateCreated, shape: .duration, operators: dateOperators,
                      example: "1y", needsContent: false),
        AttributeSpec(attribute: .dateModified, shape: .duration, operators: dateOperators,
                      example: "30d", needsContent: false),
        AttributeSpec(attribute: .dateOpened, shape: .duration, operators: dateOperators,
                      example: "6mo", needsContent: false),
        AttributeSpec(attribute: .dateCaptured, shape: .duration, operators: dateOperators,
                      example: "2y", needsContent: false),
        AttributeSpec(attribute: .relPath, shape: .text, operators: stringOperators,
                      example: "Invoices/*", needsContent: false),
        AttributeSpec(attribute: .parent, shape: .text, operators: stringOperators,
                      example: "Downloads", needsContent: false),
        AttributeSpec(attribute: .subfolder, shape: .text, operators: stringOperators,
                      example: "2026/Q1", needsContent: false),
        AttributeSpec(attribute: .depth, shape: .number, operators: numberOperators,
                      example: "2", needsContent: false),
        AttributeSpec(attribute: .uti, shape: .text, operators: [.equals, .isNot, .conformsTo],
                      example: "public.image", needsContent: false),
        AttributeSpec(attribute: .isPackage, shape: .none, operators: boolOperators,
                      example: "", needsContent: false),
        AttributeSpec(attribute: .isHidden, shape: .none, operators: boolOperators,
                      example: "", needsContent: false),
        AttributeSpec(attribute: .tags, shape: .list, operators: listOperators,
                      example: "Wichtig", needsContent: false),
        AttributeSpec(attribute: .label, shape: .number, operators: numberOperators,
                      example: "3", needsContent: false),
        AttributeSpec(attribute: .comment, shape: .text, operators: stringOperators,
                      example: "Steuer", needsContent: false),
        AttributeSpec(attribute: .whereFrom, shape: .text, operators: stringOperators,
                      example: "amazon.de", needsContent: false),
        AttributeSpec(attribute: .whereFromHost, shape: .text, operators: stringOperators,
                      example: "amazon.de", needsContent: false),
        AttributeSpec(attribute: .pixelWidth, shape: .number, operators: numberOperators,
                      example: "1920", needsContent: false),
        AttributeSpec(attribute: .pixelHeight, shape: .number, operators: numberOperators,
                      example: "1080", needsContent: false),
        AttributeSpec(attribute: .megapixels, shape: .number, operators: numberOperators,
                      example: "12", needsContent: false),
        AttributeSpec(attribute: .duration, shape: .number, operators: numberOperators,
                      example: "600", needsContent: false),
        AttributeSpec(attribute: .pageCount, shape: .number, operators: numberOperators,
                      example: "10", needsContent: false),
        AttributeSpec(attribute: .title, shape: .text, operators: stringOperators,
                      example: "Der Hobbit", needsContent: true),
        AttributeSpec(attribute: .authors, shape: .list, operators: listOperators,
                      example: "Tolkien", needsContent: true),
        AttributeSpec(attribute: .subjects, shape: .list, operators: listOperators,
                      example: "Fantasy", needsContent: true),
        AttributeSpec(attribute: .publisher, shape: .text, operators: stringOperators,
                      example: "Klett-Cotta", needsContent: true),
        AttributeSpec(attribute: .language, shape: .text, operators: stringOperators,
                      example: "de", needsContent: true),
        AttributeSpec(attribute: .text, shape: .text, operators: stringOperators,
                      example: "Rechnungsnummer", needsContent: true),
        AttributeSpec(attribute: .duplicateInTarget, shape: .none, operators: boolOperators,
                      example: "", needsContent: false)
    ]

    static func spec(for attribute: Attribute) -> AttributeSpec? {
        attributes.first { $0.attribute == attribute }
    }

    static func operators(for attribute: Attribute) -> [Operator] {
        spec(for: attribute)?.operators ?? stringOperators
    }

    /// Actions the editor offers, in menu order.
    static let actionTypes: [ActionType] = [
        .move, .copy, .rename, .sortIntoDatedFolder, .askModel, .skip,
        .addTags, .setComment, .trash, .stop, .proceed
    ]

    static func takesTemplate(_ type: ActionType) -> Bool {
        type == .move || type == .copy || type == .rename || type == .sortIntoDatedFolder
            || type == .setComment
    }

    static func takesTags(_ type: ActionType) -> Bool {
        type == .addTags || type == .removeTags
    }

    // MARK: - Labels

    private static let englishAttributes: [String: String] = [
        "name": "File name", "stem": "Name without extension", "ext": "Extension",
        "kind": "Kind", "size": "Size", "dateAdded": "Date added",
        "dateCreated": "Date created", "dateModified": "Date modified",
        "dateOpened": "Date last opened", "dateCaptured": "Date taken",
        "relpath": "Path below the watched folder", "parent": "Parent folder",
        "subfolder": "Subfolder", "depth": "Folder depth", "uti": "Type identifier",
        "isPackage": "Is a document package", "isHidden": "Is hidden",
        "tags": "Finder tags", "label": "Finder label", "comment": "Finder comment",
        "whereFrom": "Downloaded from", "whereFromHost": "Downloaded from (site)",
        "pixelWidth": "Width in pixels", "pixelHeight": "Height in pixels",
        "megapixels": "Megapixels", "duration": "Duration in seconds",
        "pageCount": "Page count", "title": "Title", "authors": "Authors",
        "subjects": "Subjects", "publisher": "Publisher", "language": "Language",
        "text": "Text inside the file", "duplicateInTarget": "Already filed"
    ]

    private static let germanAttributes: [String: String] = [
        "name": "Dateiname", "stem": "Name ohne Endung", "ext": "Endung",
        "kind": "Art", "size": "Grösse", "dateAdded": "Hinzugefügt am",
        "dateCreated": "Erstellt am", "dateModified": "Geändert am",
        "dateOpened": "Zuletzt geöffnet", "dateCaptured": "Aufgenommen am",
        "relpath": "Pfad unter dem Ordner", "parent": "Übergeordneter Ordner",
        "subfolder": "Unterordner", "depth": "Ordnertiefe", "uti": "Typkennung",
        "isPackage": "Ist ein Dokumentpaket", "isHidden": "Ist ausgeblendet",
        "tags": "Finder-Tags", "label": "Finder-Etikett", "comment": "Finder-Kommentar",
        "whereFrom": "Geladen von", "whereFromHost": "Geladen von (Website)",
        "pixelWidth": "Breite in Pixeln", "pixelHeight": "Höhe in Pixeln",
        "megapixels": "Megapixel", "duration": "Dauer in Sekunden",
        "pageCount": "Seitenzahl", "title": "Titel", "authors": "Autoren",
        "subjects": "Themen", "publisher": "Verlag", "language": "Sprache",
        "text": "Text in der Datei", "duplicateInTarget": "Bereits abgelegt"
    ]

    private static let englishOperators: [String: String] = [
        "is": "is", "isNot": "is not", "contains": "contains",
        "notContains": "does not contain", "beginsWith": "begins with",
        "endsWith": "ends with", "matchesGlob": "matches pattern",
        "notMatchesGlob": "does not match pattern", "matchesRegex": "matches regex",
        "notMatchesRegex": "does not match regex", "in": "is one of",
        "notIn": "is none of", "isEmpty": "is empty", "isNotEmpty": "is not empty",
        "eq": "is", "ne": "is not", "gt": "is more than", "gte": "is at least",
        "lt": "is less than", "lte": "is at most", "between": "is between",
        "before": "is before", "after": "is after", "olderThan": "is older than",
        "newerThan": "is newer than", "inLast": "is within the last",
        "notInLast": "is not within the last", "containsAny": "contains any of",
        "containsAll": "contains all of", "containsNone": "contains none of",
        "isTrue": "is true", "isFalse": "is false", "conformsTo": "conforms to"
    ]

    private static let germanOperators: [String: String] = [
        "is": "ist", "isNot": "ist nicht", "contains": "enthält",
        "notContains": "enthält nicht", "beginsWith": "beginnt mit",
        "endsWith": "endet mit", "matchesGlob": "passt auf Muster",
        "notMatchesGlob": "passt nicht auf Muster", "matchesRegex": "passt auf Regex",
        "notMatchesRegex": "passt nicht auf Regex", "in": "ist eines von",
        "notIn": "ist keines von", "isEmpty": "ist leer", "isNotEmpty": "ist nicht leer",
        "eq": "ist", "ne": "ist nicht", "gt": "ist grösser als", "gte": "ist mindestens",
        "lt": "ist kleiner als", "lte": "ist höchstens", "between": "liegt zwischen",
        "before": "ist vor", "after": "ist nach", "olderThan": "ist älter als",
        "newerThan": "ist neuer als", "inLast": "liegt in den letzten",
        "notInLast": "liegt nicht in den letzten", "containsAny": "enthält eines von",
        "containsAll": "enthält alle von", "containsNone": "enthält keines von",
        "isTrue": "trifft zu", "isFalse": "trifft nicht zu", "conformsTo": "entspricht"
    ]

    private static let englishActions: [String: String] = [
        "move": "Move to", "copy": "Copy to", "rename": "Rename to",
        "sortIntoDatedFolder": "Sort into dated folder", "askModel": "Ask the model",
        "skip": "Leave alone", "addTags": "Add tags", "removeTags": "Remove tags",
        "setComment": "Set Finder comment", "setLabel": "Set label", "notify": "Notify",
        "reveal": "Reveal in Finder", "open": "Open", "runShortcut": "Run Shortcut",
        "trash": "Move to Trash", "quarantine": "File as unsure",
        "stop": "Stop here", "continue": "Keep checking later steps"
    ]

    private static let germanActions: [String: String] = [
        "move": "Verschieben nach", "copy": "Kopieren nach", "rename": "Umbenennen in",
        "sortIntoDatedFolder": "In Datumsordner ablegen", "askModel": "Das Modell fragen",
        "skip": "Unangetastet lassen", "addTags": "Tags hinzufügen",
        "removeTags": "Tags entfernen", "setComment": "Finder-Kommentar setzen",
        "setLabel": "Etikett setzen", "notify": "Mitteilung senden",
        "reveal": "Im Finder zeigen", "open": "Öffnen", "runShortcut": "Kurzbefehl ausführen",
        "trash": "In den Papierkorb", "quarantine": "Als unsicher ablegen",
        "stop": "Hier aufhören", "continue": "Weitere Schritte prüfen"
    ]

    /// Whether both tables carry this term. The editor never asks; the tests
    /// do, because a label that falls back to its raw value looks fine in
    /// English (where "contains" *is* the raw value) and reads as gibberish in
    /// German.
    static func isLabelled(_ attribute: Attribute) -> Bool {
        englishAttributes[attribute.rawValue] != nil && germanAttributes[attribute.rawValue] != nil
    }

    static func isLabelled(_ op: Operator) -> Bool {
        englishOperators[op.rawValue] != nil && germanOperators[op.rawValue] != nil
    }

    static func isLabelled(_ action: ActionType) -> Bool {
        englishActions[action.rawValue] != nil && germanActions[action.rawValue] != nil
    }

    static func label(for attribute: Attribute) -> String {
        localized(attribute.rawValue, english: englishAttributes, german: germanAttributes)
    }

    static func label(for op: Operator) -> String {
        localized(op.rawValue, english: englishOperators, german: germanOperators)
    }

    static func label(for action: ActionType) -> String {
        localized(action.rawValue, english: englishActions, german: germanActions)
    }

    private static func localized(_ key: String, english: [String: String],
                                  german: [String: String]) -> String {
        if L10n.language == "de", let text = german[key] { return text }
        // An unknown value from a newer build shows its own name rather than
        // nothing: the user can see it, and re-saving keeps it.
        return english[key] ?? key
    }
}
