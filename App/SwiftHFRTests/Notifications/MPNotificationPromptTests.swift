import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// #1172 (HIG › Privacy, « Requesting permission »): the notification prompt comes when an account is current, not at
/// launch: logged out it never shows; with an account it shows once, only while iOS never asked and a switch needs it.
@MainActor
struct MPNotificationPromptTests {
    @Test func loggedOutNothingIsAsked() async {
        let permission = FakeNotificationPermission(.notDetermined)
        await MPNotificationPrompt(store: InMemorySettingsStore(), permission: permission).accountBecameCurrent(nil)
        #expect(await permission.requests == 0)
    }

    @Test func anAccountBecomingCurrentAsksOnceWhileIOSNeverAsked() async {
        let permission = FakeNotificationPermission(.notDetermined)
        let prompt = MPNotificationPrompt(store: InMemorySettingsStore(), permission: permission)
        await prompt.accountBecameCurrent("Alice")
        #expect(await permission.requests == 1)
        // iOS answered: a later account (a switch, a new login) asks nothing again.
        await prompt.accountBecameCurrent("Bob")
        #expect(await permission.requests == 1)
    }

    @Test(arguments: [NotificationPermission.allowed, .denied, .badgesOff])
    func anAnswerGivenBeforeIsNotAskedAgain(_ answered: NotificationPermission) async {
        let permission = FakeNotificationPermission(answered)
        await MPNotificationPrompt(store: InMemorySettingsStore(), permission: permission).accountBecameCurrent("Alice")
        #expect(await permission.requests == 0)
    }

    /// Both switches off: nothing the app would show needs the permission, so it waits for one turned on (Réglages asks then).
    @Test func withNothingToShowNothingIsAsked() async {
        let store = InMemorySettingsStore()
        store.set(false, for: SettingKey.mpNotificationsEnabled)
        store.set(false, for: SettingKey.privateMessageBadge)
        let permission = FakeNotificationPermission(.notDetermined)
        await MPNotificationPrompt(store: store, permission: permission).accountBecameCurrent("Alice")
        #expect(await permission.requests == 0)
    }

    @Test(arguments: [(true, false), (false, true), (true, true)])
    func eitherSwitchIsEnoughToAsk(notifications: Bool, badge: Bool) {
        #expect(MPNotificationPrompt.asks(account: "Alice", notifications: notifications, badge: badge, authorization: .notDetermined))
        #expect(!MPNotificationPrompt.asks(account: nil, notifications: notifications, badge: badge, authorization: .notDetermined))
    }

    /// The launch only registers the category: the one call that shows the system prompt is `LiveNotificationPermission`'s,
    /// reached through this rule or Réglages (red while the launch asked by itself).
    @Test func onlyThePermissionSeamAsksIOS() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "SwiftHFR")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var callers: [String] = []
        for case let file as URL in files where file.pathExtension == "swift" {
            let text = try String(contentsOf: file, encoding: .utf8)
            let calls = text.split(separator: "\n").filter { line in
                let code = line.trimmingCharacters(in: .whitespaces)
                return !code.hasPrefix("//") && code.contains(".requestAuthorization(options:")
            }
            if !calls.isEmpty { callers.append(file.lastPathComponent) }
        }
        #expect(callers == ["NotificationPermission.swift"])
    }
}
