import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A rule, with the thing people change most often — whether it files by itself
/// or asks first — promoted out of the form into a header they can't miss.
struct RuleDetailView: View {
    @EnvironmentObject private var state: AppState
    let ruleID: UUID

    var body: some View {
        if let index = state.config.rules.firstIndex(where: { $0.id == ruleID }) {
            VStack(spacing: 0) {
                header(index: index)
                Divider()
                RuleEditor(rule: $state.config.rules[index])
            }
        } else {
            EmptyState(symbol: "tray.and.arrow.down",
                       title: L10n.t("rules.empty.title"),
                       message: L10n.t("rules.empty.message"))
        }
    }

    private func header(index: Int) -> some View {
        let rule = state.config.rules[index]
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(rule.name).font(.title2.weight(.semibold)).lineLimit(1)
                Text(pathSentence(rule)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Picker("", selection: modeBinding) {
                ForEach(RuleMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help(RuleMode(rule).help)
        }
        .padding(14)
    }

    /// The picker writes through to the two stored booleans, so nothing
    /// downstream — config.json, the CLI, rule packs — has to learn a new
    /// shape. Keyed by id rather than index: a rule deleted from the sidebar
    /// while its header is on screen would make a captured index a crash.
    private var modeBinding: Binding<RuleMode> {
        Binding(
            get: {
                guard let rule = state.config.rules.first(where: { $0.id == ruleID }) else { return .off }
                return RuleMode(rule)
            },
            set: { newMode in
                guard let index = state.config.rules.firstIndex(where: { $0.id == ruleID }) else { return }
                newMode.apply(to: &state.config.rules[index])
                state.persistAndApply()
            }
        )
    }

    private func pathSentence(_ rule: Rule) -> String {
        let watch = rule.watchPath.isEmpty
            ? L10n.t("sidebar.noFolder")
            : (rule.watchPath as NSString).abbreviatingWithTildeInPath
        let target = rule.targetPath.isEmpty
            ? L10n.t("sidebar.noFolder")
            : (rule.targetPath as NSString).abbreviatingWithTildeInPath
        return "\(watch)  →  \(target)"
    }
}

/// Export/import, kept out of the sidebar body so the list stays a list.
/// A rule — its instruction, its allowed folders, its steps — is exactly the
/// kind of artifact people want to share; paths stay machine-local and imports
/// arrive switched off.
struct RulePackButtons: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: SidebarSelection
    @State private var status: String?

    var body: some View {
        HStack(spacing: 6) {
            Button {
                exportSelected()
            } label: { Image(systemName: "square.and.arrow.up") }
                .disabled(selection.ruleID == nil)
                .help(L10n.t("rules.export"))
            Button {
                importPack()
            } label: { Image(systemName: "square.and.arrow.down") }
                .help(L10n.t("rules.import"))
        }
        .buttonStyle(.borderless)
        .help(status ?? "")
    }

    private func exportSelected() {
        guard let id = selection.ruleID,
              let rule = state.config.rules.first(where: { $0.id == id }) else { return }
        let panel = NSSavePanel()
        if let type = UTType(filenameExtension: RulePack.fileExtension) {
            panel.allowedContentTypes = [type, .json]
        } else {
            panel.allowedContentTypes = [.json]
        }
        panel.nameFieldStringValue = "\(rule.name).\(RulePack.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try RulePack(exporting: rule).encoded().write(to: url, options: .atomic)
            status = L10n.t("rules.export.done", rule.name)
        } catch {
            status = L10n.t("rules.pack.failed", error.localizedDescription)
        }
    }

    private func importPack() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let pack = try RulePack.decode(try Data(contentsOf: url))
            selection = .rule(state.importRule(pack.makeImportedRule()))
            status = L10n.t("rules.import.done")
        } catch {
            status = L10n.t("rules.pack.failed", error.localizedDescription)
        }
    }
}
