import UIKit
import UserNotifications

// Port of Classes/HFRplusAppDelegate.m (didFinishLaunching: `center.delegate = self`, :164-165; userNotificationCenter:
// didReceiveNotificationResponse:, :186-212) @ 87fe0d1c. Differences: the destination goes to `MPNotificationRouter` instead of
// a `UserDefaults` flag and a `NotificationCenter` post, and it can name a conversation (GAP-011).
extension AppDelegate: UNUserNotificationCenterDelegate {
    /// Becomes the notification delegate before launch ends, so a tap that launches the app is delivered (Apple's rule for
    /// `UNUserNotificationCenter.delegate`).
    func application(
        _ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// A tap on an MP notification: the root opens its destination once it is built.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let destination = MPNotificationDestination(userInfo: response.notification.request.content.userInfo) else { return }
        await MPNotificationRouter.shared.receive(destination)
    }
}
