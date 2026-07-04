import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var tab: SettingsTab = .rules

    private enum SettingsTab: Hashable { case rules, general, about }

    var body: some View {
        TabView(selection: $tab) {
            RulesTab()
                .tag(SettingsTab.rules)
                .tabItem { Label(L10n.t("tab.rules"), systemImage: "list.bullet.rectangle") }
            GeneralTab()
                .tag(SettingsTab.general)
                .tabItem { Label(L10n.t("tab.general"), systemImage: "gearshape") }
            AboutTab()
                .tag(SettingsTab.about)
                .tabItem { Label(L10n.t("tab.about"), systemImage: "info.circle") }
        }
        .padding(8)
        .frame(minWidth: 720, minHeight: 460)
        // The editing lock only applies while the Rules tab is showing.
        .onAppear { state.setRulesTabActive(tab == .rules) }
        .onChange(of: tab) { newTab in state.setRulesTabActive(newTab == .rules) }
    }
}
