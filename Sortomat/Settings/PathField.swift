import AppKit
import SwiftUI

/// A text field for a folder path plus a "Choose…" button that opens an
/// `NSOpenPanel`.
struct PathField: View {
    let label: String
    @Binding var path: String

    var body: some View {
        HStack {
            TextField(label, text: $path, prompt: Text("/path/to/folder"))
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.canCreateDirectories = true
                panel.allowsMultipleSelection = false
                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
        }
    }
}
