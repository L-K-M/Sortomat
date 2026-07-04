import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            RulesTab()
                .tabItem { Label("Regeln", systemImage: "list.bullet.rectangle") }
            GeneralTab()
                .tabItem { Label("Einstellungen", systemImage: "gearshape") }
        }
        .padding(8)
    }
}

// MARK: - Rules

private struct RulesTab: View {
    @EnvironmentObject private var state: AppState
    @State private var selection: UUID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(state.config.rules) { rule in
                        HStack {
                            Circle()
                                .fill(rule.enabled ? Color.green : Color.secondary.opacity(0.4))
                                .frame(width: 8, height: 8)
                            Text(rule.name).lineLimit(1)
                        }
                        .tag(rule.id)
                    }
                }
                Divider()
                HStack(spacing: 12) {
                    Button {
                        var rule = Rule()
                        rule.enabled = false
                        state.config.rules.append(rule)
                        selection = rule.id
                        state.persistAndApply()
                    } label: { Image(systemName: "plus") }

                    Button {
                        if let id = selection {
                            state.config.rules.removeAll { $0.id == id }
                            selection = nil
                            state.persistAndApply()
                        }
                    } label: { Image(systemName: "minus") }
                    .disabled(selection == nil)

                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(8)
            }
            .frame(minWidth: 200, maxWidth: 280)

            if let index = state.config.rules.firstIndex(where: { $0.id == selection }) {
                RuleEditor(rule: $state.config.rules[index])
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("Regel auswählen oder mit + anlegen")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = state.config.rules.first?.id }
    }
}

private struct RuleEditor: View {
    @EnvironmentObject private var state: AppState
    @Binding var rule: Rule
    @State private var extensionsText = ""

    var body: some View {
        Form {
            TextField("Name:", text: $rule.name)
            Toggle("Regel aktiv", isOn: $rule.enabled)

            PathField(label: "Überwachter Ordner:", path: $rule.watchPath)
            PathField(label: "Zielordner:", path: $rule.targetPath)

            TextField(
                "Dateiendungen:", text: $extensionsText,
                prompt: Text("z.B. epub, pdf – leer = alle Dateien")
            )
            .onChange(of: extensionsText) { newValue in
                rule.extensions = newValue
                    .split(separator: ",")
                    .map {
                        $0.trimmingCharacters(in: .whitespaces)
                            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
                            .lowercased()
                    }
                    .filter { !$0.isEmpty }
            }

            Toggle("Kopieren statt verschieben", isOn: $rule.copyInsteadOfMove)

            Section("Sortier-Anweisung (Prompt)") {
                TextEditor(text: $rule.prompt)
                    .font(.body)
                    .frame(minHeight: 160)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3))
                    )
                Text(
                    "Beschreibe, welche Dateien betroffen sind und wie die "
                    + "Zielstruktur aussehen soll, z.B. «{Genre}/{Nachname, Vorname}/{Titel}.epub»."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onAppear { extensionsText = rule.extensions.joined(separator: ", ") }
        .onChange(of: rule) { _ in state.persistAndApply() }
    }
}

private struct PathField: View {
    let label: String
    @Binding var path: String

    var body: some View {
        HStack {
            TextField(label, text: $path, prompt: Text("/Pfad/zum/Ordner"))
            Button("Auswählen…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
        }
    }
}

// MARK: - General settings

private struct GeneralTab: View {
    @EnvironmentObject private var state: AppState
    @State private var apiKey = ""
    @State private var keySaved = false

    var body: some View {
        Form {
            Section("Mistral API") {
                HStack {
                    SecureField(
                        "API-Key:", text: $apiKey,
                        prompt: Text(state.apiKeyMissing ? "Noch kein Key hinterlegt" : "••••••••  (gespeichert)")
                    )
                    Button("Sichern") {
                        state.saveAPIKey(apiKey)
                        apiKey = ""
                        keySaved = true
                    }
                    .disabled(apiKey.isEmpty)
                }
                if keySaved {
                    Text("Im Schlüsselbund gespeichert.")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                TextField("Modell:", text: $state.config.model)
                TextField("API-Basis-URL:", text: $state.config.apiBase)
            }

            Section("Überwachung") {
                Slider(
                    value: $state.config.scanIntervalSeconds, in: 15...600, step: 15
                ) {
                    Text("Prüfintervall: \(Int(state.config.scanIntervalSeconds)) s")
                }
                Text(
                    "Ordner werden zusätzlich sofort geprüft, wenn sich etwas ändert. "
                    + "Das Intervall ist nur das Sicherheitsnetz."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Text(
                    "Hinweis: Dateiname, Metadaten und ein Textauszug jeder Datei "
                    + "werden zur Klassifikation an die Mistral-API gesendet."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding()
        .onChange(of: state.config) { _ in state.persistAndApply() }
    }
}
