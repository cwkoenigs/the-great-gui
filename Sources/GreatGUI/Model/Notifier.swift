import Foundation
import UserNotifications

/// macOS notifications for scheduled runs that fail. The window asks for permission once a schedule exists;
/// the command line, running inside the same bundle, posts. Nothing happens outside a bundle (swift run).
enum Notifier {
    /// Only inside the app's own bundle: the notification centre refuses a process that is not one (a test
    /// runner has a bundle identifier and still is not), and says so by raising.
    static var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    static func requestAuthorizationIfNeeded() {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Posts and waits a moment, so a command-line process does not exit before the request is delivered.
    static func post(title: String, body: String) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        let done = DispatchSemaphore(value: 0)
        center.getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else { done.signal(); return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { _ in done.signal() }
        }
        _ = done.wait(timeout: .now() + 3)
    }
}
