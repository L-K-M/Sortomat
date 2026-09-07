import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var state: AppState
    @State private var apiKey = ""
    /// nil = no verdict shown; true/false = the last save's actual outcome.
    @State private var keySaveSucceeded: Bool?
    @State private var launchAtLogin = LaunchAtLogin.isEnabled

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
                        keySaveSucceeded = state.saveAPIKey(apiKey)
                        if keySaveSucceeded == true { apiKey = "" }
                    }
                    .disabled(apiKey.isEmpty)
                }
                if let outcome = keySaveSucceeded {
                    Text(L10n.t(outcome ? "general.apiKey.saved" : "general.apiKey.saveFailed"))
                        .font(.caption)
                        .foregroundStyle(outcome ? Color.green : Color.red)
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
                TextField(L10n.t("general.pricing.currency"), text: $state.config.currencyCode)
                TextField(L10n.t("general.monthlyBudget"), value: $state.config.monthlyBudget,
                          format: .number)
                Text(L10n.t("general.monthlyBudget.help"))
                    .font(.caption).foregroundStyle(.secondary)
                if state.estimatedSpend > 0 {
                    Text(state.withinMonthlyBudget
                         ? L10n.t("menu.spend", state.estimatedSpendString)
                         : L10n.t("general.monthlyBudget.reached", state.estimatedSpendString))
                        .font(.caption)
                        .foregroundStyle(state.withinMonthlyBudget ? Color.secondary : Color.orange)
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
                Toggle(L10n.t("general.onlyOnPower"), isOn: $state.config.onlyOnPower)
                Toggle(L10n.t("general.pauseInLowPower"), isOn: $state.config.pauseInLowPowerMode)
                Text(L10n.t("general.power.help"))
                    .font(.caption).foregroundStyle(.secondary)
                // README promised this toggle all along; the SMAppService
                // wrapper existed but was never wired to any UI.
                Toggle(L10n.t("general.launchAtLogin"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        LaunchAtLogin.set(enabled)
                        // Registration can be refused (e.g. by System Settings
                        // restrictions); reflect what actually took effect.
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
            }

            Section {
                Text(L10n.t("general.privacyNote"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onChange(of: state.config) { _ in state.persistAndApply() }
        // A stale save verdict must not linger under a key being retyped —
        // but clearing the field after a *successful* save is not typing, and
        // used to wipe the success caption in the same update cycle.
        .onChange(of: apiKey) { newValue in
            if !newValue.isEmpty { keySaveSucceeded = nil }
        }
        // The user may have toggled login items in System Settings meanwhile.
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }
}
