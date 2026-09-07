import Foundation

/// A tiny in-code localization table. English is the base; German overrides it
/// when the user's preferred language is German. An in-code table (rather than
/// `.strings`/String-catalog resources) keeps the executable target free of
/// resource-bundling quirks while still shipping a genuinely bilingual UI.
public enum L10n {
    /// Overridden in tests to force a language; otherwise follows the system.
    public static var forcedLanguage: String?

    /// Every language the tables actually hold. One place, so a test that
    /// sweeps "does this string exist in every language" keeps sweeping all of
    /// them when a third is added.
    public static let supportedLanguages = ["en", "de"]

    public static var language: String {
        if let forced = forcedLanguage { return forced }
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("de") ? "de" : "en"
    }

    /// Localized string for `key`. Falls back to the English table, then to the
    /// key itself (so a missing key is visible but never crashes).
    public static func t(_ key: String) -> String {
        if language == "de", let s = german[key] { return s }
        if let s = english[key] ?? german[key] { return s }
        // A key that reaches a user as its own raw name is a bug; fail in
        // Debug (so any test that renders it says so) and degrade in release.
        assertionFailure("L10n: no entry for «\(key)»")
        return key
    }

    /// Localized format string with positional `%@`/`%d`-style arguments.
    public static func t(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    /// Count-aware lookup: `key.one` when the count is exactly 1, `key.other`
    /// otherwise, with the count as the format argument — retires the
    /// "%d change(s)" hack. (Two forms cover English and German; a language
    /// with more plural categories would need a real plural-rules engine.)
    public static func plural(_ key: String, _ count: Int) -> String {
        String(format: t(key + (count == 1 ? ".one" : ".other")), count)
    }

    /// Count-aware lookup with extra format arguments. The count is argument
    /// 1 and the extras follow, so strings that need both use positional
    /// specifiers (`%1$d`, `%2$@`).
    ///
    /// A form that references `%2$` **must** also reference `%1$`: the
    /// formatter only types the slots a specifier names, and an untyped slot
    /// doesn't consume its argument — so `%2$@` alone would read the count as
    /// an object pointer and crash. `L10nTests` enforces this across the
    /// tables.
    public static func plural(_ key: String, _ count: Int, _ args: CVarArg...) -> String {
        let format = t(key + (count == 1 ? ".one" : ".other"))
        // The table test enforces this across the shipped strings; the assert
        // catches anything that reaches the formatter another way, because the
        // failure mode is a crash rather than a wrong word.
        assert(!format.contains("%2$") || format.contains("%1$"),
               "L10n: «\(format)» references %2$ without %1$ — the count slot stays untyped")
        return String(format: format, arguments: [count as CVarArg] + args)
    }

    // MARK: - English (base)

    static let english: [String: String] = [
        // App / menubar
        "app.status.active.one": "Active — 1 rule",
        "app.status.active.other": "Active — %d rules",
        "app.status.paused": "Paused",
        "app.status.noKey": "⚠️ No API key set",
        "app.lastScan": "Last check: %@",
        "menu.resume": "Resume",
        "menu.pause": "Pause",
        "menu.scanNow": "Check now",
        "menu.previewNow": "Preview changes…",

        // Main window
        "main.window.title": "Sortomat",
        "menu.openMain": "Open Sortomat",
        "menu.openHistory": "History…",
        "sidebar.inbox": "Inbox",
        "sidebar.history": "History",
        "sidebar.noFolder": "No folder set",

        // How a rule runs — one choice instead of two toggles
        "mode.automatic": "Automatic",
        "mode.automatic.help": "It files matching files by itself. You can undo anything it does from History.",
        "mode.askFirst": "Ask first",
        "mode.askFirst.help": "Works out what it would do and puts it in the Inbox for you to approve.",
        "mode.off": "Off",
        "mode.off.help": "Doesn't run at all.",

        // How sure the model was
        "heat.certain": "Certain",
        "heat.sure": "Sure",
        "heat.probably": "Probably",
        "heat.unsure": "Unsure",
        "heat.exact": "Exact match",
        "heat.help": "How sure Sortomat is about this one. «Exact match» means a step decided it — no guessing involved.",

        // Where a decision came from — the trust signal
        "origin.step": "Step",
        "origin.model": "Model",
        "origin.folders": "Kept inside your folders",
        "origin.unsure": "Too unsure to file",
        "origin.fallback": "No step matched",
        "origin.system": "Sortomat",

        // Inbox
        "inbox.count.one": "1 thing to file",
        "inbox.count.other": "%d things to file",
        "inbox.check": "Check now",
        "inbox.apply": "File it",
        "inbox.skip": "Skip",
        "inbox.applyAll": "File all",
        "inbox.skipAll": "Skip all",
        "inbox.why": "Why?",
        "inbox.why.hide": "Hide why",
        "inbox.reveal": "Show in Finder",
        "inbox.undoLast": "Undo that",
        "inbox.applied.one": "Filed 1 item.",
        "inbox.applied.other": "Filed %d items.",
        "inbox.skipped.one": "Skipped 1 item.",
        "inbox.skipped.other": "Skipped %d items.",
        "inbox.empty.title": "Nothing to file",
        "inbox.empty": "Sortomat is watching your folders. Anything it wants to move will show up here first.",
        "inbox.empty.noKey.title": "No API key set",
        "inbox.empty.noKey": "Steps still run without one, but nothing can be handed to the model. Add a key in Settings, or build rules out of steps alone.",
        "inbox.action.move": "Move to %@",
        "inbox.action.copy": "Copy to %@",
        "inbox.action.unsure": "Not sure — park in %@",
        "inbox.action.duplicate": "Already filed — this is the same file",
        "inbox.action.skip": "Leave where it is",

        // History
        "history.empty.title": "Nothing filed yet",
        "history.refresh": "Reload",
        "history.reveal": "Show in Finder",
        "rules.empty.message": "Pick a rule on the left, or add one with the + button.",
        "menu.noActivity": "No activity yet",
        "menu.recentActivity": "Recent activity",
        "menu.openLog": "Open log",
        "menu.settings": "Rules & Settings…",
        "menu.quit": "Quit",
        "menu.pendingReview.one": "1 change awaiting review…",
        "menu.pendingReview.other": "%d changes awaiting review…",
        "menu.spend": "Estimated spend (this month): %@",
        "menu.checkUpdates": "Check for Updates…",
        "menu.close": "Close",
        "menu.file": "File",
        "menu.edit": "Edit",
        "menu.about": "About Sortomat",
        "menu.hide": "Hide Sortomat",
        "menu.hideOthers": "Hide Others",
        "menu.showAll": "Show All",
        "menu.quitApp": "Quit Sortomat",
        "edit.undo": "Undo",
        "edit.redo": "Redo",
        "edit.cut": "Cut",
        "edit.copy": "Copy",
        "edit.paste": "Paste",
        "edit.delete": "Delete",
        "edit.selectAll": "Select All",

        // Settings tabs
        "settings.window.title": "Sortomat — Rules & Settings",
        "tab.general": "Settings",
        "tab.about": "About",

        // Rules list
        "rules.empty.title": "Select a rule, or add one with +",
        "rules.add": "Add rule",
        "rules.remove": "Remove rule",
        "rules.duplicate": "Duplicate",
        "rules.delete.title": "Delete the rule «%@»?",
        "rules.delete.message": "Its prompt, taxonomy and pre-rules are deleted with it, and Sortomat forgets which files it already handled. This cannot be undone.",
        "rules.delete.confirm": "Delete rule",
        "rules.export": "Export rule…",
        "rules.import": "Import rule…",
        "rules.export.done": "Exported «%@».",
        "rules.import.done": "Imported — disabled, in preview mode. Set its folders, then enable it.",
        "rules.pack.failed": "Couldn't process the rule file: %@",
        "rules.pack.unsupportedFormat": "This rule file uses a newer format (%d) than this version of Sortomat understands.",

        // Rule editor
        "rule.defaultName": "New Rule",
        "rule.defaultQuarantine": "_Quarantine",
        "rule.name": "Name:",
        "rule.enabled": "Rule enabled",
        "rule.dryRun": "Preview only (don't move files)",
        "rule.priority": "Priority:",
        "rule.watchFolder": "Watched folder:",
        "rule.targetFolder": "Target folder:",
        "rule.recursive": "Include subfolders",
        "rule.extensions": "File extensions:",
        "rule.extensions.prompt": "e.g. epub, pdf — empty = all files",
        "rule.copy": "Copy instead of move",
        "rule.privacy": "Privacy:",
        "rule.privacy.full": "Send name, metadata & content excerpt",
        "rule.privacy.metadataOnly": "Send name & metadata only (contents stay local)",
        "rule.prompt.section": "Sorting instruction (prompt)",
        "rule.prompt.help": "Describe which files are affected and what the target structure should look like, e.g. «{Genre}/{Last, First}/{Title}.epub».",
        "rule.taxonomy.section": "Allowed top-level folders (taxonomy)",
        "rule.taxonomy.help": "One per line. If set, the model may only file into these top folders; anything else goes to the quarantine folder.",
        "rule.taxonomy.prompt": "Leave empty to let the model choose freely",
        "rule.quarantine": "Quarantine subfolder:",
        "rule.confidence": "Confidence threshold: %d%%",
        "rule.confidence.help": "Classifications below this confidence are routed to the quarantine folder instead of being filed. 0 disables the check.",
        "rule.preRules.section": "Deterministic pre-rules",
        "rule.preRules.help": "Checked in order before the model. First match wins. Free and predictable — the model only handles what falls through.",
        "rule.preRules.add": "Add pre-rule",
        "rule.preRule.match": "Match",
        "rule.preRule.pattern": "Pattern",
        "rule.preRule.action": "Action",
        "rule.preRule.route": "Route to",
        "rule.editingPaused": "This rule is paused while it's open here — it resumes when you switch away.",
        "rule.validate.watchMissing": "The watched folder doesn't exist.",
        "rule.validate.targetMissing": "The target folder doesn't exist yet — it will be created on first use.",
        "rule.validate.samePath": "Watched and target folder are the same — nothing will ever be sorted.",
        "rule.validate.watchInsideTarget": "The watched folder lies inside the target folder — its files count as already sorted, so nothing will match.",
        "rule.validate.targetInsideWatch": "The target folder lies inside the watched folder. Filed files stay in the watched tree; Sortomat skips them, but a target outside the watched folder is easier to reason about.",
        "rule.validate.badRegex": "This regular expression is invalid — the pre-rule will never match.",

        "match.glob": "Name glob",
        "match.regex": "Name regex",
        "match.kind": "Kind",
        "match.olderThanDays": "Older than (days)",
        "match.newerThanDays": "Newer than (days)",
        "action.route": "Route to folder",
        "action.skip": "Skip",
        "action.useLLM": "Ask the model",
        "preRule.name.prompt": "Optional name",
        "preRule.moveUp": "Move up",
        "preRule.moveDown": "Move down",
        "preRule.delete": "Delete pre-rule",
        "preRule.route.help": "Relative to the target folder. Tokens: {name} {ext} {year} {month} {day}.",
        "preRule.help.glob": "Shell wildcards: * matches anything, ? matches one character.",
        "preRule.help.regex": "A regular expression matched against the file name.",
        "preRule.help.kind": "One of: image, video, audio, pdf, archive, text, ebook, document.",
        "preRule.help.days": "A whole number of days.",
        "preRule.sum.glob": "the name matches «%@»",
        "preRule.sum.regex": "the name matches the regex «%@»",
        "preRule.sum.kind": "the file's kind is %@",
        "preRule.sum.olderThanDays": "the file is older than %@ days",
        "preRule.sum.newerThanDays": "the file is newer than %@ days",
        "preRule.sum.route": "file it into «%@»",
        "preRule.sum.skip": "skip it",
        "preRule.sum.useLLM": "let the model decide",
        "preRule.sum.template": "When %@, %@.",
        "preRule.sum.placeholder": "…",

        // General tab
        "general.provider.section": "Model provider",
        "general.apiKey": "API key:",
        "general.apiKey.save": "Save",
        "general.apiKey.saved": "Saved to the Keychain.",
        "general.apiKey.saveFailed": "Couldn't save to the Keychain — the key was not stored.",
        "general.apiKey.placeholder.missing": "No key set yet",
        "general.apiKey.placeholder.set": "••••••••  (saved)",
        "general.model": "Model:",
        "general.apiBase": "API base URL:",
        "general.requiresKey": "This provider needs an API key",
        "general.localHint": "For a local model (Ollama, LM Studio) point the base URL at it and turn off «needs an API key», e.g. http://localhost:11434.",
        "general.pricing.section": "Cost estimation",
        "general.pricing.input": "Input $/1M tokens:",
        "general.pricing.output": "Output $/1M tokens:",
        "general.pricing.currency": "Currency (ISO code):",
        "general.monthlyBudget": "Stop after (per month, 0 = no limit):",
        "general.monthlyBudget.help": "The per-check limit caps one burst. This caps the month: once estimated spend passes it, steps keep filing what they can for free and files that need the model wait.",
        "general.monthlyBudget.reached": "Monthly limit reached — %@ spent. Steps still run; nothing is being sent to the model.",
        "general.onlyOnPower": "Only check while plugged in",
        "general.pauseInLowPower": "Pause in Low Power Mode",
        "general.power.help": "Reading a file can mean OCR, a full-content hash and a paid request. On battery that is the most expensive possible work at the worst possible moment.",
        "general.watch.section": "Watching",
        "general.interval": "Check interval: %d s",
        "general.interval.help": "Folders are also checked immediately when something changes. The interval is only the safety net.",
        "general.concurrency": "Max concurrent classifications: %d",
        "general.budget": "Max model calls per check (0 = unlimited): %d",
        "general.notifications": "Notify about filed files and failures",
        "general.launchAtLogin": "Launch Sortomat at login",
        "general.privacyNote": "Note: a file's name, metadata and (unless a rule is metadata-only) a text excerpt are sent to the model to classify it. For images and scanned PDFs the excerpt is text recognized on this Mac; nothing else leaves the machine.",

        // Paths
        "path.choose": "Choose…",
        "path.placeholder": "/path/to/folder",

        // Preview / dry-run

        // Journal / undo
        "journal.title": "History",
        "journal.empty": "No moves recorded yet.",
        "journal.undo": "Undo",
        "journal.undoAll": "Undo last check",
        "journal.undone": "Undone: %@",
        "journal.undoFailed": "Couldn't undo %@: %@",
        "headless.unknownCommand": "Unknown command: %@",
        "journal.undo.sourceOccupied": "A file is already at the original location: %@",
        "journal.undo.destinationMissing": "The moved file is no longer at: %@",
        "journal.undo.destinationModified": "The copy at %@ no longer matches the original, so it wasn't deleted.",
        "journal.undoBatchDone.one": "Undid 1 move.",
        "journal.undoBatchDone.other": "Undid %d moves.",
        "journal.undoBatchFailed.one": "1 couldn't be undone.",
        "journal.undoBatchFailed.other": "%d couldn't be undone.",
        "headless.nothingToUndo": "Nothing to undo.",
        "headless.undone": "Undone: %@ → %@",
        "headless.undoFailed": "Failed: %@: %@",

        // Activity messages (logged)
        "activity.skipped": "[%@] Skipped: %@ — %@",
        "activity.moved": "[%@] %@ → %@",
        "activity.copied": "[%@] Copied %@ → %@",
        "activity.duplicate": "[%@] Duplicate: %@ already exists as %@",

        // MARK: Rule engine
        "engine.reason.noStepMatched": "No step matched",
        "engine.step.unnamed": "Step %@",
        "engine.summary.matched": "matched «%@» (%@) → %@",
        "engine.summary.noMatchSkip": "No step matched — left alone",
        "engine.summary.noMatchQuarantine": "No step matched — filed as unsure",
        "engine.summary.noMatchModel": "No step matched — asking the model",
        "engine.summary.noSteps": "This rule has no steps yet",
        "template.error.unterminated": "A «{» is never closed",
        "template.error.emptyToken": "Empty «{}»",
        "template.error.unknownFilter": "Unknown filter «%@»",
        "migration.stepsFromPreRules": "%@ pre-rules became steps",
        "migration.ageUsesModified": "Age conditions still use the modification date — the editor can switch them to «date added»",
        "migration.downgradeGuard": "Needs a newer Sortomat",
        "migration.downgradeFallback": "Leave anything else alone",
        "preview.origin.step": "Rule step",
        "preview.origin.fallback": "Fallback",

        // MARK: Rule steps
        "rule.steps.section": "Steps",
        "rule.steps.help": "Each step is «if … then …». The first step that matches claims the file, unless it says to keep checking. Steps cost nothing and never call the model unless you ask them to.",
        "rule.steps.add": "Add step",
        "rule.tryIt.pick": "Try it on a file…",
        "rule.tryIt.count": "How many match now?",
        "rule.tryIt.help": "Both answers are free: the steps run without the model, without moving anything, and without recording anything.",
        "rule.tryIt.would": "%@ → %@ %@\n%@",
        "rule.tryIt.skip": "%@ would be left alone.\n%@",
        "rule.tryIt.needsModel": "%@ would go to the model — no step claimed it.\n%@",
        "rule.tryIt.matches": "Claimed by these steps: %@ of %@ — for the model: %@.",
        "rule.fallback": "If no step matches",
        "rule.fallback.askModel": "Ask the model",
        "rule.fallback.skip": "Leave the file alone",
        "rule.fallback.quarantine": "File it as unsure",
        "rule.fallback.help": "Asking the model is what this rule did before steps existed.",
        "step.name": "Step name",
        "step.enabled.help": "Turn this step off without deleting it",
        "step.delete": "Delete step",
        "step.when": "If",
        "step.then": "Then",
        "step.when.empty": "No conditions yet — «all of these» and «none of these» claim every file; «any of these» matches nothing.",
        "step.then.empty": "No actions yet — this step does nothing.",
        "step.mode.all": "all of these",
        "step.mode.any": "any of these",
        "step.mode.none": "none of these",
        "step.condition.add": "Add condition",
        "step.action.add": "Add action",
        "step.condition.nested": "Nested group (%@, conditions: %@) — edit in config.json",
        "step.condition.needsContent": "This rule never reads file contents, so this condition can never match.",
        "step.action.template": "Destination, e.g. Finance/{modified|date:'yyyy'}/{name}",
        "step.action.tags": "Tags, comma separated",
        "step.action.prompt": "What to ask — leave empty to use the rule's instruction",
        "step.join.all": " and ",
        "step.join.any": " or ",
        "step.sentence": "If %@, then %@.",
        "step.sentence.noAction": "If %@, then nothing happens.",
        "step.sentence.anyFile": "any file",
        "step.sentence.none": "none of: %@",
        "activity.quarantined": "[%@] Quarantined: %@ → %@ (%@)",
        "activity.preRuleSkip": "[%@] Pre-rule skip: %@ (%@)",
        "activity.error": "[%@] ERROR on %@: %@",
        "activity.missingWatch": "[%@] Watched folder missing: %@",
        "activity.wouldMove": "[%@] Would move %@ → %@",
        "activity.wouldSkip": "[%@] Would skip %@ — %@",
        "activity.budgetReached": "[%@] Per-check model-call budget reached (%d).",
        "activity.stalePlan": "[%@] Skipped %@: the file changed after this suggestion was made — check again.",
        "activity.keyDeferred.one": "[%2$@] %1$d file needs the model, but no API key is set — pre-rules still ran.",
        "activity.keyDeferred.other": "[%2$@] %1$d files need the model, but no API key is set — pre-rules still ran.",
        "activity.modelHeld.one": "[%2$@] %1$d file is waiting for the model — the monthly limit is reached. Pre-rules still ran.",
        "activity.modelHeld.other": "[%2$@] %1$d files are waiting for the model — the monthly limit is reached. Pre-rules still ran.",

        // Why nothing is running
        "hold.lowPower": "Paused — Low Power Mode",
        "hold.onBattery": "Paused — on battery",
        "hold.budget": "Held — monthly limit reached",

        // Decision memo
        "memo.remembered": "%@ · remembered from an identical file",
        "memo.rememberedBare": "Remembered from an identical file",

        // Notifications
        "notify.filed.one": "Filed 1 file",
        "notify.filed.other": "Filed %d files",
        "notify.failed.one": "1 file couldn't be filed",
        "notify.failed.other": "%d files couldn't be filed",
        "notify.andMore.one": "and 1 more",
        "notify.andMore.other": "and %d more",
        "notify.action.undo": "Undo",
        "notify.action.reveal": "Show in Finder",
        "notify.action.log": "Open log",
        "notify.undone.one": "Put 1 file back",
        "notify.undone.other": "Put %d files back",
        "notify.undoFailed.one": "1 file couldn't be put back",
        "notify.undoFailed.other": "%d files couldn't be put back",
        "notify.undoNothing": "Nothing left to put back",
        "notify.undoNothing.body": "These files were already put back, or the record of the move is no longer kept.",
        "notify.failuresMore.one": "%2$@ (and %1$d more failure)",
        "notify.failuresMore.other": "%2$@ (and %1$d more failures)",

        // Errors
        "error.unsafePath": "Unsafe destination path: %@",
        "error.tooManyCollisions": "Too many name collisions: %@",
        "error.badApiBase": "Invalid API base URL",
        "error.noKey": "No API key (Keychain or MISTRAL_API_KEY / SORTOMAT_API_KEY).",
        "error.http": "Model API HTTP %d: %@",
        "error.badResponse": "Unexpected API response: %@",
        "error.missingPath": "relative_path missing for action=move",
        "error.sourceVanished": "Source file vanished before it could be filed",
        "error.verifyFailed": "Cross-volume copy could not be verified; original kept",
        "component.unknown": "Unknown",

        // Decision reasons (shown in Review rows and logged)
        "reason.preRule": "pre-rule «%@»",
        "reason.notInTaxonomy": "folder «%@» is not in the allowed set",
        "reason.lowConfidence": "confidence %d%% is below the threshold",
        "reason.noConfidence": "the model reported no usable confidence",
        "reason.ruleDoesNotApply": "rule does not apply",

        // Journal
        "journal.undo.destinationReplaced": "The file at %@ is not the one Sortomat put there (it was edited or replaced since), so it was left alone.",
        "journal.writeFailed": "Couldn't record the move of %@ in the journal (%@) — it can't be undone from History.",

        // Command line
        "headless.usage": """
        Usage: Sortomat <command>

          scan-once   Sort every enabled rule once, then exit (1 on any error).
          preview     Print what scan-once would do, without touching files.
          undo        Reverse the most recent batch of moves.
          version     Print the version and exit.
          help        Show this text.

        Run with no arguments to start the menu-bar app.
        SORTOMAT_API_KEY overrides the Keychain key; SORTOMAT_CONFIG_DIR the config folder.
        """,
        "headless.version": "Sortomat %@ (%@)",
        "process.locked": "Another Sortomat process is using this configuration — not running, to avoid clobbering its records.",
        "process.lockWarning": "Warning: another Sortomat process holds this configuration; concurrent runs may conflict.",

        // Templates
        "template.tidy.title": "Tidy up by kind",
        "template.tidy.summary": "Sort images, documents, media and archives into folders. Needs no API key.",
        "template.tidy.folder.images": "Images",
        "template.tidy.folder.documents": "Documents",
        "template.tidy.folder.media": "Media",
        "template.tidy.folder.archives": "Archives",
        "template.ebooks.title": "E-books",
        "template.ebooks.summary": "Sort EPUBs into Genre / Author / Title.",
        "template.ebooks.prompt": """
        Sort e-books (EPUB) into the structure {Genre}/{Last name, First name}/{Title}.epub.

        Pick the genre from the provided list. The author as "Last name, First name"
        (a single name or pseudonym stays as-is). Title without series-number
        prefixes like "01 - " and without publisher notes. Skip files that are
        not e-books.
        """,
        "template.screenshots.title": "Screenshots",
        "template.screenshots.summary": "Route screenshots to the matching project folder.",
        "template.screenshots.preSkip": "Everything else",
        "template.screenshots.prompt": """
        File screenshots into the matching project or topic folder, e.g.
        {Project}/{YYYY-MM}/{filename}. Judge from the text recognized in the
        screenshot (window titles, app names, headings), the file name and its
        timestamps. If no project is recognizable, file it under
        "General/{YYYY-MM}".
        """,
        "template.invoices.title": "Invoices & receipts",
        "template.invoices.summary": "File PDFs under Year / Sender / Date Subject.",
        "template.invoices.prompt": """
        File invoices and receipts under {Year}/{Sender}/{YYYY-MM-DD Subject}.pdf.
        Use the sender, invoice date and subject from the document. Skip
        documents that are not invoices or receipts.
        """,
        "template.blank.title": "Blank rule",
        "template.blank.summary": "Start from scratch.",

        // About
        "about.tagline": "Hazel, but the rule is a sentence.",
        "about.version": "Version %@",
        "about.help": "Help",

        // Updates
        "updates.available.title": "%@ %@ is available",
        "updates.available.body": "You have %@. Would you like to download the update?",
        "updates.available.download": "Download",
        "updates.available.later": "Remind Me Later",
        "updates.available.skip": "Skip This Version",
        "updates.upToDate.title": "You're up to date",
        "updates.upToDate.body": "%@ %@ is the latest version.",
        "updates.failed.title": "Couldn't check for updates",
        "updates.parseFailed": "The version numbers couldn't be compared.",
        "updates.ok": "OK",
        "updates.lastResult.available": "Update available: %@",
        "updates.lastResult.upToDate": "You're up to date (%@).",
        "updates.error.http": "GitHub API returned HTTP %d.",
        "updates.error.noRelease": "No suitable release found.",
        // Rule validation
        "validate.errors.one": "1 problem",
        "validate.errors.other": "%d problems",
        "validate.warnings.one": "1 note",
        "validate.warnings.other": "%d notes",
        "step.match.result": "Matches: %@ of %@",
        "step.match.counting": "Counting…",
        "step.match.idle": "Count what matches",
        "step.match.help": "Counts the files in the watched folder this step claims right now. Nothing is moved and nothing is paid for.",
        "validate.section": "Before you enable this",
        "validate.stepLabel": "Step %@",
        "validate.stepLabelNamed": "Step %@ · %@",
        "validate.rule.noWatchFolder": "No watched folder: this rule has nothing to look at.",
        "validate.rule.noTargetFolder": "No destination folder: there is nowhere to file anything.",
        "validate.rule.doesNothing": "No steps yet, and unmatched files are skipped — this rule does nothing.",
        "validate.rule.modelWithoutPrompt": "The model is asked, but there is no instruction telling it what to do. Every file would be a paid guess.",
        "validate.rule.incompleteRoot": "A destination folder needs both a name and a path.",
        "validate.rule.duplicateRoot": "Two destination folders are both called «%@».",
        "validate.step.noActions": "This step matches and then does nothing.",
        "validate.step.twoPlacements": "Two actions both decide where the file goes (%@ and %@). The first one wins; the second never runs.",
        "validate.step.neverMatches": "«Any of» with no conditions can never be true, so this step never runs.",
        "validate.step.unreachable": "Step %@ matches every file and keeps it, so this step is never reached.",
        "validate.condition.emptyGroup": "An empty group of conditions has no effect.",
        "validate.condition.unknownAttribute": "«%@» is not something this version can look at.",
        "validate.condition.unknownOperator": "«%@» is not a comparison this version knows.",
        "validate.condition.noValue": "«%@» needs something to compare against.",
        "validate.condition.betweenNeedsTwo": "«between» needs exactly two values.",
        "validate.condition.blockedByPrivacy": "This rule never reads file contents, so «%@» can never have a value. Turn off metadata-only, or test something else.",
        "validate.condition.metadataOnlyValue": "This rule never reads file contents, so «%@» is only known for files Spotlight has already indexed.",
        "validate.step.problems": "%@ in this step",
        "validate.condition.unsafeRegex": "This pattern can take exponential time on some names and is rejected for that reason.",
        "validate.condition.badRegex": "This is not a valid regular expression.",
        "validate.condition.captureWithoutRegex": "Only «matches pattern» captures anything; this name will never be filled in.",
        "validate.condition.modelNotSupported": "Asking the model inside a condition isn't supported yet, so this can never be true. Use the «ask the model» action instead.",
        "validate.action.unknownType": "«%@» is not an action this version can perform.",
        "validate.action.unknownRoot": "There is no destination folder called «%@».",
        "validate.action.notAppliedYet": "«%@» is recorded but not carried out by this version yet — the rest of the step still runs.",
        "validate.action.trashMoves": "This version leaves the file where it is instead of moving it to the Trash.",
        "validate.action.noTags": "No tags given.",
        "validate.action.noShortcut": "No shortcut name given.",
        "validate.action.badTemplate": "The destination is not valid: %@",
        "validate.action.unknownToken": "«{%@}» is not a value this version can fill in — it will be left empty.",
        "validate.action.captureWithoutSource": "This uses a captured value, but no condition in this rule captures anything.",
        "validate.action.nameCanBeEmpty": "If those values are missing the file would arrive with no name at all.",
    ]

    // MARK: - German

    static let german: [String: String] = [
        "app.status.active.one": "Aktiv – 1 Regel",
        "app.status.active.other": "Aktiv – %d Regeln",
        "app.status.paused": "Pausiert",
        "app.status.noKey": "⚠️ Kein API-Key hinterlegt",
        "app.lastScan": "Letzte Prüfung: %@",
        "menu.resume": "Fortsetzen",
        "menu.pause": "Pausieren",
        "menu.scanNow": "Jetzt prüfen",
        "menu.previewNow": "Änderungen vorschauen…",

        // Main window
        "main.window.title": "Sortomat",
        "menu.openMain": "Sortomat öffnen",
        "menu.openHistory": "Verlauf…",
        "sidebar.inbox": "Eingang",
        "sidebar.history": "Verlauf",
        "sidebar.noFolder": "Kein Ordner gesetzt",

        // How a rule runs — one choice instead of two toggles
        "mode.automatic": "Automatisch",
        "mode.automatic.help": "Legt passende Dateien selbstständig ab. Alles lässt sich im Verlauf rückgängig machen.",
        "mode.askFirst": "Erst fragen",
        "mode.askFirst.help": "Ermittelt, was zu tun wäre, und legt es zur Freigabe in den Eingang.",
        "mode.off": "Aus",
        "mode.off.help": "Läuft gar nicht.",

        // How sure the model was
        "heat.certain": "Sicher",
        "heat.sure": "Ziemlich sicher",
        "heat.probably": "Wahrscheinlich",
        "heat.unsure": "Unsicher",
        "heat.exact": "Exakter Treffer",
        "heat.help": "Wie sicher sich Sortomat hier ist. «Exakter Treffer» heisst: ein Schritt hat entschieden – ganz ohne Raten.",

        // Where a decision came from — the trust signal
        "origin.step": "Schritt",
        "origin.model": "Modell",
        "origin.folders": "In deinen Ordnern gehalten",
        "origin.unsure": "Zu unsicher zum Ablegen",
        "origin.fallback": "Kein Schritt hat gepasst",
        "origin.system": "Sortomat",

        // Inbox
        "inbox.count.one": "1 Datei wartet",
        "inbox.count.other": "%d Dateien warten",
        "inbox.check": "Jetzt prüfen",
        "inbox.apply": "Ablegen",
        "inbox.skip": "Überspringen",
        "inbox.applyAll": "Alle ablegen",
        "inbox.skipAll": "Alle überspringen",
        "inbox.why": "Warum?",
        "inbox.why.hide": "Begründung ausblenden",
        "inbox.reveal": "Im Finder zeigen",
        "inbox.undoLast": "Rückgängig",
        "inbox.applied.one": "1 Datei abgelegt.",
        "inbox.applied.other": "%d Dateien abgelegt.",
        "inbox.skipped.one": "1 Datei übersprungen.",
        "inbox.skipped.other": "%d Dateien übersprungen.",
        "inbox.empty.title": "Nichts abzulegen",
        "inbox.empty": "Sortomat beobachtet deine Ordner. Was verschoben werden soll, erscheint zuerst hier.",
        "inbox.empty.noKey.title": "Kein API-Key hinterlegt",
        "inbox.empty.noKey": "Schritte laufen auch ohne Key, aber nichts kann ans Modell gehen. Trage in den Einstellungen einen Key ein – oder baue Regeln allein aus Schritten.",
        "inbox.action.move": "Verschieben nach %@",
        "inbox.action.copy": "Kopieren nach %@",
        "inbox.action.unsure": "Unsicher – parken in %@",
        "inbox.action.duplicate": "Schon abgelegt – dieselbe Datei",
        "inbox.action.skip": "Liegen lassen",

        // History
        "history.empty.title": "Noch nichts abgelegt",
        "history.refresh": "Neu laden",
        "history.reveal": "Im Finder zeigen",
        "rules.empty.message": "Wähle links eine Regel oder lege mit + eine neue an.",
        "menu.noActivity": "Noch keine Aktivität",
        "menu.recentActivity": "Letzte Aktivität",
        "menu.openLog": "Protokoll öffnen",
        "menu.settings": "Regeln & Einstellungen…",
        "menu.quit": "Beenden",
        "menu.pendingReview.one": "1 Änderung zur Prüfung…",
        "menu.pendingReview.other": "%d Änderungen zur Prüfung…",
        "menu.spend": "Geschätzte Kosten (diesen Monat): %@",
        "menu.checkUpdates": "Nach Updates suchen…",
        "menu.close": "Schliessen",
        "menu.file": "Ablage",
        "menu.edit": "Bearbeiten",
        "menu.about": "Über Sortomat",
        "menu.hide": "Sortomat ausblenden",
        "menu.hideOthers": "Andere ausblenden",
        "menu.showAll": "Alle einblenden",
        "menu.quitApp": "Sortomat beenden",
        "edit.undo": "Widerrufen",
        "edit.redo": "Wiederholen",
        "edit.cut": "Ausschneiden",
        "edit.copy": "Kopieren",
        "edit.paste": "Einsetzen",
        "edit.delete": "Löschen",
        "edit.selectAll": "Alles auswählen",

        "settings.window.title": "Sortomat – Regeln & Einstellungen",
        "tab.general": "Einstellungen",
        "tab.about": "Über",

        "rules.empty.title": "Regel auswählen oder mit + anlegen",
        "rules.delete.title": "Regel «%@» löschen?",
        "rules.delete.message": "Prompt, Taxonomie und Vorregeln werden mitgelöscht, und Sortomat vergisst, welche Dateien sie bereits behandelt hat. Das kann nicht rückgängig gemacht werden.",
        "rules.delete.confirm": "Regel löschen",
        "rules.export": "Regel exportieren…",
        "rules.import": "Regel importieren…",
        "rules.export.done": "«%@» exportiert.",
        "rules.import.done": "Importiert – deaktiviert und im Vorschau-Modus. Ordner setzen, dann aktivieren.",
        "rules.pack.failed": "Regeldatei konnte nicht verarbeitet werden: %@",
        "rules.pack.unsupportedFormat": "Diese Regeldatei verwendet ein neueres Format (%d), als diese Sortomat-Version versteht.",
        "rules.add": "Regel hinzufügen",
        "rules.remove": "Regel entfernen",
        "rules.duplicate": "Duplizieren",

        "rule.defaultName": "Neue Regel",
        "rule.defaultQuarantine": "_Quarantäne",
        "rule.name": "Name:",
        "rule.enabled": "Regel aktiv",
        "rule.dryRun": "Nur Vorschau (keine Dateien bewegen)",
        "rule.priority": "Priorität:",
        "rule.watchFolder": "Überwachter Ordner:",
        "rule.targetFolder": "Zielordner:",
        "rule.recursive": "Unterordner einbeziehen",
        "rule.extensions": "Dateiendungen:",
        "rule.extensions.prompt": "z.B. epub, pdf – leer = alle Dateien",
        "rule.copy": "Kopieren statt verschieben",
        "rule.privacy": "Datenschutz:",
        "rule.privacy.full": "Name, Metadaten & Textauszug senden",
        "rule.privacy.metadataOnly": "Nur Name & Metadaten senden (Inhalt bleibt lokal)",
        "rule.prompt.section": "Sortier-Anweisung (Prompt)",
        "rule.prompt.help": "Beschreibe, welche Dateien betroffen sind und wie die Zielstruktur aussehen soll, z.B. «{Genre}/{Nachname, Vorname}/{Titel}.epub».",
        "rule.taxonomy.section": "Erlaubte oberste Ordner (Taxonomie)",
        "rule.taxonomy.help": "Einer pro Zeile. Wenn gesetzt, darf das Modell nur in diese obersten Ordner einsortieren; alles andere landet im Quarantäne-Ordner.",
        "rule.taxonomy.prompt": "Leer lassen, damit das Modell frei wählt",
        "rule.quarantine": "Quarantäne-Unterordner:",
        "rule.confidence": "Konfidenz-Schwelle: %d%%",
        "rule.confidence.help": "Klassifikationen unter dieser Konfidenz landen im Quarantäne-Ordner statt einsortiert zu werden. 0 deaktiviert die Prüfung.",
        "rule.preRules.section": "Deterministische Vorregeln",
        "rule.preRules.help": "Werden vor dem Modell der Reihe nach geprüft. Erste Übereinstimmung gewinnt. Kostenlos und vorhersehbar – das Modell übernimmt nur, was durchfällt.",
        "rule.preRules.add": "Vorregel hinzufügen",
        "rule.preRule.match": "Prüfung",
        "rule.preRule.pattern": "Muster",
        "rule.preRule.action": "Aktion",
        "rule.preRule.route": "Ablegen in",
        "rule.editingPaused": "Diese Regel pausiert, solange sie hier geöffnet ist – sie läuft weiter, sobald du wegwechselst.",
        "rule.validate.watchMissing": "Der überwachte Ordner existiert nicht.",
        "rule.validate.targetMissing": "Der Zielordner existiert noch nicht – er wird bei der ersten Verwendung angelegt.",
        "rule.validate.samePath": "Überwachter und Zielordner sind identisch – es wird nie etwas einsortiert.",
        "rule.validate.watchInsideTarget": "Der überwachte Ordner liegt im Zielordner – seine Dateien gelten als bereits einsortiert, es wird nichts gefunden.",
        "rule.validate.targetInsideWatch": "Der Zielordner liegt im überwachten Ordner. Einsortierte Dateien bleiben im überwachten Baum; Sortomat überspringt sie, aber ein Zielordner ausserhalb ist leichter nachvollziehbar.",
        "rule.validate.badRegex": "Dieser reguläre Ausdruck ist ungültig – die Vorregel trifft nie zu.",

        "match.glob": "Name-Glob",
        "match.regex": "Name-Regex",
        "match.kind": "Art",
        "match.olderThanDays": "Älter als (Tage)",
        "match.newerThanDays": "Neuer als (Tage)",
        "action.route": "In Ordner ablegen",
        "action.skip": "Überspringen",
        "action.useLLM": "Modell fragen",
        "preRule.name.prompt": "Optionaler Name",
        "preRule.moveUp": "Nach oben",
        "preRule.moveDown": "Nach unten",
        "preRule.delete": "Vorregel löschen",
        "preRule.route.help": "Relativ zum Zielordner. Platzhalter: {name} {ext} {year} {month} {day}.",
        "preRule.help.glob": "Platzhalter: * steht für Beliebiges, ? für ein Zeichen.",
        "preRule.help.regex": "Ein regulärer Ausdruck, geprüft gegen den Dateinamen.",
        "preRule.help.kind": "Eines von: image, video, audio, pdf, archive, text, ebook, document.",
        "preRule.help.days": "Eine ganze Zahl von Tagen.",
        "preRule.sum.glob": "der Name auf «%@» passt",
        "preRule.sum.regex": "der Name auf den Regex «%@» passt",
        "preRule.sum.kind": "die Dateiart %@ ist",
        "preRule.sum.olderThanDays": "die Datei älter als %@ Tage ist",
        "preRule.sum.newerThanDays": "die Datei neuer als %@ Tage ist",
        "preRule.sum.route": "lege sie in «%@» ab",
        "preRule.sum.skip": "überspringe sie",
        "preRule.sum.useLLM": "lass das Modell entscheiden",
        "preRule.sum.template": "Wenn %@, %@.",
        "preRule.sum.placeholder": "…",

        "general.provider.section": "Modell-Anbieter",
        "general.apiKey": "API-Key:",
        "general.apiKey.save": "Sichern",
        "general.apiKey.saved": "Im Schlüsselbund gespeichert.",
        "general.apiKey.saveFailed": "Konnte nicht im Schlüsselbund gespeichert werden – der Key wurde nicht übernommen.",
        "general.apiKey.placeholder.missing": "Noch kein Key hinterlegt",
        "general.apiKey.placeholder.set": "••••••••  (gespeichert)",
        "general.model": "Modell:",
        "general.apiBase": "API-Basis-URL:",
        "general.requiresKey": "Dieser Anbieter benötigt einen API-Key",
        "general.localHint": "Für ein lokales Modell (Ollama, LM Studio) die Basis-URL darauf zeigen lassen und «benötigt API-Key» ausschalten, z.B. http://localhost:11434.",
        "general.pricing.section": "Kostenschätzung",
        "general.pricing.input": "Eingabe $/1M Tokens:",
        "general.pricing.output": "Ausgabe $/1M Tokens:",
        "general.pricing.currency": "Währung (ISO-Code):",
        "general.monthlyBudget": "Stopp ab (pro Monat, 0 = kein Limit):",
        "general.monthlyBudget.help": "Das Limit pro Prüfung begrenzt einen einzelnen Schub. Dieses begrenzt den Monat: ist die geschätzte Summe überschritten, legen Schritte weiterhin kostenlos ab, und Dateien fürs Modell warten.",
        "general.monthlyBudget.reached": "Monatslimit erreicht – %@ ausgegeben. Schritte laufen weiter; ans Modell geht nichts.",
        "general.onlyOnPower": "Nur am Stromnetz prüfen",
        "general.pauseInLowPower": "Im Stromsparmodus pausieren",
        "general.power.help": "Eine Datei zu lesen kann OCR, einen Hash über den ganzen Inhalt und eine kostenpflichtige Anfrage bedeuten. Im Akkubetrieb ist das die teuerste denkbare Arbeit zum schlechtesten denkbaren Zeitpunkt.",
        "general.watch.section": "Überwachung",
        "general.interval": "Prüfintervall: %d s",
        "general.interval.help": "Ordner werden zusätzlich sofort geprüft, wenn sich etwas ändert. Das Intervall ist nur das Sicherheitsnetz.",
        "general.concurrency": "Max. gleichzeitige Klassifikationen: %d",
        "general.budget": "Max. Modell-Aufrufe pro Prüfung (0 = unbegrenzt): %d",
        "general.notifications": "Über einsortierte Dateien und Fehler benachrichtigen",
        "general.launchAtLogin": "Sortomat beim Anmelden starten",
        "general.privacyNote": "Hinweis: Dateiname, Metadaten und (sofern die Regel nicht «nur Metadaten» ist) ein Textauszug werden zur Klassifikation an das Modell gesendet. Bei Bildern und gescannten PDFs ist der Auszug auf diesem Mac erkannter Text; nichts anderes verlässt den Rechner.",

        "path.choose": "Auswählen…",
        "path.placeholder": "/Pfad/zum/Ordner",


        "journal.title": "Verlauf",
        "journal.empty": "Noch keine Bewegungen aufgezeichnet.",
        "journal.undo": "Rückgängig",
        "journal.undoAll": "Letzte Prüfung rückgängig",
        "journal.undone": "Rückgängig gemacht: %@",
        "journal.undoFailed": "«%@» konnte nicht rückgängig gemacht werden: %@",
        "headless.unknownCommand": "Unbekannter Befehl: %@",
        "journal.undo.sourceOccupied": "Am ursprünglichen Ort liegt bereits eine Datei: %@",
        "journal.undo.destinationMissing": "Die verschobene Datei ist nicht mehr unter: %@",
        "journal.undo.destinationModified": "Die Kopie unter %@ stimmt nicht mehr mit dem Original überein und wurde deshalb nicht gelöscht.",
        "journal.undoBatchDone.one": "1 Bewegung rückgängig gemacht.",
        "journal.undoBatchDone.other": "%d Bewegungen rückgängig gemacht.",
        "journal.undoBatchFailed.one": "1 konnte nicht rückgängig gemacht werden.",
        "journal.undoBatchFailed.other": "%d konnten nicht rückgängig gemacht werden.",
        "headless.nothingToUndo": "Nichts rückgängig zu machen.",
        "headless.undone": "Rückgängig: %@ → %@",
        "headless.undoFailed": "Fehlgeschlagen: %@: %@",

        "activity.skipped": "[%@] Übersprungen: %@ – %@",
        "activity.moved": "[%@] %@ → %@",
        "activity.copied": "[%@] Kopiert %@ → %@",
        "activity.duplicate": "[%@] Duplikat: %@ existiert bereits als %@",

        // MARK: Regel-Engine
        "engine.reason.noStepMatched": "Kein Schritt hat gepasst",
        "engine.step.unnamed": "Schritt %@",
        "engine.summary.matched": "passte auf «%@» (%@) → %@",
        "engine.summary.noMatchSkip": "Kein Schritt hat gepasst – unangetastet gelassen",
        "engine.summary.noMatchQuarantine": "Kein Schritt hat gepasst – als unsicher abgelegt",
        "engine.summary.noMatchModel": "Kein Schritt hat gepasst – das Modell wird gefragt",
        "engine.summary.noSteps": "Diese Regel hat noch keine Schritte",
        "template.error.unterminated": "Eine «{» wird nie geschlossen",
        "template.error.emptyToken": "Leeres «{}»",
        "template.error.unknownFilter": "Unbekannter Filter «%@»",
        "migration.stepsFromPreRules": "%@ Vorregeln wurden zu Schritten",
        "migration.ageUsesModified": "Altersbedingungen nutzen weiterhin das Änderungsdatum – im Editor auf «hinzugefügt am» umstellbar",
        "migration.downgradeGuard": "Benötigt ein neueres Sortomat",
        "migration.downgradeFallback": "Alles andere in Ruhe lassen",
        "preview.origin.step": "Regelschritt",
        "preview.origin.fallback": "Auffangregel",

        // MARK: Regelschritte
        "rule.steps.section": "Schritte",
        "rule.steps.help": "Jeder Schritt ist ein «wenn … dann …». Der erste passende Schritt übernimmt die Datei, ausser er sagt, dass weitergeprüft werden soll. Schritte kosten nichts und fragen das Modell nur, wenn du es verlangst.",
        "rule.steps.add": "Schritt hinzufügen",
        "rule.tryIt.pick": "An einer Datei ausprobieren…",
        "rule.tryIt.count": "Wie viele passen gerade?",
        "rule.tryIt.help": "Beide Antworten sind gratis: die Schritte laufen ohne Modell, ohne etwas zu verschieben und ohne etwas festzuhalten.",
        "rule.tryIt.would": "%@ → %@ %@\n%@",
        "rule.tryIt.skip": "%@ bliebe unangetastet.\n%@",
        "rule.tryIt.needsModel": "%@ ginge ans Modell – kein Schritt hat sie übernommen.\n%@",
        "rule.tryIt.matches": "Von diesen Schritten übernommen: %@ von %@ – fürs Modell: %@.",
        "rule.fallback": "Wenn kein Schritt passt",
        "rule.fallback.askModel": "Das Modell fragen",
        "rule.fallback.skip": "Die Datei unangetastet lassen",
        "rule.fallback.quarantine": "Als unsicher ablegen",
        "rule.fallback.help": "Das Modell zu fragen ist, was diese Regel vor den Schritten getan hat.",
        "step.name": "Name des Schritts",
        "step.enabled.help": "Schritt deaktivieren, ohne ihn zu löschen",
        "step.delete": "Schritt löschen",
        "step.when": "Wenn",
        "step.then": "Dann",
        "step.when.empty": "Noch keine Bedingungen – «alle davon» und «keine davon» übernehmen jede Datei; «eine davon» trifft auf nichts zu.",
        "step.then.empty": "Noch keine Aktionen – dieser Schritt tut nichts.",
        "step.mode.all": "alle davon",
        "step.mode.any": "eine davon",
        "step.mode.none": "keine davon",
        "step.condition.add": "Bedingung hinzufügen",
        "step.action.add": "Aktion hinzufügen",
        "step.condition.nested": "Verschachtelte Gruppe (%@, Bedingungen: %@) – in config.json bearbeiten",
        "step.condition.needsContent": "Diese Regel liest keine Dateiinhalte, diese Bedingung kann also nie passen.",
        "step.action.template": "Ziel, z. B. Finanzen/{modified|date:'yyyy'}/{name}",
        "step.action.tags": "Tags, mit Komma getrennt",
        "step.action.prompt": "Was gefragt wird – leer lassen für die Anweisung der Regel",
        "step.join.all": " und ",
        "step.join.any": " oder ",
        "step.sentence": "Wenn %@, dann %@.",
        "step.sentence.noAction": "Wenn %@, passiert nichts.",
        "step.sentence.anyFile": "jede Datei",
        "step.sentence.none": "keines von: %@",
        "activity.quarantined": "[%@] Quarantäne: %@ → %@ (%@)",
        "activity.preRuleSkip": "[%@] Vorregel-Skip: %@ (%@)",
        "activity.error": "[%@] FEHLER bei %@: %@",
        "activity.missingWatch": "[%@] Überwachter Ordner fehlt: %@",
        "activity.wouldMove": "[%@] Würde verschieben %@ → %@",
        "activity.wouldSkip": "[%@] Würde überspringen %@ – %@",
        "activity.budgetReached": "[%@] Modell-Aufruf-Budget pro Prüfung erreicht (%d).",
        "activity.stalePlan": "[%@] Übersprungen: %@ wurde seit dem Vorschlag geändert – Vorschau aktualisieren.",
        "activity.keyDeferred.one": "[%2$@] %1$d Datei benötigt das Modell, aber kein API-Key ist hinterlegt – Vorregeln liefen trotzdem.",
        "activity.keyDeferred.other": "[%2$@] %1$d Dateien benötigen das Modell, aber kein API-Key ist hinterlegt – Vorregeln liefen trotzdem.",
        "activity.modelHeld.one": "[%2$@] %1$d Datei wartet auf das Modell – das Monatslimit ist erreicht. Vorregeln liefen trotzdem.",
        "activity.modelHeld.other": "[%2$@] %1$d Dateien warten auf das Modell – das Monatslimit ist erreicht. Vorregeln liefen trotzdem.",

        // Why nothing is running
        "hold.lowPower": "Pausiert – Stromsparmodus",
        "hold.onBattery": "Pausiert – Akkubetrieb",
        "hold.budget": "Angehalten – Monatslimit erreicht",

        "memo.remembered": "%@ · von einer identischen Datei übernommen",
        "memo.rememberedBare": "Von einer identischen Datei übernommen",

        "notify.filed.one": "1 Datei einsortiert",
        "notify.filed.other": "%d Dateien einsortiert",
        "notify.failed.one": "1 Datei konnte nicht abgelegt werden",
        "notify.failed.other": "%d Dateien konnten nicht abgelegt werden",
        "notify.andMore.one": "und 1 weitere",
        "notify.andMore.other": "und %d weitere",
        "notify.action.undo": "Rückgängig",
        "notify.action.reveal": "Im Finder zeigen",
        "notify.action.log": "Protokoll öffnen",
        "notify.undone.one": "1 Datei zurückgelegt",
        "notify.undone.other": "%d Dateien zurückgelegt",
        "notify.undoFailed.one": "1 Datei konnte nicht zurückgelegt werden",
        "notify.undoFailed.other": "%d Dateien konnten nicht zurückgelegt werden",
        "notify.undoNothing": "Nichts mehr zurückzulegen",
        "notify.undoNothing.body": "Diese Dateien wurden bereits zurückgelegt, oder der Eintrag dazu wird nicht mehr aufbewahrt.",
        "notify.failuresMore.one": "%2$@ (und %1$d weiterer Fehler)",
        "notify.failuresMore.other": "%2$@ (und %1$d weitere Fehler)",

        "error.unsafePath": "Unsicherer Zielpfad: %@",
        "error.tooManyCollisions": "Zu viele Namenskollisionen: %@",
        "error.badApiBase": "Ungültige API-Basis-URL",
        "error.noKey": "Kein API-Key (Schlüsselbund oder MISTRAL_API_KEY / SORTOMAT_API_KEY).",
        "error.http": "Modell-API HTTP %d: %@",
        "error.badResponse": "Unerwartete API-Antwort: %@",
        "error.missingPath": "relative_path fehlt bei action=move",
        "error.sourceVanished": "Quelldatei verschwand, bevor sie einsortiert werden konnte",
        "error.verifyFailed": "Volumen-übergreifende Kopie nicht verifizierbar; Original behalten",
        "component.unknown": "Unbekannt",

        "reason.preRule": "Vorregel «%@»",
        "reason.notInTaxonomy": "Ordner «%@» ist nicht in der erlaubten Liste",
        "reason.lowConfidence": "Konfidenz %d%% liegt unter der Schwelle",
        "reason.noConfidence": "das Modell hat keine brauchbare Konfidenz gemeldet",
        "reason.ruleDoesNotApply": "Regel trifft nicht zu",

        "journal.undo.destinationReplaced": "Die Datei unter %@ ist nicht die, die Sortomat dort abgelegt hat (seither bearbeitet oder ersetzt) – sie wurde nicht angerührt.",
        "journal.writeFailed": "Die Verschiebung von %@ konnte nicht im Verlauf protokolliert werden (%@) – sie lässt sich dort nicht rückgängig machen.",

        "headless.usage": """
        Verwendung: Sortomat <Befehl>

          scan-once   Alle aktiven Regeln einmal ausführen, dann beenden (1 bei Fehlern).
          preview     Ausgeben, was scan-once tun würde, ohne Dateien anzufassen.
          undo        Den letzten Stapel Verschiebungen rückgängig machen.
          version     Version ausgeben und beenden.
          help        Diesen Text anzeigen.

        Ohne Argumente startet die Menüleisten-App.
        SORTOMAT_API_KEY übersteuert den Schlüsselbund-Key; SORTOMAT_CONFIG_DIR den Konfigurationsordner.
        """,
        "headless.version": "Sortomat %@ (%@)",
        "process.locked": "Ein anderer Sortomat-Prozess verwendet diese Konfiguration – Abbruch, um dessen Aufzeichnungen nicht zu überschreiben.",
        "process.lockWarning": "Warnung: Ein anderer Sortomat-Prozess hält diese Konfiguration; gleichzeitige Läufe können kollidieren.",

        "template.tidy.title": "Nach Art aufräumen",
        "template.tidy.summary": "Sortiert Bilder, Dokumente, Medien und Archive in Ordner. Braucht keinen API-Schlüssel.",
        "template.tidy.folder.images": "Bilder",
        "template.tidy.folder.documents": "Dokumente",
        "template.tidy.folder.media": "Medien",
        "template.tidy.folder.archives": "Archive",
        "template.ebooks.title": "E-Books",
        "template.ebooks.summary": "EPUBs nach Genre / Autor / Titel sortieren.",
        "template.ebooks.prompt": """
        Sortiere E-Books (EPUB) in die Struktur {Genre}/{Nachname, Vorname}/{Titel}.epub.

        Wähle das Genre aus der vorgegebenen Liste. Der Autor als "Nachname, Vorname"
        (bei nur einem Namen oder Pseudonym nur der Name). Titel ohne Reihennummern-
        Präfixe wie "01 - ", ohne Verlagsangaben. Dateien, die keine E-Books sind,
        überspringen.
        """,
        "template.screenshots.title": "Screenshots",
        "template.screenshots.summary": "Screenshots dem passenden Projektordner zuordnen.",
        "template.screenshots.preSkip": "Alles andere",
        "template.screenshots.prompt": """
        Ordne Screenshots dem passenden Projekt- oder Themenordner zu, z.B.
        {Projekt}/{JJJJ-MM}/{Dateiname}. Beurteile das anhand des im Screenshot
        erkannten Texts (Fenstertitel, App-Namen, Überschriften), des Dateinamens
        und der Zeitstempel. Wenn kein Projekt erkennbar ist, lege die Datei
        unter "Allgemein/{JJJJ-MM}" ab.
        """,
        "template.invoices.title": "Rechnungen & Belege",
        "template.invoices.summary": "PDFs nach Jahr / Absender / Datum Betreff ablegen.",
        "template.invoices.prompt": """
        Lege Rechnungen und Belege unter {Jahr}/{Absender}/{JJJJ-MM-TT Betreff}.pdf ab.
        Nutze Absender, Rechnungsdatum und Betreff aus dem Dokument. Dokumente, die
        keine Rechnungen/Belege sind, überspringen.
        """,
        "template.blank.title": "Leere Regel",
        "template.blank.summary": "Von Grund auf beginnen.",

        "about.tagline": "Hazel, aber die Regel ist ein Satz.",
        "about.version": "Version %@",
        "about.help": "Hilfe",

        "updates.available.title": "%@ %@ ist verfügbar",
        "updates.available.body": "Installiert ist %@. Update jetzt laden?",
        "updates.available.download": "Laden",
        "updates.available.later": "Später erinnern",
        "updates.available.skip": "Diese Version überspringen",
        "updates.upToDate.title": "Alles aktuell",
        "updates.upToDate.body": "%@ %@ ist die neueste Version.",
        "updates.failed.title": "Update-Prüfung fehlgeschlagen",
        "updates.parseFailed": "Die Versionsnummern konnten nicht verglichen werden.",
        "updates.ok": "OK",
        "updates.lastResult.available": "Update verfügbar: %@",
        "updates.lastResult.upToDate": "Alles aktuell (%@).",
        "updates.error.http": "GitHub-API antwortete mit HTTP %d.",
        "updates.error.noRelease": "Keine passende Version gefunden.",
        // Regelprüfung
        "validate.errors.one": "1 Problem",
        "validate.errors.other": "%d Probleme",
        "validate.warnings.one": "1 Hinweis",
        "validate.warnings.other": "%d Hinweise",
        "step.match.result": "Treffer: %@ von %@",
        "step.match.counting": "Zähle…",
        "step.match.idle": "Treffer zählen",
        "step.match.help": "Zählt die Dateien im überwachten Ordner, die dieser Schritt gerade beansprucht. Nichts wird bewegt und nichts kostet etwas.",
        "validate.section": "Bevor du sie aktivierst",
        "validate.stepLabel": "Schritt %@",
        "validate.stepLabelNamed": "Schritt %@ · %@",
        "validate.rule.noWatchFolder": "Kein überwachter Ordner: Diese Regel hat nichts anzusehen.",
        "validate.rule.noTargetFolder": "Kein Zielordner: Es gibt nirgendwohin einzusortieren.",
        "validate.rule.doesNothing": "Noch keine Schritte, und übrige Dateien werden übersprungen — diese Regel tut nichts.",
        "validate.rule.modelWithoutPrompt": "Das Modell wird gefragt, aber es gibt keine Anweisung, was es tun soll. Jede Datei wäre ein bezahlter Rateversuch.",
        "validate.rule.incompleteRoot": "Ein Zielordner braucht Namen und Pfad.",
        "validate.rule.duplicateRoot": "Zwei Zielordner heißen beide «%@».",
        "validate.step.noActions": "Dieser Schritt trifft zu und tut dann nichts.",
        "validate.step.twoPlacements": "Zwei Aktionen bestimmen beide, wohin die Datei geht (%@ und %@). Die erste gewinnt; die zweite läuft nie.",
        "validate.step.neverMatches": "«Eine von» ohne Bedingungen kann nie zutreffen, dieser Schritt läuft also nie.",
        "validate.step.unreachable": "Schritt %@ trifft auf jede Datei zu und behält sie, dieser Schritt wird also nie erreicht.",
        "validate.condition.emptyGroup": "Eine leere Bedingungsgruppe hat keine Wirkung.",
        "validate.condition.unknownAttribute": "«%@» kann diese Version nicht ansehen.",
        "validate.condition.unknownOperator": "«%@» ist kein Vergleich, den diese Version kennt.",
        "validate.condition.noValue": "«%@» braucht etwas zum Vergleichen.",
        "validate.condition.betweenNeedsTwo": "«zwischen» braucht genau zwei Werte.",
        "validate.condition.blockedByPrivacy": "Diese Regel liest nie Dateiinhalte, «%@» kann also nie einen Wert haben. Schalte «nur Metadaten» aus oder prüfe etwas anderes.",
        "validate.condition.metadataOnlyValue": "Diese Regel liest nie Dateiinhalte, «%@» ist also nur für Dateien bekannt, die Spotlight bereits indexiert hat.",
        "validate.step.problems": "%@ in diesem Schritt",
        "validate.condition.unsafeRegex": "Dieses Muster kann bei manchen Namen exponentiell lange laufen und wird deshalb abgelehnt.",
        "validate.condition.badRegex": "Das ist kein gültiger regulärer Ausdruck.",
        "validate.condition.captureWithoutRegex": "Nur «entspricht Muster» merkt sich etwas; dieser Name wird nie gefüllt.",
        "validate.condition.modelNotSupported": "Das Modell in einer Bedingung zu fragen, wird noch nicht unterstützt — das kann also nie zutreffen. Nutze stattdessen die Aktion «Modell fragen».",
        "validate.action.unknownType": "«%@» ist keine Aktion, die diese Version ausführen kann.",
        "validate.action.unknownRoot": "Es gibt keinen Zielordner namens «%@».",
        "validate.action.notAppliedYet": "«%@» wird gespeichert, von dieser Version aber noch nicht ausgeführt — der Rest des Schritts läuft weiterhin.",
        "validate.action.trashMoves": "Diese Version lässt die Datei liegen, statt sie in den Papierkorb zu bewegen.",
        "validate.action.noTags": "Keine Tags angegeben.",
        "validate.action.noShortcut": "Kein Kurzbefehl-Name angegeben.",
        "validate.action.badTemplate": "Das Ziel ist ungültig: %@",
        "validate.action.unknownToken": "«{%@}» ist kein Wert, den diese Version einsetzen kann — er bleibt leer.",
        "validate.action.captureWithoutSource": "Hier wird ein gemerkter Wert verwendet, aber keine Bedingung dieser Regel merkt sich etwas.",
        "validate.action.nameCanBeEmpty": "Fehlen diese Werte, käme die Datei ganz ohne Namen an.",
    ]
}
