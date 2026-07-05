import SwiftUI

struct RulesTab: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: UUID?
    @State private var confirmingDelete = false

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 220, maxWidth: 300)
            editor
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            if selection == nil { selection = state.config.rules.first?.id }
            state.setSelectedRule(selection)
        }
        .onChange(of: selection) { newValue in state.setSelectedRule(newValue) }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(state.config.rules) { rule in
                    HStack(spacing: 8) {
                        Circle()
                            .fill(dotColor(for: rule))
                            .frame(width: 8, height: 8)
                        Text(rule.name).lineLimit(1)
                        Spacer()
                        if rule.dryRun {
                            Image(systemName: "eye").foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .tag(rule.id)
                }
            }
            Divider()
            HStack(spacing: 12) {
                Menu {
                    ForEach(RuleTemplate.allCases) { template in
                        Button(template.title) {
                            state.addRule(from: template)
                            selection = state.config.rules.last?.id
                        }
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 40)
                .help(L10n.t("rules.add"))

                Button {
                    confirmingDelete = true
                } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)
                    .help(L10n.t("rules.remove"))
                    // Deleting destroys a hand-tuned prompt/taxonomy and the
                    // rule's ledger memory, irreversibly — never on a mis-click.
                    .confirmationDialog(
                        L10n.t("rules.delete.title", selectedRuleName),
                        isPresented: $confirmingDelete,
                        titleVisibility: .visible
                    ) {
                        Button(L10n.t("rules.delete.confirm"), role: .destructive) {
                            if let id = selection {
                                state.remove(ruleID: id)
                                selection = state.config.rules.first?.id
                            }
                        }
                    } message: {
                        Text(L10n.t("rules.delete.message"))
                    }

                Button {
                    if let id = selection { state.duplicate(ruleID: id) }
                } label: { Image(systemName: "plus.square.on.square") }
                    .disabled(selection == nil)
                    .help(L10n.t("rules.duplicate"))

                Spacer()
            }
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let index = state.config.rules.firstIndex(where: { $0.id == selection }) {
            RuleEditor(rule: $state.config.rules[index])
                // A fresh editor per rule so its @State edit buffers (extensions,
                // taxonomy) reset correctly when switching rules.
                .id(state.config.rules[index].id)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "tray.and.arrow.down")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
                Text(L10n.t("rules.empty.title"))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedRuleName: String {
        state.config.rules.first(where: { $0.id == selection })?.name ?? ""
    }

    private func dotColor(for rule: Rule) -> Color {
        if !rule.enabled { return .secondary.opacity(0.4) }
        return rule.dryRun ? .orange : .green
    }
}
