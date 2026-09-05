import SwiftUI

/// The window the app is *about*: what Sortomat wants to do with your files,
/// what it already did, and the rules that decide. Settings moved out of the
/// way — an API key is not a home screen.
///
/// `HSplitView` rather than `NavigationSplitView`: the deployment floor is
/// macOS 13, where the newer container's sidebar behaviour inside an
/// `NSHostingController` is the least predictable thing on the screen, and none
/// of this can be compiled locally. The assembly is one view so it can be
/// swapped in a single edit.
struct MainView: View {
    @Binding var selection: SidebarSelection

    var body: some View {
        HSplitView {
            Sidebar(selection: $selection)
                .frame(minWidth: 210, idealWidth: 240, maxWidth: 340)
            detail
                .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 820, minHeight: 520)
    }

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .inbox:
            InboxView()
        case .history:
            HistoryView()
        case .rule(let id):
            RuleDetailView(ruleID: id, selection: $selection)
                // A fresh editor per rule, so its @State edit buffers reset
                // when the selection moves.
                .id(id)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject private var state: AppState
    @Binding var selection: SidebarSelection
    @State private var confirmingDelete: UUID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: listSelection) {
                Section {
                    row(.inbox, L10n.t("sidebar.inbox"), "tray.full", badge: state.pendingActions.count)
                    row(.history, L10n.t("sidebar.history"), "clock.arrow.circlepath", badge: 0)
                }
                ForEach(RuleGroup.group(state.config.rules)) { group in
                    Section(group.title) {
                        ForEach(group.rules) { rule in
                            ruleRow(rule)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            footer
        }
        // One dialog for the list, not one per row: deleting destroys a
        // hand-tuned instruction and the rule's memory of which files it
        // already handled, irreversibly — never on a mis-click.
        .confirmationDialog(
            L10n.t("rules.delete.title", deletionTargetName),
            isPresented: Binding(get: { confirmingDelete != nil },
                                 set: { if !$0 { confirmingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(L10n.t("rules.delete.confirm"), role: .destructive) {
                guard let id = confirmingDelete else { return }
                if selection == .rule(id) { selection = .inbox }
                state.remove(ruleID: id)
                confirmingDelete = nil
            }
        } message: {
            Text(L10n.t("rules.delete.message"))
        }
    }

    /// `List` wants an optional selection; the window's is never nil, so a
    /// deselect (⌘-click on the selected row) leaves the pane where it is
    /// rather than emptying it.
    private var listSelection: Binding<SidebarSelection?> {
        Binding(get: { selection }, set: { if let new = $0 { selection = new } })
    }

    private var deletionTargetName: String {
        state.config.rules.first { $0.id == confirmingDelete }?.name ?? ""
    }

    private func row(_ tag: SidebarSelection, _ title: String, _ symbol: String, badge: Int) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            if badge > 0 {
                Text("\(badge)")
                    .font(.caption.monospacedDigit())
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
            }
        }
        .tag(tag)
    }

    private func ruleRow(_ rule: Rule) -> some View {
        let mode = RuleMode(rule)
        return HStack(spacing: 6) {
            Image(systemName: mode.symbol)
                .foregroundStyle(mode.tint)
                .font(.caption)
                .help(mode.help)
            Text(rule.name).lineLimit(1)
        }
        .contextMenu {
            Button(L10n.t("rules.duplicate")) { state.duplicate(ruleID: rule.id) }
            Button(L10n.t("rules.remove"), role: .destructive) { confirmingDelete = rule.id }
        }
        .tag(SidebarSelection.rule(rule.id))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(RuleTemplate.allCases) { template in
                    Button(template.title) {
                        state.addRule(from: template)
                        if let id = state.config.rules.last?.id { selection = .rule(id) }
                    }
                }
            } label: {
                Label(L10n.t("rules.add"), systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Spacer()
            RulePackButtons(selection: $selection)
        }
        .padding(8)
    }
}
