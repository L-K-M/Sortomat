import Foundation
import UserNotifications

/// Thin wrapper over user notifications, posted when files are filed or a rule
/// fails (PLAN Phase 3). Only ever called from the GUI process (inside the app
/// bundle), never from the headless CLI.
enum Notifier {
    static func requestAuthorization() {
        let center = UNUserNotificationCenter.current()
        // Without a delegate, macOS suppresses banners while the app is
        // frontmost — exactly when the user has a Sortomat window open and
        // would want to see "filed / failed".
        center.delegate = ForegroundPresenter.shared
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private final class ForegroundPresenter: NSObject, UNUserNotificationCenterDelegate {
        static let shared = ForegroundPresenter()

        func userNotificationCenter(
            _ center: UNUserNotificationCenter,
            willPresent notification: UNNotification,
            withCompletionHandler completionHandler:
                @escaping (UNNotificationPresentationOptions) -> Void
        ) {
            completionHandler([.banner, .sound])
        }
    }

    static func post(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
