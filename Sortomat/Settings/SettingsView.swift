import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            RulesTab()
                .tabItem { Label(L10n.t("tab.rules"), systemImage: "list.bullet.rectangle") }
            GeneralTab()
                .tabItem { Label(L10n.t("tab.general"), systemImage: "gearshape") }
            AboutTab()
                .tabItem { Label(L10n.t("tab.about"), systemImage: "info.circle") }
        }
        .padding(8)
        .frame(minWidth: 720, minHeight: 460)
    }
}
