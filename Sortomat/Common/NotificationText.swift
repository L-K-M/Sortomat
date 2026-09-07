import Foundation

/// The words a notification says. Pure, so what the user reads at 2 a.m. when
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
