import AppKit
import SwiftUI

/// The home screen: everything Sortomat wants to do, one card per file, each
/// answerable on its own. The old Preview window put this behind a menu item
/// nothing pointed at, listed rows too narrow to read, and made "apply" an
/// all-or-nothing checkbox exercise.
struct InboxView: View {
    @EnvironmentObject private var state: AppState
    @State private var busy = false
    @State private var status: String?
    @State private var lastApplied: [PlannedAction] = []

    private var items: [InboxItem] {
        state.pendingActions.map { plan in
            let rule = state.config.rules.first { $0.id == plan.ruleID }
            return InboxItem(
                plan: plan,
                target: URL(fileURLWithPath: ((rule?.targetPath ?? "") as NSString).expandingTildeInPath),
                ruleMode: rule.map(RuleMode.init) ?? .askFirst
            )
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if items.isEmpty {
                EmptyState(
                    symbol: state.apiKeyMissing ? "key" : "checkmark.circle",
                    title: L10n.t(state.apiKeyMissing ? "inbox.empty.noKey.title" : "inbox.empty.title"),
                    message: L10n.t(state.apiKeyMissing ? "inbox.empty.noKey" : "inbox.empty")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(items) { item in
                            InboxCard(item: item, busy: busy, onApply: { apply([item.plan]) },
                                      onSkip: { state.dismiss(item.plan) })
                        }
                    }
                    .padding(14)
                }
            }
            Divider()
            footer
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.plural("inbox.count", items.count))
                    .font(.title2.weight(.semibold))
                if let last = state.lastScan {
                    Text(L10n.t("app.lastScan", last.formatted(date: .omitted, time: .shortened)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if busy { ProgressView().controlSize(.small) }
            Button(L10n.t("inbox.check")) {
                status = nil
                Task { busy = true; await state.refreshPreview(); busy = false }
            }
            .disabled(busy)
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let status {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            if !lastApplied.isEmpty {
                Button(L10n.t("inbox.undoLast")) { undoLast() }
                    .buttonStyle(.link)
                    .disabled(busy)
            }
            Spacer()
            Button(L10n.t("inbox.skipAll")) {
                let all = state.pendingActions
                all.forEach { state.dismiss($0) }
                status = L10n.plural("inbox.skipped", all.count)
            }
            .disabled(items.isEmpty || busy)
            Button(L10n.t("inbox.applyAll")) {
                apply(state.pendingActions.filter(\.isActionable))
            }
            .keyboardShortcut(.defaultAction)
            .disabled(items.allSatisfy { !$0.plan.isActionable } || busy)
        }
        .padding(12)
    }

    private func apply(_ plans: [PlannedAction]) {
        guard !plans.isEmpty else { return }
        Task {
            busy = true
            await state.apply(plans)
            busy = false
            lastApplied = plans
            status = L10n.plural("inbox.applied", plans.count)
        }
    }

    /// Undo is the promise that makes "Apply" safe to press. It reverses the
    /// newest journal batch, which is exactly the set that was just applied.
    private func undoLast() {
        Task {
            busy = true
            let result = await state.undoLastBatch()
            busy = false
            lastApplied = []
            status = result.failed == 0
                ? L10n.plural("journal.undoBatchDone", result.undone)
                : L10n.plural("journal.undoBatchFailed", result.failed)
        }
    }
}

// MARK: - One card

struct InboxCard: View {
    let item: InboxItem
    let busy: Bool
    let onApply: () -> Void
    let onSkip: () -> Void
    @State private var showingWhy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.plan.source.path))
                    .resizable().frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.plan.source.lastPathComponent)
                        .font(.body.weight(.medium))
                        .lineLimit(2)
                        .textSelection(.enabled)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                HeatBadge(heat: item.heat, confidence: item.plan.confidence)
            }

            // The sentence, not a path fragment: "Move to Invoices/2024".
            HStack(spacing: 6) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(actionSentence)
                    .font(.callout)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if showingWhy, !item.plan.reason.isEmpty {
                Text(item.plan.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 2)
            }

            HStack(spacing: 8) {
                if !item.plan.reason.isEmpty {
                    Button(showingWhy ? L10n.t("inbox.why.hide") : L10n.t("inbox.why")) {
                        showingWhy.toggle()
                    }
                    .buttonStyle(.link)
                }
                Button(L10n.t("inbox.reveal")) {
                    NSWorkspace.shared.activateFileViewerSelecting([item.plan.source])
                }
                .buttonStyle(.link)
                Spacer()
                Button(L10n.t("inbox.skip"), action: onSkip).disabled(busy)
                Button(L10n.t("inbox.apply"), action: onApply)
                    .disabled(busy || !item.plan.isActionable)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.secondary.opacity(0.18))
        )
    }

    private var subtitle: String {
        let summary = item.summary
        let parts = [item.plan.ruleName, item.originText, summary.sizeText, summary.modifiedText]
        return parts.filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private var actionSentence: String {
        switch item.plan.kind {
        case .move: return L10n.t("inbox.action.move", item.destinationText)
        case .copy: return L10n.t("inbox.action.copy", item.destinationText)
        case .quarantine: return L10n.t("inbox.action.unsure", item.destinationText)
        case .duplicate: return L10n.t("inbox.action.duplicate")
        case .skip: return L10n.t("inbox.action.skip")
        }
    }

    private var symbol: String {
        switch item.plan.kind {
        case .move: return "arrow.right.circle.fill"
        case .copy: return "doc.on.doc.fill"
        case .quarantine: return "questionmark.circle.fill"
        case .duplicate: return "equal.circle.fill"
        case .skip: return "minus.circle.fill"
        }
    }

    private var tint: Color {
        switch item.plan.kind {
        case .move, .copy: return .accentColor
        case .quarantine: return .orange
        default: return .secondary
        }
    }
}

struct HeatBadge: View {
    let heat: Heat
    let confidence: Double?

    var body: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(heat.label)
                .font(.caption.weight(.medium))
                .foregroundStyle(heat.tint)
            if let confidence {
                Text("\(Int((confidence * 100).rounded()))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .help(L10n.t("heat.help"))
    }
}

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol).font(.system(size: 34)).foregroundStyle(.secondary)
            Text(title).font(.title3.weight(.medium))
            Text(message)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
