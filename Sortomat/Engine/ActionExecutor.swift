import Foundation

/// The actions that happen *after* a file has been placed.
///
/// The engine has recorded these since the step model landed and nothing ever
/// carried them out, so a rule that said "file it and tag it Steuern" filed it
/// and said nothing about the tag. This applies the ones that can be applied
/// safely and honestly today; `supported` is the list, the validator reads the
/// same list, and a user is told in the editor which of their actions this
/// build does not perform yet rather than discovering it from a tag that never
/// appears.
///
/// Order matters and is fixed by the caller: the journal entry is written
/// first, so a side effect that fails can never cost the user their undo.
enum ActionExecutor {
    /// What this build actually performs. Deliberately short.
    ///
    /// `reveal` and `open` are left out on purpose rather than for want of an
    /// API: an automatic rule over a four-hundred-file backlog would open four
    /// hundred windows, and "how many is too many" is a product decision, not
    /// an implementation detail. `setComment`, `setLabel` and `runShortcut`
    /// need APIs (Finder comments, label numbers, the `shortcuts` binary) that
    /// deserve to be written with a compiler at hand.
    static let supported: Set<ActionType> = [.addTags, .removeTags, .notify]

    /// Returns the effects that were carried out, for the activity line.
    @discardableResult
    static func apply(_ effects: [SideEffect], to url: URL) -> [ActionType] {
        var performed: [ActionType] = []
        // The activity line names what was done, once each: two tag effects on
        // one file are one thing that happened to it, not two.
        func record(_ type: ActionType) {
            guard !performed.contains(type) else { return }
            performed.append(type)
        }
        for effect in effects where supported.contains(effect.type) {
            switch effect.type {
            case .addTags, .removeTags:
                // Nothing to do is not something done: adding a tag the file
                // already carries would otherwise rewrite the file's metadata
                // and report the effect as carried out.
                guard let existing = tags(of: url) else { continue }
                let updated = resolve(existing, applying: effect)
                guard updated != existing, writeTags(updated, to: url) else { continue }
                record(effect.type)
            case .notify:
                guard notify(effect, about: url) else { continue }
                record(effect.type)
            default:
                continue
            }
        }
        return performed
    }

    // MARK: - Tags

    /// The tag list a file should end up with. Pure, and the reason the tag
    /// rules are testable without a file system.
    ///
    /// Comparison is case-insensitive because Finder's own tag list is: a file
    /// cannot hold both "Steuern" and "steuern", and a rule that adds the
    /// second spelling of a tag the file already has must not create a
    /// duplicate. The *existing* spelling wins, because it is the one already
    /// shown in every Finder window the user has open.
    static func resolve(_ existing: [String], applying effect: SideEffect) -> [String] {
        let wanted = effect.values
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        switch effect.type {
        case .addTags:
            var result = existing
            var seen = Set(existing.map { $0.lowercased() })
            for tag in wanted where seen.insert(tag.lowercased()).inserted {
                result.append(tag)
            }
            return result
        case .removeTags:
            let doomed = Set(wanted.map { $0.lowercased() })
            return existing.filter { !doomed.contains($0.lowercased()) }
        default:
            return existing
        }
    }

    private static func tags(of url: URL) -> [String]? {
        guard let values = try? url.resourceValues(forKeys: [.tagNamesKey]) else { return nil }
        return values.tagNames ?? []
    }

    private static func writeTags(_ tags: [String], to url: URL) -> Bool {
        do {
            // `URLResourceValues.tagNames` is get-only in the Swift overlay —
            // the struct can report a file's tags but not set them — so the
            // writable path is `NSURL`'s untyped setter. Bridged explicitly
            // rather than left to `Any?` inference, because what reaches the
            // file system here is a Finder tag list and not a Swift array.
            try (url as NSURL).setResourceValue(tags as NSArray, forKey: .tagNamesKey)
            return true
        } catch {
            Log.pipeline.error("could not write tags: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    // MARK: - Notify

    /// The file's own name is the title and the rule's text is the body: a
    /// banner headed "Sortomat" tells the reader what they already know.
    private static func notify(_ effect: SideEffect, about url: URL) -> Bool {
        // `UNUserNotificationCenter.current()` traps in a process with no
        // bundle identifier, which is exactly what the headless CLI is. A rule
        // with a `notify` action must not turn `sortomat scan-once` into a
        // crash.
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let text = effect.values
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty }
        guard let text else { return false }
        Notifier.post(title: url.lastPathComponent, body: text)
        return true
    }
}
