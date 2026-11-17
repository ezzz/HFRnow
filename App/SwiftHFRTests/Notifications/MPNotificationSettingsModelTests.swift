import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-140: Réglages › Notifications MP.
@MainActor
struct MPNotificationSettingsModelTests {
    final class Calls: @unchecked Sendable {
        var made = 0
    }

    @Test("Reads the stored values; a change is written under its key and a new interval reschedules the check")
    func readsAndWrites() {
        let store = InMemorySettingsStore()
        store.set(false, for: SettingKey.privateMessageBadge)
        let calls = Calls()
        let model = MPNotificationSettingsModel(
            store: store, ledger: NotificationLedgerStore(persistence: InMemorySmallStorePersistence()), reschedule: { calls.made += 1 }
        )
        #expect(!model.badgeEnabled)
        #expect(model.interval == .thirtyMinutes)
        model.badgeEnabled = true
        #expect(store.value(for: SettingKey.privateMessageBadge))
        #expect(calls.made == 0)
        model.interval = .never
        #expect(store.value(for: SettingKey.mpCheckInterval) == .never)
        #expect(calls.made == 1)
        model.interval = .never
        #expect(calls.made == 1)
    }

    @Test("The last check of the current account, as a time today and with its date before; nothing logged out or never checked")
    func lastCheck() async throws {
        let ledger = NotificationLedgerStore(persistence: InMemorySmallStorePersistence())
        let checked = Date(timeIntervalSinceReferenceDate: 800_000_000)
        _ = try await ledger.markChecked(account: "fakeuser", at: checked)
        let model = MPNotificationSettingsModel(store: InMemorySettingsStore(), ledger: ledger, reschedule: {})
        #expect(model.lastCheckText() == nil)
        await model.loadLastCheck(account: "other")
        #expect(model.lastCheckText() == nil)
        await model.loadLastCheck(account: "fakeuser")
        let time = checked.formatted(date: .omitted, time: .shortened)
        #expect(model.lastCheckText(now: checked) == "Dernière vérification : \(time)")
        let nextDay = checked.addingTimeInterval(86_400 * 2)
        #expect(model.lastCheckText(now: nextDay)?.hasSuffix("à \(time)") == true)
        await model.loadLastCheck(account: nil)
        #expect(model.lastCheckText() == nil)
    }

    @Test("Labels and footers of the interval choices")
    func labels() {
        #expect(MPCheckInterval.allCases.map(\.title) == ["15 min", "30 min", "1 h", "2 h", "4 h", "Jamais"])
        #expect(MPCheckInterval.thirtyMinutes.footer.hasPrefix("Au plus souvent toutes les 30 min. iOS décide du moment réel"))
        #expect(MPCheckInterval.oneHour.footer.hasPrefix("Au plus souvent toutes les heures."))
        #expect(MPCheckInterval.never.footer == "Aucune vérification en arrière-plan.")
    }
}
