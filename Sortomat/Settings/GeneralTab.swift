import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var state: AppState
    @State private var apiKey = ""
    @State private var keySaved = false

    var body: some View {
        Form {
            Section(L10n.t("general.provider.section")) {
                HStack {
                    SecureField(
                        L10n.t("general.apiKey"), text: $apiKey,
                        prompt: Text(state.apiKeyMissing
                            ? L10n.t("general.apiKey.placeholder.missing")
                            : L10n.t("general.apiKey.placeholder.set"))
                    )
                    Button(L10n.t("general.apiKey.save")) {
                        state.saveAPIKey(apiKey)
                        apiKey = ""
                        keySaved = true
                    }
                    .disabled(apiKey.isEmpty)
                }
                if keySaved {
                    Text(L10n.t("general.apiKey.saved"))
                        .font(.caption).foregroundStyle(.green)
                }
                TextField(L10n.t("general.model"), text: $state.config.model)
                TextField(L10n.t("general.apiBase"), text: $state.config.apiBase)
                Toggle(L10n.t("general.requiresKey"), isOn: $state.config.providerRequiresKey)
                Text(L10n.t("general.localHint"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section(L10n.t("general.pricing.section")) {
                TextField(L10n.t("general.pricing.input"), value: $state.config.inputPricePerMTok,
                          format: .number)
                TextField(L10n.t("general.pricing.output"), value: $state.config.outputPricePerMTok,
                          format: .number)
                if state.estimatedSpend > 0 {
                    Text(L10n.t("menu.spend", state.estimatedSpendString))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            Section(L10n.t("general.watch.section")) {
                VStack(alignment: .leading) {
                    Text(L10n.t("general.interval", Int(state.config.scanIntervalSeconds)))
                    Slider(value: $state.config.scanIntervalSeconds, in: 15...600, step: 15)
                    Text(L10n.t("general.interval.help"))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Stepper(value: $state.config.maxConcurrentClassifications, in: 1...8) {
                    Text(L10n.t("general.concurrency", state.config.maxConcurrentClassifications))
                }
                Stepper(value: $state.config.perScanBudget, in: 0...1000, step: 10) {
                    Text(L10n.t("general.budget", state.config.perScanBudget))
                }
                Toggle(L10n.t("general.notifications"), isOn: $state.config.notificationsEnabled)
            }

            Section {
                Text(L10n.t("general.privacyNote"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: state.config) { _ in state.persistAndApply() }
    }
}
