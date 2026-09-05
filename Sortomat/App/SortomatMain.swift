import AppKit
import Foundation

/// Entry point. We drive `NSApplication` directly (not a SwiftUI `App` scene) so
/// Sortomat is a proper menu-bar agent: `.accessory` activation policy, no Dock
/// icon. SwiftUI is used only for content hosted inside AppKit windows. The CLI
/// subcommands (`scan-once`, `preview`, `undo`, `help`, `version`) skip the GUI
/// entirely.
@main
enum SortomatMain {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if let first = args.first, Self.isCommandLineInvocation(first) {
            Task.detached { await HeadlessRunner.run(args) } // never returns; calls exit()
            dispatchMain()
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    /// Any bare word is a command-line invocation — a typo'd launchd
    /// `ProgramArguments` (`scanonce`) used to fall through and boot a second,
    /// never-exiting GUI that fought the real one over the ledger. Flags such
    /// as Xcode's `-NSDocumentRevisionsDebugMode` or Launch Services' old
    /// `-psn_…` still mean "run the app"; only the documented `--help` /
    /// `--version` spellings are routed to the runner.
    static func isCommandLineInvocation(_ argument: String) -> Bool {
        if HeadlessRunner.command(for: argument) != nil { return true }
        return !argument.hasPrefix("-")
    }
}
