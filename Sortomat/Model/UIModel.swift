import Foundation
import SwiftUI

/// The value types the main window is built out of. Deliberately free of any
/// view code: what the sidebar selects, how sure the model was, and how a file
/// describes itself are all decisions worth testing without a window on screen.

/// What the sidebar has selected. `rule` carries the id rather than the rule so
/// a selection survives an edit, a rename, or a reordering of `config.rules`.
enum SidebarSelection: Hashable {
    case inbox
    case history
    case rule(UUID)

    var ruleID: UUID? {
        if case .rule(let id) = self { return id }
        return nil
    }
}

/// The three states a rule can be in, as one choice instead of two toggles.
///
/// `enabled` and `dryRun` are independent booleans in the stored config, which
/// makes four combinations of which only three mean anything — and asks the
/// user to work out that "enabled + preview only" is the safe setting and
/// "disabled + preview only" does nothing at all. The stored shape doesn't
/// change; this is what gets shown.
enum RuleMode: String, CaseIterable, Identifiable, Hashable {
    /// Runs and files without asking.
    case automatic
    /// Runs, but every placement waits in the Inbox for a yes.
    case askFirst
    /// Doesn't run.
    case off

    var id: String { rawValue }

    init(_ rule: Rule) {
        if !rule.enabled { self = .off } else if rule.dryRun { self = .askFirst } else { self = .automatic }
    }

    func apply(to rule: inout Rule) {
        switch self {
        case .automatic: rule.enabled = true; rule.dryRun = false
        case .askFirst: rule.enabled = true; rule.dryRun = true
        case .off: rule.enabled = false
        }
    }

    var label: String { L10n.t("mode.\(rawValue)") }
    var help: String { L10n.t("mode.\(rawValue).help") }

    var symbol: String {
        switch self {
        case .automatic: return "bolt.fill"
        case .askFirst: return "hand.raised.fill"
        case .off: return "pause.fill"
        }
    }

    var tint: Color {
        switch self {
        case .automatic: return .green
        case .askFirst: return .orange
        case .off: return .secondary
        }
    }
}

/// How sure the model was, in words. A bare "62%" asks the reader to know what
/// the threshold is; "Probably" doesn't. The number is still shown next to it —
/// the word is the part you can act on at a glance.
enum Heat: Hashable, CaseIterable {
    case certain
    case sure
    case probably
    case unsure
    /// No model was involved at all — a deterministic step decided this.
    case exact

    init(confidence: Double?) {
        guard let confidence else { self = .unsure; return }
        switch confidence {
        case 0.9...: self = .certain
        case 0.75..<0.9: self = .sure
        case 0.5..<0.75: self = .probably
        default: self = .unsure
        }
    }

    var label: String { L10n.t("heat.\(key)") }

    private var key: String {
        switch self {
        case .certain: return "certain"
        case .sure: return "sure"
        case .probably: return "probably"
        case .unsure: return "unsure"
        case .exact: return "exact"
        }
    }

    var tint: Color {
        switch self {
        case .certain, .exact: return .green
        case .sure: return .teal
        case .probably: return .orange
        case .unsure: return .red
        }
    }
}

/// What a file says about itself before anything is decided: the facts a person
/// checks when asked "should this move?".
struct FileSummary: Equatable {
    var name: String
    var sizeText: String
    var modified: Date?
    var exists: Bool

    init(url: URL, fileManager: FileManager = .default) {
        name = url.lastPathComponent
        let attributes = try? fileManager.attributesOfItem(atPath: url.path)
        exists = attributes != nil
        modified = attributes?[.modificationDate] as? Date
        let size = (attributes?[.size] as? Int64) ?? 0
        sizeText = Self.byteFormatter.string(fromByteCount: size)
    }

    /// A shared formatter: building one per row turned a 200-row list into 200
    /// allocations per redraw.
    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    var modifiedText: String {
        guard let modified else { return "" }
        return modified.formatted(date: .abbreviated, time: .shortened)
    }
}

/// One row of the Inbox: a plan, plus everything needed to render it without
/// reaching back into `AppState` from inside a `ForEach`.
struct InboxItem: Identifiable, Equatable {
    let plan: PlannedAction
    /// Target root of the rule that made the plan, for a relative destination.
    let target: URL
    let ruleMode: RuleMode
    /// Read once, at construction. As a computed property this called
    /// `attributesOfItem` — a blocking stat — on every access, so a full Inbox
    /// turned each list invalidation into one disk hit per row on the main
    /// thread, and the size shown could change between two renders of the same
    /// row. The type is `Equatable` precisely so rows diff cheaply.
    let summary: FileSummary

    init(plan: PlannedAction, target: URL, ruleMode: RuleMode) {
        self.plan = plan
        self.target = target
        self.ruleMode = ruleMode
        self.summary = FileSummary(url: plan.source)
    }

    var id: UUID { plan.id }
    /// A decision a *step* made is exact — no model was asked, so there is no
    /// confidence to report and "Certain" would be a weaker word than the
    /// truth. `.fallback` deliberately is not: the rule's fallback parking a
    /// file it could not place is the definition of unsure.
    var heat: Heat {
        switch plan.origin {
        case .preRule, .step: return .exact
        default: return Heat(confidence: plan.confidence)
        }
    }
    var destinationText: String { plan.relativeDestination(to: target) }

    /// Where the decision came from, in the user's words. "A step decided
    /// this" and "the model decided this" are not the same promise, and the
    /// difference is the whole reason to trust either.
    var originText: String {
        switch plan.origin {
        // `.preRule` is the engine's old spelling of `.step` and no longer
        // produced; the two say the same thing to a reader, so they say it in
        // the same words rather than inventing a distinction to keep them
        // apart.
        case .preRule, .step: return L10n.t("origin.step")
        case .model: return L10n.t("origin.model")
        case .taxonomy: return L10n.t("origin.folders")
        case .confidence: return L10n.t("origin.unsure")
        case .fallback: return L10n.t("origin.fallback")
        case .system: return L10n.t("origin.system")
        }
    }

}

/// The Inbox's rules, grouped by the folder they watch — because "what happens
/// to my Downloads folder" is the question people actually have, and a flat
/// list of rule names never answers it.
struct RuleGroup: Identifiable, Equatable {
    let watchPath: String
    let rules: [Rule]

    var id: String { watchPath }

    /// `~/Downloads` rather than `/Users/someone/Downloads`: the home prefix is
    /// noise in a sidebar, and it is the same for every row.
    var title: String {
        guard !watchPath.isEmpty else { return L10n.t("sidebar.noFolder") }
        return (watchPath as NSString).abbreviatingWithTildeInPath
    }

    static func group(_ rules: [Rule]) -> [RuleGroup] {
        var order: [String] = []
        var byPath: [String: [Rule]] = [:]
        for rule in rules {
            // Standardized, not merely tilde-expanded: a trailing slash, a
            // `.` segment or a doubled separator all name the same folder, and
            // a real config.json contains them. Two visually identical sidebar
            // sections for one folder is a bug the user can do nothing about.
            let key = URL(fileURLWithPath: (rule.watchPath as NSString).expandingTildeInPath)
                .standardizedFileURL.path
            if byPath[key] == nil { order.append(key) }
            byPath[key, default: []].append(rule)
        }
        return order.map { RuleGroup(watchPath: $0, rules: byPath[$0] ?? []) }
    }
}
