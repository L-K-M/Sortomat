import Foundation
import UserNotifications

/// Thin wrapper over user notifications, posted when files are filed or a rule
/// fails (PLAN Phase 3). Only ever called from the GUI process (inside the app
/// bundle), never from the headless CLI.
///
/// The banner is the only place most people ever see Sortomat work, so it
/// carries buttons: **Undo** reverses exactly the pass it reports, **Show in
/// Finder** opens where the files landed. A notification that says what
/// happened and offers no way back is a notification you learn to dismiss
/// without reading.
enum Notifier {
    /// What a click on a notification asks the app to do.
    enum Action: Equatable {
        case undo(batch: UUID)
        case reveal(URL)
        case openLog
        /// The body of the notification was clicked, not one of its buttons.
        case open
    }

    /// Installed by the app delegate. Set before `requestAuthorization`, since
    /// a notification can be delivered to a click as soon as one is posted.
    @MainActor static var handler: (@MainActor (Action) -> Void)? {
        didSet { if handler != nil { drainPending() } }
    }

    /// A click that arrived before the handler existed. The delegate is
    /// installed in `applicationWillFinishLaunching` and the handler in
    /// `applicationDidFinishLaunching`, so a cold launch *from* a notification
    /// can deliver its response into that gap — and dropping it would silently
    /// cancel a file-moving action the user asked for.
    @MainActor private static var pending: [Action] = []

    @MainActor private static func drainPending() {
        let queued = pending
        pending = []
        queued.forEach { handler?($0) }
    }

    enum Category {
        static let filed = "sortomat.filed"
        static let failed = "sortomat.failed"
    }

    private enum ActionID {
        static let undo = "sortomat.action.undo"
        static let reveal = "sortomat.action.reveal"
        static let log = "sortomat.action.log"
    }

    private enum InfoKey {
        static let batch = "batch"
        static let reveal = "reveal"
    }

    /// Must run before the app finishes launching. macOS delivers the response
    /// to a click that *launched* the app as soon as launching completes, and
    /// drops it if no delegate is registered by then — so a click on Undo in a
    /// banner left over from a previous session would do nothing at all, which
    /// is precisely the "learn to dismiss without reading" outcome the buttons
    /// exist to avoid.
    static func prepareForLaunch() {
        let center = UNUserNotificationCenter.current()
        // Without a delegate, macOS also suppresses banners while the app is
        // frontmost — exactly when the user has a Sortomat window open and
        // would want to see "filed / failed".
        center.delegate = Responder.shared
        center.setNotificationCategories([filedCategory(), failedCategory()])
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func filedCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: Category.filed,
            actions: [
                // Destructive styling: it moves files, and the red draws the
                // eye to the way out — which is the point of showing it here.
                UNNotificationAction(identifier: ActionID.undo, title: L10n.t("notify.action.undo"),
                                     options: [.destructive]),
                UNNotificationAction(identifier: ActionID.reveal, title: L10n.t("notify.action.reveal"),
                                     options: [.foreground]),
            ],
            intentIdentifiers: [], options: []
        )
    }

    private static func failedCategory() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: Category.failed,
            actions: [
                UNNotificationAction(identifier: ActionID.log, title: L10n.t("notify.action.log"),
                                     options: [.foreground]),
            ],
            intentIdentifiers: [], options: []
        )
    }

    // MARK: - Posting

    /// A pass that filed something: what landed where, with a way back.
    static func postFiled(_ urls: [URL], count: Int, batch: UUID?) {
        guard count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.plural("notify.filed", count)
        content.body = NotificationText.summary(of: urls)
        // One thread identifier shared by every pass, so ten passes over an
        // afternoon stack into one group in Notification Center instead of ten
        // separate cards.
        content.threadIdentifier = "sortomat.pass"
        var info: [String: Any] = [:]
        if let batch { info[InfoKey.batch] = batch.uuidString }
        if let folder = NotificationText.commonFolder(of: urls) ?? urls.first {
            info[InfoKey.reveal] = folder.path
        }
        content.userInfo = info
        if let category = filedCategoryIdentifier(batch: batch, urls: urls) {
            content.categoryIdentifier = category
        }
        deliver(content)
    }

    /// The category to attach to a "filed" banner, or nil when neither button
    /// could do anything. A destructive-looking Undo that silently does nothing
    /// erodes trust faster than no button at all, and both actions need a
    /// payload: the batch to reverse, the folder to open.
    static func filedCategoryIdentifier(batch: UUID?, urls: [URL]) -> String? {
        (batch != nil && !urls.isEmpty) ? Category.filed : nil
    }

    static func postFailed(count: Int, message: String) {
        guard count > 0 else { return }
        let content = UNMutableNotificationContent()
        content.title = L10n.plural("notify.failed", count)
        content.body = message
        content.categoryIdentifier = Category.failed
        content.threadIdentifier = "sortomat.failure"
        deliver(content)
    }

    /// Plain text, no buttons — a missing watch folder has nothing to undo.
    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        deliver(content)
    }

    private static func deliver(_ content: UNMutableNotificationContent) {
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Responding

    /// Which action a delivered notification asks for. Pure, so the mapping
    /// from a click to a consequence is testable without a notification centre.
    static func action(for identifier: String, userInfo: [AnyHashable: Any]) -> Action? {
        switch identifier {
        case ActionID.undo:
            guard let raw = userInfo[InfoKey.batch] as? String, let id = UUID(uuidString: raw) else {
                // No batch id means a journal written before batches, or a
                // pass that filed nothing — reversing "the newest batch" on a
                // guess could undo work the user has since redone.
                return nil
            }
            return .undo(batch: id)
        case ActionID.reveal:
            guard let path = userInfo[InfoKey.reveal] as? String else { return nil }
            return .reveal(URL(fileURLWithPath: path))
        case ActionID.log:
            return .openLog
        case UNNotificationDefaultActionIdentifier:
            return .open
        default:
            return nil // dismissed, or an action from an older build
        }
    }

    private final class Responder: NSObject, UNUserNotificationCenterDelegate {
        static let shared = Responder()

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler:
                @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            didReceive response: UNNotificationResponse,
            withCompletionHandler completionHandler: @escaping () -> Void
        ) {
            let identifier = response.actionIdentifier
            let info = response.notification.request.content.userInfo
            // The callback arrives on an arbitrary queue; everything the
            // handler touches lives on the main actor.
            Task { @MainActor in
                if let action = Notifier.action(for: identifier, userInfo: info) {
                    if let handler = Notifier.handler {
                        handler(action)
                    } else {
                        // A cold launch *from* this click: the delegate exists,
                        // the app delegate hasn't installed the handler yet.
                        Notifier.pending.append(action)
                    }
                }
                completionHandler()
            }
        }
    }
}
