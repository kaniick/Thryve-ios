import UIKit
import UserNotifications

/// UIKit hooks SwiftUI doesn't have: the APNs device token and notification taps.
final class AppDelegate: NSObject, UIApplicationDelegate {
    private let notificationDelegate = NotificationDelegate()

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = notificationDelegate
        NotificationContent.registerCategories()
        // Tokens can change; iOS hands back the current one on every launch.
        if UnitNotifier.isEnabled() { application.registerForRemoteNotifications() }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushRegistrar.shared.tokenArrived(deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: any Error) {
        PushRegistrar.shared.tokenFailed(error)
    }
}

/// Banners while the app is open, and the Acknowledge action.
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate, Sendable {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard response.actionIdentifier == NotificationContent.acknowledgeAction,
              let alertId = Self.alertId(in: response.notification.request.content.userInfo) else { return }
        await Self.acknowledge(alertId)
    }

    /// Local notifications carry an Int; APNs JSON may decode it as NSNumber or a string.
    nonisolated static func alertId(in userInfo: [AnyHashable: Any]) -> Int? {
        switch userInfo["alertId"] {
        case let n as Int: n
        case let n as NSNumber: n.intValue
        case let s as String: Int(s)
        default: nil
        }
    }

    @MainActor private static func acknowledge(_ alertId: Int) async {
        guard let api = Connection().api else { return }
        do {
            try await api.acknowledgeAlert(id: alertId)
        } catch {
            Log.notify.error("acknowledge \(alertId) failed: \(error.localizedDescription)")
        }
    }
}
