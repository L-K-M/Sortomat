import Foundation

/// The decided outcome for one file — computed once, then either shown in the
/// preview or executed. Separating "decide" from "do" is what makes dry-run and
/// apply share exactly the same logic (PLAN Phase 2).
struct PlannedAction: Identifiable, Equatable {
    enum Kind: String, Equatable {
        case move
        case copy
        case skip
        case quarantine
        case duplicate
    }

    /// Where the decision came from — surfaced so the user can trust it.
    enum Origin: String, Equatable, CaseIterable {
        case preRule
        case model
        case taxonomy      // model answered but was constrained/redirected by taxonomy
        case confidence    // routed to quarantine for low confidence
        case system        // duplicate/skip decided locally
        case step          // an engine-v2 step claimed the file
        case fallback      // no step matched; rule.fallback decided
    }

    let id = UUID()
    let ruleID: UUID
    let ruleName: String
    let source: URL
    let kind: Kind
    /// Absolute destination for move/copy/quarantine; nil for skip.
    let destination: URL?
    let origin: Origin
    let reason: String
    /// 0…1 when the model reported one.
    let confidence: Double?
    /// Whether executing this should copy rather than move.
    let copyInsteadOfMove: Bool
    /// `Ledger.fingerprint` of the source at decide time. Apply re-checks it:
    /// a plan must not execute against a file that changed (or was replaced)
    /// after the user saw the suggestion. `nil` on plans made before this
    /// field existed — those apply unchecked, as before.
    var fingerprint: String? = nil
    /// What happens to the file once it has been placed — tags, a banner.
    /// Carried on the plan rather than re-derived at apply time, so what the
    /// preview showed is exactly what runs.
    var sideEffects: [SideEffect] = []

    var isActionable: Bool { kind == .move || kind == .copy || kind == .quarantine }

    /// Destination shown relative to a target root, for compact display.
    func relativeDestination(to target: URL) -> String {
        guard let destination else { return "—" }
        let base = target.standardizedFileURL.path
        let full = destination.standardizedFileURL.path
        if full.hasPrefix(base + "/") {
            return String(full.dropFirst(base.count + 1))
        }
        return destination.lastPathComponent
    }
}
