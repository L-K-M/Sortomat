import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menubar-only app: no Dock icon, no app switcher entry.
        NSApp.setActivationPolicy(.accessory)
    }
}

struct SortomatApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra("Sortomat", systemImage: state.paused ? "tray" : "tray.full") {
            MenuContent()
                .environmentObject(state)
        }

        Window("Sortomat – Regeln", id: "settings") {
            SettingsView()
                .environmentObject(state)
                .frame(minWidth: 780, minHeight: 480)
        }
        .defaultSize(width: 860, height: 540)
    }
}

struct MenuContent: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if state.apiKeyMissing {
                Text("⚠️ Kein Mistral API-Key hinterlegt")
            } else if state.paused {
                Text("Pausiert")
            } else {
                Text("Aktiv – \(state.enabledRuleCount) Regel(n)")
            }
            if let last = state.lastScan {
                Text("Letzte Prüfung: \(last.formatted(date: .omitted, time: .shortened))")
            }

            Divider()

            Button(state.paused ? "Fortsetzen" : "Pausieren") {
                state.paused.toggle()
            }
            Button("Jetzt prüfen") {
                state.requestScan()
            }
            .disabled(state.paused)

            Divider()

            if state.activity.isEmpty {
                Text("Noch keine Aktivität")
            } else {
                Menu("Letzte Aktivität") {
                    ForEach(state.activity.prefix(12)) { entry in
                        Text((entry.ok ? "" : "⚠️ ") + entry.message)
                    }
                    Divider()
                    Button("Protokoll öffnen") {
                        NSWorkspace.shared.open(ConfigStore.logFile)
                    }
                }
            }

            Divider()

            Button("Regeln & Einstellungen…") {
                openWindow(id: "settings")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",")

            Button("Beenden") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
    }
}
