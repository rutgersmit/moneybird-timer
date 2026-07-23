import Foundation
import UserNotifications

extension Notification.Name {
    static let timerStoppedViaNotification = Notification.Name("timerStoppedViaNotification")
}

final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationDelegate()

    // Toon notificatie ook als de app op de voorgrond staat
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // Verwerk acties uit de notificatie
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == "STOP_TIMER" else {
            // "Bekijk timer" of standaard tap: app opent gewoon
            completionHandler()
            return
        }

        Task {
            if let entryId = UserDefaults.standard.string(forKey: "activeTimeEntryId") {
                try? await MoneybirdAPI.shared.stopTimer(id: entryId)
                UserDefaults.standard.removeObject(forKey: "activeTimeEntryId")
                UserDefaults.standard.removeObject(forKey: "activeTimerStartedAt")
                NotificationCenter.default.post(name: .timerStoppedViaNotification, object: nil)
            }
            completionHandler()
        }
    }
}
