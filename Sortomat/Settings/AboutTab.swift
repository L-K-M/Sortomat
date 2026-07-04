import AppKit
import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 96, height: 96)
            }
            Text("Sortomat")
                .font(.largeTitle.bold())
            Text(L10n.t("about.tagline"))
                .foregroundStyle(.secondary)
            Text(L10n.t("about.version", "\(AppInfo.shortVersion) (\(AppInfo.buildVersion))"))
                .font(.callout)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Button(L10n.t("about.help")) {
                    if let url = URL(string: "https://github.com/\(AppInfo.repoOwner)/\(AppInfo.repoName)") {
                        NSWorkspace.shared.open(url)
                    }
                }
                Button(L10n.t("menu.openLog")) {
                    NSWorkspace.shared.open(ConfigStore.logFile)
                }
            }
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }
}
