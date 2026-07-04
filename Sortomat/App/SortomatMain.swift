import AppKit
import Foundation

/// Entry point. We drive `NSApplication` directly (not a SwiftUI `App` scene) so
/// Sortomat is a proper menu-bar agent: `.accessory` activation policy, no Dock
/// icon. SwiftUI is used only for content hosted inside AppKit windows. A few
/// CLI subcommands (`scan-once`, `preview`, `undo`) skip the GUI entirely.
@main
enum SortomatMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let command = args.first, ["scan-once", "preview", "undo"].contains(command) {
            Task.detached { await HeadlessRunner.run(args) } // never returns; calls exit()
            dispatchMain()
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
