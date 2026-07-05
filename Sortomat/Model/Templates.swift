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

    // The prompts follow the UI language: an English-speaking user previously
    // got German prompts steering their model (and German folder names out the
    // other end). The German originals live in the L10n table.
    static var ebookPrompt: String { L10n.t("template.ebooks.prompt") }
    static var screenshotPrompt: String { L10n.t("template.screenshots.prompt") }
    static var invoicePrompt: String { L10n.t("template.invoices.prompt") }
}
