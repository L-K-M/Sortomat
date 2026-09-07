import SwiftUI

/// What is wrong with the rule *as a whole* — no watched folder, no
/// destination, a duplicate destination root, the model with no instruction.
///
/// Everything that belongs to a step, a condition or an action is drawn
/// against that row instead, in `StepCard`. Anything a rule editor can tell
/// you before you enable a rule is worth more than the same sentence in a log
/// afterwards, and a sentence next to the picker that caused it is worth more
/// than the same sentence in a list at the bottom.
struct RuleIssues: View {
    let rule: Rule

    /// Only what belongs to the rule as a whole. Everything about a step, a
    /// condition or an action is drawn against that row in the step card, so
    /// repeating it here would say each thing twice and bury the two findings
    /// — no watched folder, no destination — that have nowhere else to go.
    private var findings: [RuleValidator.Finding] {
        RuleValidator.findings(for: rule).filter { $0.stepID == nil }
    }

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
                        Text(finding.message)
                            .font(.callout)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}
