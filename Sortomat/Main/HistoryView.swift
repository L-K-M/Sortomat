import AppKit
import SwiftUI

/// What Sortomat actually did, newest first, with a way back for each row.
/// Reading the journal is disk work; doing it on the main actor in `onAppear`
/// froze the window for as long as the file took to parse.
struct HistoryView: View {
    @EnvironmentObject private var state: AppState
    @State private var entries: [JournalEntry] = []
    @State private var loading = true
    @State private var busy = false
    @State private var status: String?
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                EmptyState(symbol: "clock", title: L10n.t("history.empty.title"),
                           message: L10n.t("journal.empty"))
            } else {
                List {
                    ForEach(entries) { entry in
                        HistoryRow(entry: entry, busy: busy, onUndo: { undo(entry) })
                    }
                }
            }
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
                    .padding(.horizontal, 12).padding(.vertical, 6)
            }
            Divider()
            footer
        }
        .task { await reload() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(L10n.t("sidebar.history")).font(.title2.weight(.semibold))
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(L10n.t("history.refresh")) { Task { await reload() } }
                .disabled(busy)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            if let status { Text(status).font(.caption).foregroundStyle(.secondary) }
            Spacer()
            Button(L10n.t("journal.undoAll")) { undoLastBatch() }
                .disabled(entries.isEmpty || busy)
        }
        .padding(12)
    }

    private func reload() async {
        error = nil
        let loaded = await Task.detached { Journal.recent(limit: 200) }.value
        entries = loaded
        loading = false
    }

    private func undo(_ entry: JournalEntry) {
        // Set before the task, not inside it: a guard that only takes effect
        // once the first task has started isn't a guard.
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                // Via AppState so the ledger learns about the restored file —
                // otherwise the next check would just move it back.
                try await state.undo(entry)
                entries.removeAll { $0.id == entry.id }
                status = L10n.t("journal.undone", entry.destination.lastPathComponent)
            } catch {
                self.error = L10n.t("journal.undoFailed",
                                    entry.destination.lastPathComponent, error.localizedDescription)
            }
        }
    }

    private func undoLastBatch() {
        guard !busy else { return }
        busy = true
        Task { @MainActor in
            let result = await state.undoLastBatch()
            await reload()
            busy = false
            status = L10n.plural("journal.undoBatchDone", result.undone)
            if result.failed > 0 { error = L10n.plural("journal.undoBatchFailed", result.failed) }
        }
    }
}

private struct HistoryRow: View {
    let entry: JournalEntry
    let busy: Bool
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: entry.wasCopy ? "doc.on.doc" : "arrow.right.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.destination.lastPathComponent).lineLimit(1)
                Text("\(entry.ruleName) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Text(entry.destination.deletingLastPathComponent().path)
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                    .help(entry.destination.path)
            }
            Spacer()
            Button(L10n.t("history.reveal")) {
                NSWorkspace.shared.activateFileViewerSelecting([entry.destination])
            }
            .buttonStyle(.link)
            Button(L10n.t("journal.undo"), action: onUndo)
                .buttonStyle(.borderless)
                .disabled(busy)
        }
        .padding(.vertical, 3)
    }
}
