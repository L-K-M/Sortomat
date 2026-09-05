import AppKit
import SwiftUI

struct RuleEditor: View {
    @EnvironmentObject private var state: AppState
    @Binding var rule: Rule
    // Raw edit buffers: editing these directly (rather than a computed binding
    // that reparses on every keystroke) is what lets Return actually insert a
    // newline in the taxonomy field and keeps the extensions text stable.
    @State private var extensionsText = ""
    @State private var taxonomyText = ""
    @State private var tryResult: String?
    @State private var matchResult: String?
    @State private var counting = false

    var body: some View {
        Form {
            // The editing lock is a good idea with zero UI: an enabled rule
            // silently stops running while it's open here. Say so.
            if rule.enabled, !rule.dryRun, state.editingRuleID == rule.id {
                Section {
                    Label(L10n.t("rule.editingPaused"), systemImage: "pause.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                TextField(L10n.t("rule.name"), text: $rule.name)
                Toggle(L10n.t("rule.enabled"), isOn: $rule.enabled)
                Toggle(L10n.t("rule.dryRun"), isOn: $rule.dryRun)
                Stepper(value: $rule.priority, in: 0...100) {
                    Text("\(L10n.t("rule.priority")) \(rule.priority)")
                }
            }

            Section {
                PathField(label: L10n.t("rule.watchFolder"), path: $rule.watchPath)
                PathField(label: L10n.t("rule.targetFolder"), path: $rule.targetPath)
                // These misconfigurations previously failed in silence —
                // watch == target (or watch inside target) yields zero
                // candidates forever with no hint anywhere.
                ForEach(pathWarnings, id: \.self) { warning in
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Toggle(L10n.t("rule.recursive"), isOn: $rule.recursive)
                TextField(L10n.t("rule.extensions"), text: $extensionsText,
                          prompt: Text(L10n.t("rule.extensions.prompt")))
                    .onChange(of: extensionsText) { newValue in
                        rule.extensions = newValue
                            .split(separator: ",")
                            .map {
                                $0.trimmingCharacters(in: .whitespaces)
                                    .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                                    .lowercased()
                            }
                            .filter { !$0.isEmpty }
                    }
                Toggle(L10n.t("rule.copy"), isOn: $rule.copyInsteadOfMove)
                Picker(L10n.t("rule.privacy"), selection: $rule.privacyMode) {
                    Text(L10n.t("rule.privacy.full")).tag(PrivacyMode.full)
                    Text(L10n.t("rule.privacy.metadataOnly")).tag(PrivacyMode.metadataOnly)
                }
            }

            Section(L10n.t("rule.prompt.section")) {
                TextEditor(text: $rule.prompt)
                    .font(.body)
                    .frame(minHeight: 120)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                Text(L10n.t("rule.prompt.help"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t("rule.taxonomy.section")) {
                TextEditor(text: $taxonomyText)
                    .font(.callout)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
                    // TextEditor has no placeholder support; the hint string
                    // existed in the table but was never shown anywhere.
                    .overlay(alignment: .topLeading) {
                        if taxonomyText.isEmpty {
                            Text(L10n.t("rule.taxonomy.prompt"))
                                .font(.callout)
                                .foregroundStyle(Color.secondary.opacity(0.7))
                                .padding(.top, 8)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                    .onChange(of: taxonomyText) { newValue in
                        rule.taxonomy = newValue
                            .split(whereSeparator: \.isNewline)
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    }
                Text(L10n.t("rule.taxonomy.help"))
                    .font(.caption).foregroundStyle(.secondary)
                TextField(L10n.t("rule.quarantine"), text: $rule.quarantineSubfolder)
                VStack(alignment: .leading) {
                    Text(L10n.t("rule.confidence", Int(rule.confidenceThreshold * 100)))
                    Slider(value: $rule.confidenceThreshold, in: 0...1, step: 0.05)
                    Text(L10n.t("rule.confidence.help"))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            RuleIssues(rule: rule)

            Section(L10n.t("rule.steps.section")) {
                Text(L10n.t("rule.steps.help"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(rule.steps.indices, id: \.self) { index in
                    StepCard(
                        step: $rule.steps[index],
                        rule: rule,
                        position: index + 1,
                        canMoveUp: index > 0,
                        canMoveDown: index < rule.steps.count - 1,
                        metadataOnly: rule.privacyMode == .metadataOnly,
                        onMoveUp: { move(index, by: -1) },
                        onMoveDown: { move(index, by: 1) },
                        onDelete: { rule.steps.remove(at: index) }
                    )
                    .padding(.vertical, 4)
                }
                Button {
                    rule.steps.append(RuleStep(
                        when: ConditionGroup(mode: .all, items: [.test(ConditionTest())]),
                        then: [RuleAction(type: .move, template: "{name}")]
                    ))
                } label: {
                    Label(L10n.t("rule.steps.add"), systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)

                Divider()

                HStack(spacing: 10) {
                    Button(L10n.t("rule.tryIt.pick")) { tryOneFile() }
                    Button(L10n.t("rule.tryIt.count")) { countMatches() }
                        .disabled(counting || rule.watchPath.isEmpty)
                    if counting { ProgressView().controlSize(.small) }
                    Spacer()
                }
                if let tryResult {
                    Text(tryResult)
                        .font(.callout)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let matchResult {
                    Text(matchResult).font(.callout)
                }
                Text(L10n.t("rule.tryIt.help"))
                    .font(.caption).foregroundStyle(.secondary)

                Picker(L10n.t("rule.fallback"), selection: $rule.fallback) {
                    Text(L10n.t("rule.fallback.askModel")).tag(Rule.Fallback.askModel)
                    Text(L10n.t("rule.fallback.skip")).tag(Rule.Fallback.skip)
                    Text(L10n.t("rule.fallback.quarantine")).tag(Rule.Fallback.quarantine)
                }
                Text(L10n.t("rule.fallback.help"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            extensionsText = rule.extensions.joined(separator: ", ")
            taxonomyText = rule.taxonomy.joined(separator: "\n")
        }
        .onChange(of: rule) { _ in state.persistAndApply() }
    }

    /// Run the rule against one chosen file without enabling it, writing
    /// anything down, or calling the model.
    private func tryOneFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !rule.watchPath.isEmpty {
            panel.directoryURL = URL(
                fileURLWithPath: (rule.watchPath as NSString).expandingTildeInPath
            )
        }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let rule = rule
        Task { @MainActor in
            let run = await state.tryRule(rule, on: url)
            let name = url.lastPathComponent
            if run.needsModel {
                tryResult = L10n.t("rule.tryIt.needsModel", name, run.summary)
            } else if let destination = run.destination, run.operation != .skip {
                tryResult = L10n.t("rule.tryIt.would", name,
                                   RuleCatalog.label(for: operationType(run.operation)),
                                   destination, run.summary)
            } else {
                tryResult = L10n.t("rule.tryIt.skip", name, run.summary)
            }
        }
    }

    private func countMatches() {
        counting = true
        let rule = rule
        Task { @MainActor in
            let counts = await state.matchCount(for: rule)
            counting = false
            matchResult = L10n.t("rule.tryIt.matches", "\(counts.matched)",
                                 "\(counts.scanned)", "\(counts.needsModel)")
        }
    }

    private func operationType(_ operation: Placement.Operation) -> ActionType {
        switch operation {
        case .move: return .move
        case .copy: return .copy
        case .rename: return .rename
        case .trash: return .trash
        case .quarantine: return .quarantine
        case .skip: return .skip
        }
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard rule.steps.indices.contains(index), rule.steps.indices.contains(target) else { return }
        rule.steps.swapAt(index, target)
    }

    private var pathWarnings: [String] {
        var warnings: [String] = []
        let fm = FileManager.default
        // Resolve links and compare case-insensitively: on a default APFS
        // volume "~/Downloads" and "~/downloads" are the same folder, and a
        // watch path that reaches the target through a symlink is the same
        // misconfiguration as naming it directly.
        func canonical(_ path: String) -> String {
            URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
                .resolvingSymlinksInPath().standardizedFileURL.path
        }
        let watch = canonical(rule.watchPath)
        let target = canonical(rule.targetPath)
        func isDirectory(_ path: String) -> Bool {
            var isDir: ObjCBool = false
            return fm.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
        }
        if !rule.watchPath.isEmpty, !isDirectory(watch) {
            warnings.append(L10n.t("rule.validate.watchMissing"))
        }
        if !rule.targetPath.isEmpty, !isDirectory(target) {
            warnings.append(L10n.t("rule.validate.targetMissing"))
        }
        if !rule.watchPath.isEmpty, watch.compare(target, options: .caseInsensitive) == .orderedSame {
            warnings.append(L10n.t("rule.validate.samePath"))
        } else if !rule.watchPath.isEmpty, !rule.targetPath.isEmpty,
                  watch.lowercased().hasPrefix(target.lowercased() + "/") {
            warnings.append(L10n.t("rule.validate.watchInsideTarget"))
        } else if rule.recursive, !rule.watchPath.isEmpty, !rule.targetPath.isEmpty,
                  target.lowercased().hasPrefix(watch.lowercased() + "/") {
            // Filed files land back inside the watched tree. The scan skips the
            // target subtree so nothing loops, but the folder is worth naming.
            warnings.append(L10n.t("rule.validate.targetInsideWatch"))
        }
        return warnings
    }
}

/// One deterministic pre-rule, presented as a roomy card: a numbered header with
/// reorder/delete controls, aligned Match / Pattern / Action rows with inline
/// help, and a plain-language summary of what it does.
struct PreRuleCard: View {
    @Binding var preRule: PreRule
    let position: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    label(L10n.t("rule.preRule.match"))
                    Picker("", selection: $preRule.match) {
                        Text(L10n.t("match.glob")).tag(PreRule.Match.glob)
                        Text(L10n.t("match.regex")).tag(PreRule.Match.regex)
                        Text(L10n.t("match.kind")).tag(PreRule.Match.kind)
                        Text(L10n.t("match.olderThanDays")).tag(PreRule.Match.olderThanDays)
                        Text(L10n.t("match.newerThanDays")).tag(PreRule.Match.newerThanDays)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                GridRow {
                    label(L10n.t("rule.preRule.pattern"))
                    VStack(alignment: .leading, spacing: 3) {
                        TextField("", text: $preRule.pattern, prompt: Text(patternPrompt))
                        Text(patternHelp).font(.caption2).foregroundStyle(.secondary)
                        // An invalid regex silently never matches — flag it
                        // right where it's being typed.
                        if preRule.match == .regex, !preRule.pattern.isEmpty,
                           !DeterministicEngine.isValidRegex(preRule.pattern) {
                            Text(L10n.t("rule.validate.badRegex"))
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                GridRow {
                    label(L10n.t("rule.preRule.action"))
                    Picker("", selection: $preRule.action) {
                        Text(L10n.t("action.route")).tag(PreRule.Action.route)
                        Text(L10n.t("action.skip")).tag(PreRule.Action.skip)
                        Text(L10n.t("action.useLLM")).tag(PreRule.Action.useLLM)
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if preRule.action == .route {
                    GridRow {
                        label(L10n.t("rule.preRule.route"))
                        VStack(alignment: .leading, spacing: 3) {
                            TextField("", text: $preRule.routePath,
                                      prompt: Text("Photos/{year}-{month}"))
                            Text(L10n.t("preRule.route.help")).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            summary
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .textBackgroundColor).opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(position)")
                .font(.caption.bold().monospacedDigit())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.accentColor))
            TextField("", text: $preRule.name, prompt: Text(L10n.t("preRule.name.prompt")))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 220)
            Spacer()
            Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                .disabled(!canMoveUp).help(L10n.t("preRule.moveUp"))
            Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                .disabled(!canMoveDown).help(L10n.t("preRule.moveDown"))
            Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                .help(L10n.t("preRule.delete"))
        }
        .buttonStyle(.borderless)
    }

    private var summary: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
            Text(summaryText).font(.caption).italic().foregroundStyle(.secondary)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .gridColumnAlignment(.trailing)
            .foregroundStyle(.secondary)
    }

    private var patternPrompt: String {
        switch preRule.match {
        case .glob: return "IMG_*.jpg"
        case .regex: return "^Invoice-\\d+"
        case .kind: return "image, pdf, ebook…"
        case .olderThanDays, .newerThanDays: return "30"
        }
    }

    private var patternHelp: String {
        switch preRule.match {
        case .glob: return L10n.t("preRule.help.glob")
        case .regex: return L10n.t("preRule.help.regex")
        case .kind: return L10n.t("preRule.help.kind")
        case .olderThanDays, .newerThanDays: return L10n.t("preRule.help.days")
        }
    }

    private var summaryText: String {
        let pattern = preRule.pattern.isEmpty ? L10n.t("preRule.sum.placeholder") : preRule.pattern
        let condition: String
        switch preRule.match {
        case .glob: condition = L10n.t("preRule.sum.glob", pattern)
        case .regex: condition = L10n.t("preRule.sum.regex", pattern)
        case .kind: condition = L10n.t("preRule.sum.kind", pattern)
        case .olderThanDays: condition = L10n.t("preRule.sum.olderThanDays", pattern)
        case .newerThanDays: condition = L10n.t("preRule.sum.newerThanDays", pattern)
        }
        let action: String
        switch preRule.action {
        case .route:
            let route = preRule.routePath.isEmpty ? L10n.t("preRule.sum.placeholder") : preRule.routePath
            action = L10n.t("preRule.sum.route", route)
        case .skip: action = L10n.t("preRule.sum.skip")
        case .useLLM: action = L10n.t("preRule.sum.useLLM")
        }
        return L10n.t("preRule.sum.template", condition, action)
    }
}
