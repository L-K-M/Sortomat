import Foundation

/// Ready-made rules the user can drop in and adjust — the onboarding story for
/// non-programmers (PLAN Phase 4).
public enum RuleTemplate: String, CaseIterable, Identifiable, Sendable {
    case tidy
    case ebooks
    case screenshots
    case invoices
    case blank

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .tidy: return L10n.t("template.tidy.title")
        case .ebooks: return L10n.t("template.ebooks.title")
        case .screenshots: return L10n.t("template.screenshots.title")
        case .invoices: return L10n.t("template.invoices.title")
        case .blank: return L10n.t("template.blank.title")
        }
    }

    public var summary: String {
        switch self {
        case .tidy: return L10n.t("template.tidy.summary")
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
        case .tidy:
            // The one template that needs no key, no model and no network: a
            // file's kind is a `UTType` lookup, and four buckets cover most of
            // what lands in a Downloads folder. It is also the honest answer to
            // "what can this app do for free?", which every previous template
            // answered with "nothing".
            //
            // The fallback is `skip`, not `askModel`: anything the four steps
            // do not recognize is left exactly where it is. A tidy-up rule that
            // starts spending money on the files it did not understand would be
            // the opposite of what it says on the tin.
            return Rule(
                name: L10n.t("template.tidy.title"),
                enabled: false,
                steps: Self.tidySteps,
                fallback: .skip
            )
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
                // The old single pre-rule sent screenshot-named files to the
                // LLM — which is the fall-through anyway, so it changed
                // nothing: every image in the folder was classified (and paid
                // for). Now only screenshot-named files (English and German
                // conventions) reach the model; the catch-all skip keeps
                // everything else off the paid path.
                preRules: [
                    PreRule(
                        name: "Screenshots",
                        match: .glob,
                        pattern: "*creenshot*",
                        action: .useLLM
                    ),
                    PreRule(
                        name: "Bildschirmfotos",
                        match: .glob,
                        pattern: "*ildschirmfoto*",
                        action: .useLLM
                    ),
                    // macOS before Big Sur wrote "Screen Shot 2024-01-01 at …"
                    // with a space, which contains no "creenshot" substring —
                    // without this those files fall into the catch-all skip
                    // below and are never classified.
                    PreRule(
                        name: "Screen Shot (legacy)",
                        match: .glob,
                        pattern: "*creen Shot*",
                        action: .useLLM
                    ),
                    PreRule(
                        name: "Capture d'écran",
                        match: .glob,
                        pattern: "*apture d*cran*",
                        action: .useLLM
                    ),
                    PreRule(
                        name: "Captura de pantalla",
                        match: .glob,
                        pattern: "*aptura de pantalla*",
                        action: .useLLM
                    ),
                    PreRule(
                        name: L10n.t("template.screenshots.preSkip"),
                        match: .glob,
                        pattern: "*",
                        action: .skip
                    ),
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

    /// Four buckets by content kind, each a single free condition. `{name}` is
    /// the last component of every destination, so a file always arrives with
    /// the name it had — the one thing a tidy-up rule must never get wrong.
    static var tidySteps: [RuleStep] {
        func step(_ folderKey: String, _ kinds: [Kind]) -> RuleStep {
            let folder = L10n.t(folderKey)
            return RuleStep(
                name: folder,
                when: ConditionGroup(mode: .all, items: [
                    .test(ConditionTest(attribute: .kind, op: .isIn,
                                        value: .list(kinds.map(\.rawValue))))
                ]),
                then: [RuleAction(type: .move, template: "\(folder)/{name}")]
            )
        }
        return [
            step("template.tidy.folder.images", [.image]),
            step("template.tidy.folder.documents",
                 [.pdf, .document, .spreadsheet, .presentation, .text, .ebook]),
            step("template.tidy.folder.media", [.audio, .video]),
            step("template.tidy.folder.archives", [.archive, .diskImage]),
        ]
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
