import Foundation

/// The words a notification says — and, where the window reports the same fact,
/// the joins those two share. Pure, so what the user reads at 2 a.m. when
/// twelve files moved on their own can be pinned by a test instead of guessed
/// at from a screenshot.
enum NotificationText {
    /// How many file names are listed before the rest become "and N more".
    static let namesShown = 2

    /// "Invoice 2024.pdf, Receipt.pdf and 3 more → ~/Documents/Invoices".
    ///
    /// The old banner said "Sortomat / Filed 5 files." — which tells you
    /// something happened and nothing about what, and leaves you opening
    /// Finder to find out whether to worry.
    static func summary(of urls: [URL]) -> String {
        guard !urls.isEmpty else { return "" }
        let names = urls.prefix(namesShown).map(\.lastPathComponent)
        var text = names.joined(separator: ", ")
        let extra = urls.count - names.count
        if extra > 0 { text += " " + L10n.plural("notify.andMore", extra) }
        if let folder = commonFolder(of: urls) {
            text += " → " + (folder.path as NSString).abbreviatingWithTildeInPath
        }
        return text
    }

    /// What the banner says once an Undo button has been pressed: a title and
    /// a body, or an empty body when there is nothing more to add.
    ///
    /// Pure, and separate from the posting, because the case that matters most
    /// is the one no screenshot will ever catch. A banner survives in
    /// Notification Center for days, and `Journal.recent` folds away a move
    /// that has already been reversed — so pressing Undo on yesterday's banner,
    /// or pressing it twice, legitimately finds nothing to reverse. The old
    /// code posted nothing at all in that case: the user pressed a button that
    /// moves files and the machine went silent, which is the exact fear the
    /// Undo button exists to answer.
    static func undoResult(
        undone: Int, failed: Int, firstFailure: String? = nil
    ) -> (title: String, body: String) {
        guard undone + failed > 0 else {
            return (L10n.t("notify.undoNothing"), L10n.t("notify.undoNothing.body"))
        }
        // Nothing moved and something refused: lead with the refusal rather
        // than with "Put 0 files back".
        if undone == 0 {
            return (L10n.plural("notify.undoFailed", failed), firstFailure ?? "")
        }
        return (
            L10n.plural("notify.undone", undone),
            failed > 0
                ? refusal(count: L10n.plural("notify.undoFailed", failed), reason: firstFailure)
                : ""
        )
    }

    /// A count of refusals and the reason behind the first, joined the one way
    /// this app reports a refusal.
    ///
    /// Shared with the History list rather than written out twice: "something
    /// else is at that path now" is the only part of a failure the user can act
    /// on, both surfaces report it, and two copies of a join are two chances
    /// for the same fact to arrive punctuated differently.
    static func refusal(count: String, reason: String?) -> String {
        [count, reason ?? ""].filter { !$0.isEmpty }.joined(separator: " — ")
    }

    /// The deepest folder that contains all of them — the one place a person
    /// can open to see everything this pass did. Nil when they landed on
    /// different volumes, or when the answer would be `/`, which says nothing.
    static func commonFolder(of urls: [URL]) -> URL? {
        guard let first = urls.first else { return nil }
        var shared = first.deletingLastPathComponent().standardizedFileURL.pathComponents
        for url in urls.dropFirst() {
            let components = url.deletingLastPathComponent().standardizedFileURL.pathComponents
            var index = 0
            while index < shared.count, index < components.count, shared[index] == components[index] {
                index += 1
            }
            shared = Array(shared.prefix(index))
        }
        guard shared.count > 1 else { return nil }
        return URL(fileURLWithPath: NSString.path(withComponents: shared))
    }
}
