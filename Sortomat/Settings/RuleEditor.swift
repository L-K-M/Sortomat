import SwiftUI

struct RuleEditor: View {
    @EnvironmentObject private var state: AppState
    @Binding var rule: Rule
    @State private var extensionsText = ""

    var body: some View {
        Form {
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
                TextEditor(text: taxonomyBinding)
                    .font(.callout)
                    .frame(minHeight: 80)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
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

            Section(L10n.t("rule.preRules.section")) {
                Text(L10n.t("rule.preRules.help"))
                    .font(.caption).foregroundStyle(.secondary)
                ForEach($rule.preRules) { $preRule in
                    PreRuleRow(preRule: $preRule) {
                        rule.preRules.removeAll { $0.id == preRule.id }
                    }
                    Divider()
                }
                Button {
                    rule.preRules.append(PreRule())
                } label: {
                    Label(L10n.t("rule.preRules.add"), systemImage: "plus.circle")
                }
                .buttonStyle(.borderless)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { extensionsText = rule.extensions.joined(separator: ", ") }
        .onChange(of: rule) { _ in state.persistAndApply() }
    }

    private var taxonomyBinding: Binding<String> {
        Binding(
            get: { rule.taxonomy.joined(separator: "\n") },
            set: { newValue in
                rule.taxonomy = newValue
                    .split(whereSeparator: \.isNewline)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

struct PreRuleRow: View {
    @Binding var preRule: PreRule
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField(L10n.t("rule.preRule.match"), text: $preRule.name, prompt: Text("Name"))
                    .frame(maxWidth: 140)
                Picker("", selection: $preRule.match) {
                    Text(L10n.t("match.glob")).tag(PreRule.Match.glob)
                    Text(L10n.t("match.regex")).tag(PreRule.Match.regex)
                    Text(L10n.t("match.kind")).tag(PreRule.Match.kind)
                    Text(L10n.t("match.olderThanDays")).tag(PreRule.Match.olderThanDays)
                    Text(L10n.t("match.newerThanDays")).tag(PreRule.Match.newerThanDays)
                }
                .labelsHidden()
                .frame(maxWidth: 150)
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            TextField(L10n.t("rule.preRule.pattern"), text: $preRule.pattern,
                      prompt: Text(patternPrompt))
            Picker(L10n.t("rule.preRule.action"), selection: $preRule.action) {
                Text(L10n.t("action.route")).tag(PreRule.Action.route)
                Text(L10n.t("action.skip")).tag(PreRule.Action.skip)
                Text(L10n.t("action.useLLM")).tag(PreRule.Action.useLLM)
            }
            if preRule.action == .route {
                TextField(L10n.t("rule.preRule.route"), text: $preRule.routePath,
                          prompt: Text("Folder/{year}-{month}"))
            }
        }
        .padding(.vertical, 2)
    }

    private var patternPrompt: String {
        switch preRule.match {
        case .glob: return "IMG_*.jpg"
        case .regex: return "^Invoice-\\d+"
        case .kind: return "image, pdf, ebook, video…"
        case .olderThanDays, .newerThanDays: return "30"
        }
    }
}
