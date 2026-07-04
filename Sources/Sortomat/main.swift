import AppKit
import Foundation

// `Sortomat scan-once` runs the pipeline once without the GUI (for tests,
// scripts, or launchd). Everything else starts the menubar app.
if CommandLine.arguments.contains("scan-once") {
    let semaphore = DispatchSemaphore(value: 0)
    Task.detached {
        await HeadlessRunner.run()
        semaphore.signal() // unreachable (run exits), but keeps the contract clear
    }
    semaphore.wait()
} else {
    SortomatApp.main()
}
