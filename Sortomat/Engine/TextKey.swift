import Foundation

/// The comparison form of a string.
///
/// NFC first: a file named `Ärzte.pdf` on an HFS+ volume is stored decomposed
/// (`A` + U+0308 + `rzte`), while the same word typed into a rule field is
/// composed — ICU's regex engine does not implement canonical equivalence, so
/// the pattern silently matched nothing. Then case folding, unless the
/// condition asked for case sensitivity: `lowercased()` is the
/// locale-independent form (`lowercased(with:)` is the localized one), so a
/// Turkish system does not change what a rule matches.
///
/// Both sides of every comparison go through this — patterns included. NFC is
/// a no-op for ASCII, so regex and glob metacharacters are unaffected.
enum TextKey {
    static func fold(_ string: String, caseSensitive: Bool) -> String {
        let composed = string.precomposedStringWithCanonicalMapping
        return caseSensitive ? composed : composed.lowercased()
    }
}
