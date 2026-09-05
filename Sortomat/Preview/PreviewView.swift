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
    @State private var status: String?

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

    /// Tell the truth when nothing is shown *because the app can't work yet*
    /// (no API key) — a bare "nothing to file" reads as "all is well".
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: state.apiKeyMissing ? "key" : "checkmark.circle")
                .font(.largeTitle).foregroundStyle(.secondary)
            Text(L10n.t(state.apiKeyMissing ? "preview.empty.noKey" : "preview.empty"))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var toolbar: some View {
        HStack {
            Button(L10n.t("preview.refresh")) {
                status = nil
                Task { busy = true; await state.refreshPreview(); busy = false }
            }
            .disabled(busy)
            if busy {
                ProgressView().controlSize(.small)
            } else if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(L10n.t("preview.dismiss")) {
                let plans = state.pendingActions.filter { selected.contains($0.id) }
                plans.forEach { state.dismiss($0) }
                status = L10n.plural("preview.dismissed", plans.count)
                selected.removeAll()
            }
            .disabled(selected.isEmpty || busy)
            Button(L10n.t("preview.apply")) {
                let plans = state.pendingActions.filter { selected.contains($0.id) }
                apply(plans)
            }
            .disabled(selected.isEmpty || busy)
            Button(L10n.t("preview.applyAll")) {
                apply(state.pendingActions.filter(\.isActionable))
            }
            .keyboardShortcut(.defaultAction)
            .disabled(state.pendingActions.allSatisfy { !$0.isActionable } || busy)
        }
        .padding(8)
    }

    private func apply(_ plans: [PlannedAction]) {
        Task {
            busy = true
            await state.apply(plans)
            selected.removeAll()
            busy = false
            status = L10n.plural("preview.applied", plans.count)
        }
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
                // With several rules active, "who claimed this file" matters.
                Text("\(plan.ruleName) · \(actionLabel) → \(plan.relativeDestination(to: target))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !plan.reason.isEmpty {
                    Text(plan.reason).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer()
            Text(originLabel)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.secondary.opacity(0.12)))
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
        case .duplicate: return L10n.t("preview.plan.duplicate")
        }
    }

    /// Where the decision came from — pre-rule, model, or a safety redirect.
    private var originLabel: String {
        switch plan.origin {
        case .preRule: return L10n.t("preview.origin.preRule")
        case .model: return L10n.t("preview.origin.model")
        case .taxonomy: return L10n.t("preview.origin.taxonomy")
        case .confidence: return L10n.t("preview.origin.confidence")
        case .system: return L10n.t("preview.origin.system")
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
    @State private var status: String?
    /// Undo can hash a large copy's full content; while one runs, the buttons
    /// must not accept a second click (a double-undo can only fail noisily).
    @State private var busy = false

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
                                .disabled(busy)
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
                    .disabled(busy)
                if busy {
                    ProgressView().controlSize(.small)
                } else if let status {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(L10n.t("journal.undoAll")) { undoLastBatch() }
                    .disabled(entries.isEmpty || busy)
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
        guard !busy else { return }
        Task { @MainActor in
            busy = true
            defer { busy = false }
            do {
                // Via AppState so the ledger learns about the restored file —
                // otherwise the next scan would just move it back.
                try await state.undo(entry)
                entries.removeAll { $0.id == entry.id }
                status = L10n.t("journal.undone", entry.destination.lastPathComponent)
            } catch {
                self.error = L10n.t("journal.undoFailed", entry.destination.lastPathComponent, error.localizedDescription)
            }
        }
    }

    private func undoLastBatch() {
        guard !busy else { return }
        Task { @MainActor in
            busy = true
            defer { busy = false }
            let result = await state.undoLastBatch()
            reload()
            status = L10n.t("journal.undoBatchDone", result.undone)
            if result.failed > 0 {
                error = L10n.t("journal.undoBatchFailed", result.failed)
            }
        }
    }
}
