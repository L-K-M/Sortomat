import Foundation

/// A tiny in-code localization table. English is the base; German overrides it
/// when the user's preferred language is German. An in-code table (rather than
/// `.strings`/String-catalog resources) keeps the executable target free of
/// resource-bundling quirks while still shipping a genuinely bilingual UI.
public enum L10n {
    /// Overridden in tests to force a language; otherwise follows the system.
    public static var forcedLanguage: String?

    public static var language: String {
        if let forced = forcedLanguage { return forced }
        let pref = Locale.preferredLanguages.first ?? "en"
        return pref.hasPrefix("de") ? "de" : "en"
    }

    /// Localized string for `key`. Falls back to the English table, then to the
    /// key itself (so a missing key is visible but never crashes).
    public static func t(_ key: String) -> String {
        if language == "de", let s = german[key] { return s }
        return english[key] ?? german[key] ?? key
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
    public static func plural(_ key: String, _ count: Int, _ args: CVarArg...) -> String {
        String(format: t(key + (count == 1 ? ".one" : ".other")), arguments: [count as CVarArg] + args)
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
        "tab.rules": "Rules",
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
        "general.watch.section": "Watching",
        "general.interval": "Check interval: %d s",
        "general.interval.help": "Folders are also checked immediately when something changes. The interval is only the safety net.",
        "general.concurrency": "Max concurrent classifications: %d",
        "general.budget": "Max model calls per check (0 = unlimited): %d",
        "general.notifications": "Notify about filed files and failures",
        "general.launchAtLogin": "Launch Sortomat at login",
        "general.privacyNote": "Note: a file's name, metadata and (unless a rule is metadata-only) a text excerpt are sent to the model to classify it.",

        // Paths
        "path.choose": "Choose…",
        "path.placeholder": "/path/to/folder",

        // Preview / dry-run
        "preview.title": "Preview changes",
        "preview.empty": "Nothing to file right now.",
        "preview.apply": "Apply selected",
        "preview.applyAll": "Apply all",
        "preview.refresh": "Refresh",
        "preview.applied.one": "Applied 1 change.",
        "preview.applied.other": "Applied %d changes.",
        "preview.dismissed.one": "Dismissed 1 suggestion.",
        "preview.dismissed.other": "Dismissed %d suggestions.",
        "preview.dismiss": "Dismiss selected",
        "preview.empty.noKey": "No API key set — add one under Rules & Settings → Settings to preview changes.",
        "preview.plan.move": "Move",
        "preview.plan.copy": "Copy",
        "preview.plan.skip": "Skip",
        "preview.plan.quarantine": "Quarantine",
        "preview.plan.duplicate": "Duplicate",
        "preview.origin.preRule": "pre-rule",
        "preview.origin.model": "model",
        "preview.origin.taxonomy": "taxonomy",
        "preview.origin.confidence": "low confidence",
        "preview.origin.system": "system",

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
        "activity.quarantined": "[%@] Quarantined: %@ → %@ (%@)",
        "activity.preRuleSkip": "[%@] Pre-rule skip: %@ (%@)",
        "activity.error": "[%@] ERROR on %@: %@",
        "activity.missingWatch": "[%@] Watched folder missing: %@",
        "activity.wouldMove": "[%@] Would move %@ → %@",
        "activity.wouldSkip": "[%@] Would skip %@ — %@",
        "activity.budgetReached": "[%@] Per-check model-call budget reached (%d).",
        "activity.stalePlan": "[%@] Skipped %@: the file changed after this suggestion was made — refresh the preview.",
        "activity.keyDeferred.one": "[%2$@] %1$d file needs the model, but no API key is set — pre-rules still ran.",
        "activity.keyDeferred.other": "[%2$@] %1$d files need the model, but no API key is set — pre-rules still ran.",

        // Decision memo
        "memo.remembered": "%@ · remembered from an identical file",
        "memo.rememberedBare": "Remembered from an identical file",

        // Notifications
        "notify.filed.one": "Filed 1 file.",
        "notify.filed.other": "Filed %d files.",
        "notify.failuresMore.one": "%2$@ (and 1 more failure)",
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
        "process.locked": "Another Sortomat process is using this configuration — not running, to avoid clobbering its records.",
        "process.lockWarning": "Warning: another Sortomat process holds this configuration; concurrent runs may conflict.",

        // Templates
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
        {Project}/{YYYY-MM}/{filename}. Judge from the file name, its
        timestamps and any indexed text in the metadata. If no project is
        recognizable, file it under "General/{YYYY-MM}".
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
        "tab.rules": "Regeln",
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
        "general.watch.section": "Überwachung",
        "general.interval": "Prüfintervall: %d s",
        "general.interval.help": "Ordner werden zusätzlich sofort geprüft, wenn sich etwas ändert. Das Intervall ist nur das Sicherheitsnetz.",
        "general.concurrency": "Max. gleichzeitige Klassifikationen: %d",
        "general.budget": "Max. Modell-Aufrufe pro Prüfung (0 = unbegrenzt): %d",
        "general.notifications": "Über einsortierte Dateien und Fehler benachrichtigen",
        "general.launchAtLogin": "Sortomat beim Anmelden starten",
        "general.privacyNote": "Hinweis: Dateiname, Metadaten und (sofern die Regel nicht «nur Metadaten» ist) ein Textauszug werden zur Klassifikation an das Modell gesendet.",

        "path.choose": "Auswählen…",
        "path.placeholder": "/Pfad/zum/Ordner",

        "preview.title": "Änderungen vorschauen",
        "preview.empty": "Momentan nichts einzusortieren.",
        "preview.apply": "Ausgewählte anwenden",
        "preview.applyAll": "Alle anwenden",
        "preview.refresh": "Aktualisieren",
        "preview.applied.one": "1 Änderung angewendet.",
        "preview.applied.other": "%d Änderungen angewendet.",
        "preview.dismissed.one": "1 Vorschlag verworfen.",
        "preview.dismissed.other": "%d Vorschläge verworfen.",
        "preview.dismiss": "Ausgewählte verwerfen",
        "preview.empty.noKey": "Kein API-Key gesetzt — unter Regeln & Einstellungen → Einstellungen hinzufügen, um Änderungen vorzuschauen.",
        "preview.plan.move": "Verschieben",
        "preview.plan.copy": "Kopieren",
        "preview.plan.skip": "Überspringen",
        "preview.plan.quarantine": "Quarantäne",
        "preview.plan.duplicate": "Duplikat",
        "preview.origin.preRule": "Vorregel",
        "preview.origin.model": "Modell",
        "preview.origin.taxonomy": "Taxonomie",
        "preview.origin.confidence": "geringe Konfidenz",
        "preview.origin.system": "System",

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

        "memo.remembered": "%@ · von einer identischen Datei übernommen",
        "memo.rememberedBare": "Von einer identischen Datei übernommen",

        "notify.filed.one": "1 Datei einsortiert.",
        "notify.filed.other": "%d Dateien einsortiert.",
        "notify.failuresMore.one": "%2$@ (und 1 weiterer Fehler)",
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
        "process.locked": "Ein anderer Sortomat-Prozess verwendet diese Konfiguration – Abbruch, um dessen Aufzeichnungen nicht zu überschreiben.",
        "process.lockWarning": "Warnung: Ein anderer Sortomat-Prozess hält diese Konfiguration; gleichzeitige Läufe können kollidieren.",

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
        {Projekt}/{JJJJ-MM}/{Dateiname}. Beurteile das anhand des Dateinamens,
        der Zeitstempel und eventuell mitgelieferter indexierter Texte. Wenn
        kein Projekt erkennbar ist, lege die Datei unter "Allgemein/{JJJJ-MM}" ab.
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
    ]
}
