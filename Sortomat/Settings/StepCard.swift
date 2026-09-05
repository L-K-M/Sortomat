import SwiftUI

/// One "if … then …" of a rule. Replaces the old pre-rule card, which could
/// express exactly one test and one action.
struct StepCard: View {
    @Binding var step: RuleStep
    let position: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let metadataOnly: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            conditions
            actions
            Text(StepSentence.text(for: step))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.08)))
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("\(position)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            TextField(L10n.t("step.name"), text: $step.name)
                .textFieldStyle(.roundedBorder)
            Toggle("", isOn: $step.enabled)
                .labelsHidden()
                .help(L10n.t("step.enabled.help"))
            Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                .buttonStyle(.borderless).disabled(!canMoveUp)
            Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                .buttonStyle(.borderless).disabled(!canMoveDown)
            Button(action: onDelete) { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .accessibilityLabel(L10n.t("step.delete"))
        }
    }

    private var conditions: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.t("step.when"))
                Picker("", selection: $step.when.mode) {
                    Text(L10n.t("step.mode.all")).tag(ConditionGroup.Mode.all)
                    Text(L10n.t("step.mode.any")).tag(ConditionGroup.Mode.any)
                    Text(L10n.t("step.mode.none")).tag(ConditionGroup.Mode.none)
                }
                .labelsHidden()
                .frame(width: 160)
                Spacer()
            }
            if step.when.items.isEmpty {
                Text(L10n.t("step.when.empty"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(step.when.items.indices, id: \.self) { index in
                ConditionRow(
                    condition: $step.when.items[index],
                    metadataOnly: metadataOnly,
                    onDelete: { step.when.items.remove(at: index) }
                )
            }
            Button {
                step.when.items.append(.test(ConditionTest()))
            } label: {
                Label(L10n.t("step.condition.add"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.t("step.then"))
            if step.then.isEmpty {
                Text(L10n.t("step.then.empty"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(step.then.indices, id: \.self) { index in
                ActionRow(
                    action: $step.then[index],
                    onDelete: { step.then.remove(at: index) }
                )
            }
            Button {
                step.then.append(RuleAction(type: .move, template: "{name}"))
            } label: {
                Label(L10n.t("step.action.add"), systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
        }
    }
}

/// A group or a test. Nested groups are shown but not edited here: the model
/// supports any depth, the editor does one level, and a hand-written nested
/// group must survive being looked at.
struct ConditionRow: View {
    @Binding var condition: Condition
    let metadataOnly: Bool
    let onDelete: () -> Void

    var body: some View {
        switch condition {
        case .group(let group):
            HStack {
                Image(systemName: "list.bullet.indent").foregroundStyle(.secondary)
                Text(L10n.t("step.condition.nested", group.mode.rawValue, "\(group.items.count)"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: onDelete) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
        case .test:
            ConditionTestRow(test: testBinding, metadataOnly: metadataOnly, onDelete: onDelete)
        }
    }

    private var testBinding: Binding<ConditionTest> {
        Binding(
            get: {
                if case .test(let test) = condition { return test }
                return ConditionTest()
            },
            set: { condition = .test($0) }
        )
    }
}

struct ConditionTestRow: View {
    @Binding var test: ConditionTest
    let metadataOnly: Bool
    let onDelete: () -> Void

    /// Operators whose value is a list the user types comma-separated.
    private static let listValued: Set<Operator> = [
        .isIn, .notIn, .containsAny, .containsAll, .containsNone, .between
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Picker("", selection: $test.attribute) {
                    ForEach(RuleCatalog.attributes, id: \.attribute.rawValue) { spec in
                        Text(RuleCatalog.label(for: spec.attribute)).tag(spec.attribute)
                    }
                }
                .labelsHidden()
                .frame(width: 200)

                Picker("", selection: $test.op) {
                    ForEach(RuleCatalog.operators(for: test.attribute), id: \.rawValue) { op in
                        Text(RuleCatalog.label(for: op)).tag(op)
                    }
                }
                .labelsHidden()
                .frame(width: 170)

                if needsValue {
                    TextField(placeholder, text: valueText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }
                Button(action: onDelete) { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless)
            }
            if blockedByPrivacy {
                Label(L10n.t("step.condition.needsContent"), systemImage: "eye.slash")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var needsValue: Bool {
        test.op != .isEmpty && test.op != .isNotEmpty
            && test.op != .isTrue && test.op != .isFalse
    }

    /// A condition on file contents can never match while the rule promises
    /// that contents are never read — say so instead of leaving a dead row.
    private var blockedByPrivacy: Bool {
        metadataOnly && RuleCatalog.spec(for: test.attribute)?.needsContent == true
    }

    private var placeholder: String {
        RuleCatalog.spec(for: test.attribute)?.example ?? ""
    }

    private var valueText: Binding<String> {
        Binding(
            get: {
                switch test.value {
                case .list(let items): return items.joined(separator: ", ")
                default: return ValueCoercion.string(test.value) ?? ""
                }
            },
            set: { typed in
                let trimmed = typed.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty {
                    test.value = .none
                } else if Self.listValued.contains(test.op) {
                    test.value = .list(
                        typed.split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces) }
                            .filter { !$0.isEmpty }
                    )
                } else {
                    test.value = .text(typed)
                }
            }
        )
    }
}

struct ActionRow: View {
    @Binding var action: RuleAction
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Picker("", selection: $action.type) {
                ForEach(RuleCatalog.actionTypes, id: \.rawValue) { type in
                    Text(RuleCatalog.label(for: type)).tag(type)
                }
            }
            .labelsHidden()
            .frame(width: 200)

            if RuleCatalog.takesTemplate(action.type) {
                TextField(L10n.t("step.action.template"), text: $action.template)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            } else if RuleCatalog.takesTags(action.type) {
                TextField(L10n.t("step.action.tags"), text: tagsText)
                    .textFieldStyle(.roundedBorder)
            }
            Button(action: onDelete) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
        }
    }

    private var tagsText: Binding<String> {
        Binding(
            get: { action.tags.joined(separator: ", ") },
            set: {
                action.tags = $0.split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

/// The step as one readable sentence — the thing the app's own tagline
/// promises and the old editor never showed.
enum StepSentence {
    static func text(for step: RuleStep) -> String {
        let conditions = step.when.items.compactMap { item -> String? in
            switch item {
            case .test(let test):
                let attribute = RuleCatalog.label(for: test.attribute)
                let op = RuleCatalog.label(for: test.op)
                let value = describe(test.value)
                return value.isEmpty ? "\(attribute) \(op)" : "\(attribute) \(op) «\(value)»"
            case .group(let group):
                return L10n.t("step.condition.nested", group.mode.rawValue, "\(group.items.count)")
            }
        }
        let joiner = step.when.mode == .any
            ? L10n.t("step.join.any")
            : L10n.t("step.join.all")
        let when = conditions.isEmpty
            ? L10n.t("step.sentence.anyFile")
            : (step.when.mode == .none ? L10n.t("step.sentence.none", conditions.joined(separator: joiner))
                                       : conditions.joined(separator: joiner))
        let actions = step.then.map { action -> String in
            let label = RuleCatalog.label(for: action.type)
            if RuleCatalog.takesTemplate(action.type), !action.template.isEmpty {
                return "\(label) \(action.template)"
            }
            if RuleCatalog.takesTags(action.type), !action.tags.isEmpty {
                return "\(label) \(action.tags.joined(separator: ", "))"
            }
            return label
        }
        guard !actions.isEmpty else { return L10n.t("step.sentence.noAction", when) }
        return L10n.t("step.sentence", when, actions.joined(separator: ", "))
    }

    private static func describe(_ value: ConditionValue) -> String {
        switch value {
        case .none: return ""
        case .text(let text): return text
        case .number(let number): return NumberText.canonical(number)
        case .bool(let flag): return flag ? "true" : "false"
        case .list(let list): return list.joined(separator: ", ")
        }
    }
}
