import SwiftUI

/// The things you set once and forget. Rules — the part of the app people
/// actually work in — live in the main window now, where the Inbox can sit
/// next to them.
struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem { Label(L10n.t("tab.general"), systemImage: "gearshape") }
            AboutTab()
                .tabItem { Label(L10n.t("tab.about"), systemImage: "info.circle") }
        }
        .padding(8)
        .frame(minWidth: 620, minHeight: 420)
    }
}
