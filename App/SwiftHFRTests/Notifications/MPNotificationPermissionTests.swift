import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// What iOS says about the app's notifications, scripted (#1060): no real notification center in unit tests.
actor FakeNotificationPermission: NotificationPermissionReading {
    private(set) var permission: NotificationPermission
    private(set) var requests = 0
    private(set) var reads = 0
    /// What the system prompt answers.
    private let answer: NotificationPermission

    init(_ permission: NotificationPermission, answer: NotificationPermission = .allowed) {
        self.permission = permission
        self.answer = answer
    }

    func current() -> NotificationPermission {
        reads += 1
        return permission
    }

    func requestAuthorization() {
        requests += 1
        permission = answer
    }

    func change(to permission: NotificationPermission) { self.permission = permission }
}

extension NotificationPermission {
    static let allowed = NotificationPermission(authorization: .allowed, badgesAllowed: true)
    static let denied = NotificationPermission(authorization: .denied, badgesAllowed: false)
    static let notDetermined = NotificationPermission(authorization: .notDetermined, badgesAllowed: false)
    static let badgesOff = NotificationPermission(authorization: .allowed, badgesAllowed: false)
}

/// #1060: the « Notifications » switch of Réglages › Notifications MP and the alert when a switch disagrees with iOS.
@MainActor
struct MPNotificationPermissionTests {
    private func model(
        _ permission: FakeNotificationPermission, store: InMemorySettingsStore = InMemorySettingsStore()
    ) -> MPNotificationSettingsModel {
        MPNotificationSettingsModel(
            store: store, ledger: NotificationLedgerStore(persistence: InMemorySmallStorePersistence()), reschedule: {},
            permission: permission
        )
    }

    @Test("The switch reads its stored value, on when absent, and writes it under mp_notifications_enabled")
    func storedSwitch() {
        let store = InMemorySettingsStore()
        let model = model(FakeNotificationPermission(.allowed), store: store)
        #expect(model.notificationsEnabled)
        model.notificationsEnabled = false
        #expect(!store.value(for: SettingKey.mpNotificationsEnabled))
        #expect(!self.model(FakeNotificationPermission(.allowed), store: store).notificationsEnabled)
    }

    @Test(
        "The alert for each iOS state, both switches on: denied asks for notifications, badges off for the badge, else none",
        arguments: [
            (NotificationPermission.allowed, MPNotificationSettingsAlert?.none),
            (.denied, .notifications),
            (.notDetermined, nil),
            (.badgesOff, .badge)
        ]
    )
    func alertForEachState(permission: NotificationPermission, expected: MPNotificationSettingsAlert?) async {
        let model = model(FakeNotificationPermission(permission))
        await model.checkPermission()
        #expect(model.alert == expected)
    }

    @Test("A switch that is off never disagrees with iOS; both on and notifications refused: that alert alone")
    func offSwitches() {
        #expect(MPNotificationSettingsModel.disagreements(notifications: false, badge: false, with: .denied).isEmpty)
        #expect(MPNotificationSettingsModel.disagreements(notifications: false, badge: true, with: .denied) == [.badge])
        #expect(MPNotificationSettingsModel.disagreements(notifications: true, badge: false, with: .badgesOff).isEmpty)
        // Refused notifications cover the badge: one alert, never a badge alert after it.
        #expect(MPNotificationSettingsModel.disagreements(notifications: true, badge: true, with: .denied) == [.notifications])
    }

    @Test("Each alert once per opening (the model's life), iOS read again on every return; a new opening shows it again")
    func oncePerOpening() async {
        let permission = FakeNotificationPermission(.denied)
        let model = model(permission)
        await model.checkPermission()
        #expect(model.alert == .notifications)
        model.alert = nil
        // Back from iOS's settings, still denied: read, not shown again.
        await model.checkPermission()
        #expect(model.alert == nil)
        #expect(await permission.reads == 2)
        // A new opening of Réglages is a new model.
        let reopened = self.model(permission)
        await reopened.checkPermission()
        #expect(reopened.alert == .notifications)
    }

    @Test("Réglages appearing again (back from Thème, Icône or Listes) is not a new opening: no second alert")
    func appearingAgainIsNotAnOpening() async {
        let permission = FakeNotificationPermission(.denied)
        let model = model(permission)
        await model.checkPermission()
        #expect(model.alert == .notifications)
        model.alert = nil
        await model.checkPermission()
        #expect(model.alert == nil)
        #expect(await permission.reads == 2)
    }

    @Test("Notifications allowed in iOS but badges still off on return: the badge alert, once")
    func badgeAlertAfterNotificationsAlert() async {
        let permission = FakeNotificationPermission(.denied)
        let model = model(permission)
        await model.checkPermission()
        #expect(model.alert == .notifications)
        model.alert = nil
        await permission.change(to: .badgesOff)
        await model.checkPermission()
        #expect(model.alert == .badge)
        model.alert = nil
        await model.checkPermission()
        #expect(model.alert == nil)
    }

    @Test("An alert on screen is never replaced by another")
    func oneAlertAtATime() async {
        let permission = FakeNotificationPermission(.denied)
        let model = model(permission)
        await model.checkPermission()
        await permission.change(to: .badgesOff)
        await model.checkPermission()
        #expect(model.alert == .notifications)
    }

    @Test("Back from iOS's settings: what changed there is read again")
    func rereadOnReturn() async {
        let permission = FakeNotificationPermission(.allowed)
        let model = model(permission)
        await model.checkPermission()
        #expect(model.alert == nil)
        await permission.change(to: .badgesOff)
        await model.checkPermission()
        #expect(model.alert == .badge)
    }

    @Test("Turning Notifications on: denied shows the alert, even after one this opening; not determined asks iOS, no alert")
    func turningNotificationsOn() async {
        let denied = FakeNotificationPermission(.denied)
        let model = model(denied)
        await model.checkPermission()
        model.alert = nil
        model.notificationsEnabled = false
        model.notificationsEnabled = true
        await model.notificationsTurnedOn()
        #expect(model.alert == .notifications)
        #expect(await denied.requests == 0)

        let undecided = FakeNotificationPermission(.notDetermined, answer: .denied)
        let other = self.model(undecided)
        await other.notificationsTurnedOn()
        #expect(await undecided.requests == 1)
        #expect(other.alert == nil)
    }

    @Test("Turning the badge on while iOS shows no badge: the badge alert; turning Notifications on never shows it")
    func turningBadgeOn() async {
        let model = model(FakeNotificationPermission(.badgesOff))
        await model.notificationsTurnedOn()
        #expect(model.alert == nil)
        await model.badgeTurnedOn()
        #expect(model.alert == .badge)
    }

    /// #1172: an account can be current while iOS never asked (both switches were off at the login): the badge asks too.
    @Test("Turning the badge on while iOS never asked shows the system prompt, no alert")
    func turningBadgeOnWhileNeverAsked() async {
        let undecided = FakeNotificationPermission(.notDetermined, answer: .badgesOff)
        let model = model(undecided)
        await model.badgeTurnedOn()
        #expect(await undecided.requests == 1)
        #expect(model.alert == nil)
    }

    @Test("Turning the badge on with « Notifications » on and refused in iOS: the notifications alert, as on opening")
    func turningBadgeOnWhileNotificationsRefused() async {
        let model = model(FakeNotificationPermission(.denied))
        await model.badgeTurnedOn()
        #expect(model.alert == .notifications)
    }

    @Test("An alert already pending counts as shown: dismissed, it does not come back this opening")
    func pendingAlertCountsAsShown() async {
        let model = model(FakeNotificationPermission(.badgesOff))
        model.alert = .badge
        await model.checkPermission()
        model.alert = nil
        await model.checkPermission()
        #expect(model.alert == nil)
    }

    @Test("The French texts of the alert")
    func texts() {
        #expect(MPNotificationSettingsAlert.notifications.title == "Notifications désactivées dans iOS")
        #expect(MPNotificationSettingsAlert.badge.title == "Notifications désactivées dans iOS")
        #expect(
            MPNotificationSettingsAlert.notifications.message
                == "Autorisez SwiftHFR dans Réglages › Notifications pour recevoir les messages privés."
        )
        #expect(
            MPNotificationSettingsAlert.badge.message
                == "Autorisez SwiftHFR dans Réglages › Notifications pour voir la pastille sur l’icône."
        )
    }
}
