import Foundation

/// Ready-made rules the user can drop in and adjust — the onboarding story for
/// non-programmers (PLAN Phase 4).
public enum RuleTemplate: String, CaseIterable, Identifiable, Sendable {
    case ebooks
    case screenshots
    case invoices
    case blank

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ebooks: return L10n.t("template.ebooks.title")
        case .screenshots: return L10n.t("template.screenshots.title")
        case .invoices: return L10n.t("template.invoices.title")
        case .blank: return L10n.t("template.blank.title")
        }
    }

    public var summary: String {
        switch self {
        case .ebooks: return L10n.t("template.ebooks.summary")
        case .screenshots: return L10n.t("template.screenshots.summary")
        case .invoices: return L10n.t("template.invoices.summary")
        case .blank: return L10n.t("template.blank.summary")
        }
    }

    /// A fresh rule (new id) seeded from the template. Disabled by default so
    /// nothing moves until the user has picked folders and reviewed it.
    public func makeRule() -> Rule {
        switch self {
        case .ebooks:
            return Rule(
                name: L10n.t("template.ebooks.title"),
                enabled: false,
                prompt: Self.ebookPrompt,
                extensions: ["epub"],
                taxonomy: Self.ebookGenres,
                dryRun: true
            )
        case .screenshots:
            return Rule(
                name: L10n.t("template.screenshots.title"),
                enabled: false,
                prompt: Self.screenshotPrompt,
                extensions: ["png", "jpg", "jpeg", "heic"],
                preRules: [
                    PreRule(
                        name: "Screenshots",
                        match: .glob,
                        pattern: "*creenshot*",
                        action: .useLLM
                    )
                ],
                dryRun: true
            )
        case .invoices:
            return Rule(
                name: L10n.t("template.invoices.title"),
                enabled: false,
                prompt: Self.invoicePrompt,
                extensions: ["pdf"],
                dryRun: true
            )
        case .blank:
            return Rule(dryRun: true)
        }
    }

    /// The 31 normalized German genres from the original batch script, reused as
    /// the e-book taxonomy so the model can only pick from a known set.
    public static let ebookGenres: [String] = [
        "Abenteuer", "Belletristik", "Comic & Manga", "Erotik", "Fantasy",
        "Historischer Roman", "Horror", "Humor & Satire", "Kinder- & Jugendbuch",
        "Klassiker", "Krimi & Thriller", "Kurzgeschichten", "Liebesroman",
        "Lyrik & Drama", "Märchen & Sagen", "Science-Fiction",
        "Biografie & Memoiren", "Geschichte", "Gesundheit & Ernährung",
        "Kochbuch", "Kunst & Kultur", "Philosophie", "Politik & Gesellschaft",
        "Ratgeber & Selbsthilfe", "Reise", "Religion & Spiritualität", "Sachbuch",
        "True Crime", "Wirtschaft & Finanzen", "Wissenschaft & Technik", "Unbekannt",
    ]

    static let ebookPrompt = """
    Sortiere E-Books (EPUB) in die Struktur {Genre}/{Nachname, Vorname}/{Titel}.epub.

    Wähle das Genre aus der vorgegebenen Liste. Der Autor als "Nachname, Vorname"
    (bei nur einem Namen oder Pseudonym nur der Name). Titel ohne Reihennummern-
    Präfixe wie "01 - ", ohne Verlagsangaben. Dateien, die keine E-Books sind,
    überspringen.
    """

    static let screenshotPrompt = """
    Ordne Screenshots dem passenden Projekt- oder Themenordner zu, z.B.
    {Projekt}/{JJJJ-MM}/{Dateiname}. Nutze den sichtbaren Text und die Bild-
    beschreibung, um das Thema zu erkennen. Wenn kein Projekt erkennbar ist,
    lege die Datei unter "Allgemein/{JJJJ-MM}" ab.
    """

    static let invoicePrompt = """
    Lege Rechnungen und Belege unter {Jahr}/{Absender}/{JJJJ-MM-TT Betreff}.pdf ab.
    Nutze Absender, Rechnungsdatum und Betreff aus dem Dokument. Dokumente, die
    keine Rechnungen/Belege sind, überspringen.
    """
}
