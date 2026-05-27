import Foundation
import UserNotifications

/// Lokale Benachrichtigungen bei neuen Nachrichten.
///
/// Wichtig: Da BlueChat keinen Server hat, gibt es KEINE Push-Notifications.
/// Wenn iOS die App per BLE-State-Restoration im Hintergrund weckt und eine
/// Nachricht eintrifft, planen wir eine LOKALE Notification. Das ist die
/// einzige Möglichkeit, den Nutzer ohne Vordergrund-App zu erreichen.
enum NotificationService {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func notifyNewMessage(from sender: String, preview: String) {
        let content = UNMutableNotificationContent()
        content.title = sender
        // Datenminimierung: optional nur „Neue Nachricht" statt Inhalt anzeigen.
        content.body = preview
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
