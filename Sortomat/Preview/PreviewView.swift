import SwiftUI

struct PreviewView: View {
    var body: some View {
        TabView {
            ReviewTab()
                .tabItem { Label(L10n.t("preview.title"), systemImage: "eye") }
            HistoryTab()
                .tabItem { Label(L10n.t("journal.title"), systemImage: "clock.arrow.circlepath") }
        }
        .padding(8)
    }
}

// MARK: - Review

private struct ReviewTab: View {
    @EnvironmentObject private var state: AppState
    @State private var selected: Set<UUID> = []
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            if state.pendingActions.isEmpty {
                emptyState
            } else {
                List(selection: $selected) {
                    ForEach(state.pendingActions) { plan in
                        PlanRow(plan: plan, target: target(for: plan))
                            .tag(plan.id)
                    }
                }
            }
            Divider()
            toolbar
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle").font(.largeTitle).foregroundStyle(.secondary)
            Text(L10n.t("preview.empty")).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack {
            Button(L10n.t("preview.refresh")) {
                Task { busy = true; await state.refreshPreview(); busy = false }
            }
            .disabled(busy)
            Spacer()
            Button(L10n.t("preview.apply")) {
                let plans = state.pendingActions.filter { selected.contains($0.id) }
                Task { busy = true; await state.apply(plans); selected.removeAll(); busy = false }
            }
            .disabled(selected.isEmpty || busy)
            Button(L10n.t("preview.applyAll")) {
                let plans = state.pendingActions.filter(\.isActionable)
                Task { busy = true; await state.apply(plans); selected.removeAll(); busy = false }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(state.pendingActions.allSatisfy { !$0.isActionable } || busy)
        }
        .padding(8)
    }

    private func target(for plan: PlannedAction) -> URL {
        guard let rule = state.config.rules.first(where: { $0.id == plan.ruleID }) else {
            return URL(fileURLWithPath: "/")
        }
        return URL(fileURLWithPath: (rule.targetPath as NSString).expandingTildeInPath)
    }
}

private struct PlanRow: View {
    let plan: PlannedAction
    let target: URL

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(plan.source.lastPathComponent).lineLimit(1)
                Text("\(actionLabel) → \(plan.relativeDestination(to: target))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !plan.reason.isEmpty {
                    Text(plan.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            if let confidence = plan.confidence {
                Text("\(Int(confidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var actionLabel: String {
        switch plan.kind {
        case .move: return L10n.t("preview.plan.move")
        case .copy: return L10n.t("preview.plan.copy")
        case .skip: return L10n.t("preview.plan.skip")
        case .quarantine: return L10n.t("preview.plan.quarantine")
        case .duplicate: return L10n.t("activity.duplicate")
        }
    }

    private var icon: String {
        switch plan.kind {
        case .move: return "arrow.right.circle"
        case .copy: return "doc.on.doc"
        case .skip: return "minus.circle"
        case .quarantine: return "exclamationmark.triangle"
        case .duplicate: return "doc.on.doc.fill"
        }
    }

    private var color: Color {
        switch plan.kind {
        case .move, .copy: return .green
        case .quarantine: return .orange
        default: return .secondary
        }
    }
}

// MARK: - History

private struct HistoryTab: View {
    @EnvironmentObject private var state: AppState
    @State private var entries: [JournalEntry] = []
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock").font(.largeTitle).foregroundStyle(.secondary)
                    Text(L10n.t("journal.empty")).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(entries) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.destination.lastPathComponent).lineLimit(1)
                                Text("\(entry.ruleName) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(L10n.t("journal.undo")) { undo(entry) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red).padding(6)
            }
            Divider()
            HStack {
                Button(L10n.t("preview.refresh")) { reload() }
                Spacer()
            }
            .padding(8)
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        entries = Journal.recent(limit: 200)
        error = nil
    }

    private func undo(_ entry: JournalEntry) {
        Task { @MainActor in
            do {
                // Via AppState so the ledger learns about the restored file —
                // otherwise the next scan would just move it back.
                try await state.undo(entry)
                entries.removeAll { $0.id == entry.id }
            } catch {
                self.error = L10n.t("journal.undoFailed", entry.destination.lastPathComponent, error.localizedDescription)
            }
        }
    }
}
