import SwiftUI
import UIKit
import UserNotifications

/// Home Screen quick actions (getoond bij lang indrukken van het app-icoon).
enum QuickAction {
    /// Start een timer met het laatst gebruikte project en gebruiker.
    static let startRecentTimer = "startRecentTimer"
    /// Stop de op dit moment lopende timer.
    static let stopRunningTimer = "stopRunningTimer"
}

/// Houdt de laatst getikte quick action vast tot de UI hem heeft afgehandeld,
/// en beheert de dynamische menu-items op het app-icoon.
@MainActor
final class QuickActionCenter: ObservableObject {
    static let shared = QuickActionCenter()
    @Published var pending: String?

    private init() {}

    /// Stelt het menu samen op basis van de huidige timer-status:
    /// een stop-item als er een timer loopt, anders een start-item met de
    /// naam van het laatst gebruikte project.
    func updateShortcuts(isRunning: Bool, projectName: String?) {
        let item: UIApplicationShortcutItem
        if isRunning {
            item = UIApplicationShortcutItem(
                type: QuickAction.stopRunningTimer,
                localizedTitle: "Stop timer",
                localizedSubtitle: projectName.map { "Project: \($0)" },
                icon: UIApplicationShortcutIcon(systemImageName: "stop.fill"),
                userInfo: nil
            )
        } else {
            item = UIApplicationShortcutItem(
                type: QuickAction.startRecentTimer,
                localizedTitle: "Start recente timer",
                localizedSubtitle: projectName.map { "Project: \($0)" } ?? "Laatst gebruikte project",
                icon: UIApplicationShortcutIcon(systemImageName: "play.fill"),
                userInfo: nil
            )
        }
        UIApplication.shared.shortcutItems = [item]
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Koude start via een quick action: de getikte actie zit in `options`.
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        if let shortcut = options.shortcutItem {
            let type = shortcut.type
            Task { @MainActor in QuickActionCenter.shared.pending = type }
        }
        return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
    }

    /// App draait al (voorgrond/achtergrond) en er wordt een quick action getikt.
    func application(
        _ application: UIApplication,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let type = shortcutItem.type
        Task { @MainActor in QuickActionCenter.shared.pending = type }
        completionHandler(true)
    }
}

@main
struct MoneybirdTimerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = TimerViewModel()

    init() {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared
        registerNotificationCategories()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(viewModel)
        }
    }

    private func registerNotificationCategories() {
        let viewAction = UNNotificationAction(
            identifier: "VIEW_TIMER",
            title: "Bekijk timer",
            options: .foreground
        )
        let stopAction = UNNotificationAction(
            identifier: "STOP_TIMER",
            title: "Stop timer",
            options: .destructive
        )
        let category = UNNotificationCategory(
            identifier: "TIMER_WARNING",
            actions: [viewAction, stopAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([category])
    }
}
