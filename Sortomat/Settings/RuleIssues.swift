import SwiftUI

/// What the validator found, drawn in the editor next to the rule it is about.
///
/// The list is deliberately plain: an icon, the step it belongs to, and one
/// sentence saying what is wrong in the same words the user typed. Anything a
/// rule editor can tell you *before* you enable a rule is worth more than the
/// same sentence in a log afterwards.
struct RuleIssues: View {
    let rule: Rule

    private var findings: [RuleValidator.Finding] { RuleValidator.findings(for: rule) }

    var body: some View {
        let found = findings
        if !found.isEmpty {
            Section(L10n.t("validate.section")) {
                ForEach(found) { finding in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: finding.severity == .error
                              ? "exclamationmark.triangle.fill"
                              : "info.circle")
                            .foregroundStyle(finding.severity == .error
                                             ? Color.red : Color.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            if let label = stepLabel(finding) {
                                Text(label)
                                    .font(.caption)
                                    .foregroundStyle(Color.secondary)
                            }
                            Text(finding.message)
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    /// "Step 2" or "Step 2 · Invoices", so a finding can be found.
    private func stepLabel(_ finding: RuleValidator.Finding) -> String? {
        guard let id = finding.stepID,
              let index = rule.steps.firstIndex(where: { $0.id == id })
        else { return nil }
        let name = rule.steps[index].name.trimmingCharacters(in: .whitespaces)
        let position = "\(index + 1)"
        return name.isEmpty
            ? L10n.t("validate.stepLabel", position)
            : L10n.t("validate.stepLabelNamed", position, name)
    }
}
