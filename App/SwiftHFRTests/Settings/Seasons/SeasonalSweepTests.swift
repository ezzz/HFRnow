import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// A Noël theme left on is found however long ago it was switched on, and season years are Gregorian whatever the device's
/// calendar (LOT-166).
@MainActor
struct SeasonalSweepTests {
    @Test func aThemeLeftOnTwoSeasonsAgoIsRestoredBeforeTheNewArrival() {
        let (clock, store) = SeasonalThemeModelTests.noelOn(since: 10)
        clock.move(to: 5, 12, 2028)
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [
            .restoredSilently(year: 2026), .arrival(year: 2028, switchedOn: true, sleigh: true)
        ])
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.noelActiveYear) == 2028)
        #expect(model.activeTheme == .noelSoft)
    }

    @Test func aThemeLeftOnSinceDecember2026IsRestoredInFebruary2029() {
        let (clock, store) = SeasonalThemeModelTests.noelOn(since: 10)
        clock.move(to: 5, 2, 2029)
        let model = clock.model(store: store)
        #expect(model.activeTheme == nil)
        #expect(model.sceneDidBecomeActive() == [.restoredSilently(year: 2026)])
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.noelActiveYear) == nil)
        #expect(model.sceneDidBecomeActive().isEmpty)
    }

    @Test func packingClearsThePointer() {
        let (clock, store) = SeasonalThemeModelTests.noelOn(since: 10)
        #expect(store.value(for: SettingKey.noelActiveYear) == 2026)
        clock.move(to: 27, 12, 2026)
        clock.model(store: store).sceneDidBecomeActive()
        #expect(store.value(for: SettingKey.noelActiveYear) == nil)
    }

    /// A Buddhist (2569) or Japanese (Reiwa 8) device still names the 2026 season after 2026, in its own time zone.
    @Test(arguments: [Calendar.Identifier.buddhist, .japanese])
    func seasonYearsAreGregorianWhateverTheDeviceCalendar(identifier: Calendar.Identifier) {
        var device = Calendar(identifier: identifier)
        device.timeZone = SeasonTestClock.calendar.timeZone
        let date = SeasonTestClock.date(1, 12, 2026, hour: 0, minute: 30)
        #expect(NoelCalendar.seasonYear(of: date, in: device) == 2026)
        #expect(NoelCalendar.phase(of: date, in: device) == .switchOn)
        let store = InMemorySettingsStore()
        let model = SeasonalThemeModel(store: store, now: { date }, calendar: device, reduceMotion: { false })
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2026, switchedOn: true, sleigh: true)])
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == SeasonalThemeModel.legacyThemeID)
    }
}
