import Foundation

/// A portable, shareable rule: everything that makes a rule *a rule* — prompt,
/// taxonomy, pre-rules, thresholds, privacy mode — minus the machine-local
/// folder paths. Written as pretty JSON with a format version so packs shared
/// today still import tomorrow. Imports arrive disabled and in preview mode:
/// a shared pack is safe by construction until its new owner has pointed it at
/// folders and watched it do the right thing.
struct RulePack: Codable {
    static let currentFormat = 1
    /// Conventional file extension for exported packs.
    static let fileExtension = "sortomatrule"

    var format: Int
    var app: String
    var rule: Rule

    enum PackError: LocalizedError {
        case unsupportedFormat(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let version):
                return L10n.t("rules.pack.unsupportedFormat", version)
            }
        }
    }

    /// Wrap a rule for export: paths stripped (they are machine-local), the
    /// rest verbatim.
    init(exporting rule: Rule) {
        self.format = Self.currentFormat
        self.app = "Sortomat"
        var portable = rule
        portable.watchPath = ""
        portable.targetPath = ""
        self.rule = portable
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(_ data: Data) throws -> RulePack {
        let pack = try JSONDecoder().decode(RulePack.self, from: data)
        guard pack.format <= currentFormat else {
            throw PackError.unsupportedFormat(pack.format)
        }
        return pack
    }

    /// The rule as it should enter a config: fresh identity, disabled, preview
    /// mode — regardless of how the exporter had it configured.
    func makeImportedRule() -> Rule {
        var imported = rule
        imported.id = UUID()
        imported.enabled = false
        imported.dryRun = true
        return imported
    }
}
