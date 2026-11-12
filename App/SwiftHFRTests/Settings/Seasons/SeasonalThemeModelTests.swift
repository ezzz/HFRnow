import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The seasonal scheduler (LOT-166, THEMES.md §5) on an injected clock and calendar: what each first launch does.
@MainActor
struct SeasonalThemeModelTests {
    // MARK: First launch on each date of the acceptance list

    @Test func on30NovemberNothingHappensAndTheSectionIsHidden() {
        let clock = SeasonTestClock(30, 11, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive().isEmpty)
        #expect(model.activeTheme == nil)
        #expect(model.pendingAlert == nil)
        #expect(!model.isSelectable)
        #expect(!store.value(for: SettingKey.noelArrivalShown(year: 2026)))
        #expect(!store.value(for: SettingKey.noelArrivalShown(year: 2025)))
    }

    @Test(arguments: [1, 24])
    func from1To24DecemberNoelSoftIsSwitchedOnWithTheArrival(day: Int) {
        let clock = SeasonTestClock(day, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2026, switchedOn: true, sleigh: true)])
        #expect(model.activeTheme == .noelSoft)
        #expect(model.pendingAlert == .noelArrival(year: 2026))
        #expect(model.isSelectable)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == ThemeDefinition.legacyID)
        #expect(store.value(for: SettingKey.noelArrivalShown(year: 2026)))
        // A relaunch the next day finds it on.
        clock.move(to: day + 1, 12, 2026)
        #expect(clock.model(store: store).activeTheme == .noelSoft)
    }

    @Test(arguments: [25, 26])
    func on25And26DecemberTheArrivalPlaysButNothingIsSwitchedOn(day: Int) {
        let clock = SeasonTestClock(day, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2026, switchedOn: false, sleigh: true)])
        #expect(model.activeTheme == nil)
        #expect(model.pendingAlert == .noelArrival(year: 2026))
        #expect(model.isSelectable)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
    }

    @Test(arguments: [(27, 12, 2026), (31, 12, 2026), (1, 1, 2027), (2, 1, 2027)])
    func from27DecemberTo2JanuaryTheFirstLaunchPacks(day: Int, month: Int, year: Int) {
        let (clock, store) = Self.noelOn(since: 10)
        clock.move(to: day, month, year)
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.packed(year: 2026, animated: true)])
        #expect(model.activeTheme == nil)
        #expect(!model.isSelectable)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.noelPackingShown(year: 2026)))
    }

    @Test func on3JanuaryTheRestoreIsSilent() {
        let (clock, store) = Self.noelOn(since: 10)
        clock.move(to: 3, 1, 2027)
        let model = clock.model(store: store)
        // Already off from the first frame: no flash of the red accent before the activation.
        #expect(model.activeTheme == nil)
        #expect(model.sceneDidBecomeActive() == [.restoredSilently(year: 2026)])
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(!store.value(for: SettingKey.noelPackingShown(year: 2026)))
    }

    @Test func aPackingLaunchWithoutANoelThemeDoesNothing() {
        let clock = SeasonTestClock(27, 12, 2026)
        let store = InMemorySettingsStore()
        #expect(clock.model(store: store).sceneDidBecomeActive().isEmpty)
        #expect(!store.value(for: SettingKey.noelPackingShown(year: 2026)))
    }

    /// Last season's theme left on (the app not opened from December to the next one) is restored before this season starts.
    @Test func aThemeLeftOnFromLastSeasonIsRestoredBeforeTheNewArrival() {
        let (clock, store) = Self.noelOn(since: 10)
        clock.move(to: 5, 12, 2027)
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [
            .restoredSilently(year: 2026), .arrival(year: 2027, switchedOn: true, sleigh: true)
        ])
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(model.activeTheme == .noelSoft)
    }

    // MARK: Two launches, opt-out, manual pick

    @Test func twoLaunchesTheSameDayPlayTheArrivalOnce() {
        let clock = SeasonTestClock(3, 12, 2026, hour: 8)
        let store = InMemorySettingsStore()
        let first = clock.model(store: store)
        #expect(first.sceneDidBecomeActive().count == 1)
        first.answerArrival(disable: false)
        // Back from the background, then a cold launch, later that day.
        #expect(first.sceneDidBecomeActive().isEmpty)
        clock.move(to: 3, 12, 2026, hour: 22)
        let second = clock.model(store: store)
        #expect(second.sceneDidBecomeActive().isEmpty)
        #expect(second.pendingAlert == nil)
        #expect(second.activeTheme == .noelSoft)
    }

    @Test func twoPackingLaunchesPackOnce() {
        let (clock, store) = Self.noelOn(since: 10)
        clock.move(to: 27, 12, 2026)
        #expect(clock.model(store: store).sceneDidBecomeActive() == [.packed(year: 2026, animated: true)])
        clock.move(to: 28, 12, 2026)
        #expect(clock.model(store: store).sceneDidBecomeActive().isEmpty)
    }

    @Test func desactiverRestoresTheThemeAndOptsOutForTheYear() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        model.answerArrival(disable: true)
        #expect(model.activeTheme == nil)
        #expect(model.pendingAlert == nil)
        #expect(store.value(for: SettingKey.noelOptedOut(year: 2026)))
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        // Nothing comes back that season, and nothing is left to pack.
        clock.move(to: 2, 12, 2026)
        #expect(clock.model(store: store).sceneDidBecomeActive().isEmpty)
        clock.move(to: 27, 12, 2026)
        #expect(clock.model(store: store).sceneDidBecomeActive().isEmpty)
        // Next season starts afresh.
        clock.move(to: 1, 12, 2027)
        #expect(clock.model(store: store).sceneDidBecomeActive() == [.arrival(year: 2027, switchedOn: true, sleigh: true)])
    }

    @Test func okKeepsTheSeasonalTheme() {
        let clock = SeasonTestClock(1, 12, 2026)
        let model = clock.model(store: InMemorySettingsStore())
        model.sceneDidBecomeActive()
        model.answerArrival(disable: false)
        #expect(model.activeTheme == .noelSoft)
        #expect(model.pendingAlert == nil)
    }

    @Test func aThemePickedByHandIsPackedAtTheEndOfTheWindow() {
        let clock = SeasonTestClock(26, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        model.answerArrival(disable: false)
        model.select(.noelSoft)
        #expect(model.activeTheme == .noelSoft)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == ThemeDefinition.legacyID)
        clock.move(to: 27, 12, 2026)
        let later = clock.model(store: store)
        #expect(later.sceneDidBecomeActive() == [.packed(year: 2026, animated: true)])
        #expect(later.activeTheme == nil)
    }

    @Test func turningTheThemeOffByHandRestoresIt() {
        let (clock, store) = Self.noelOn(since: 2)
        let model = clock.model(store: store)
        model.select(nil)
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        clock.move(to: 27, 12, 2026)
        #expect(clock.model(store: store).sceneDidBecomeActive().isEmpty)
    }

    @Test(arguments: [(30, 11, 2026), (27, 12, 2026), (3, 1, 2027)])
    func aSeasonalThemeCannotBePickedOutsideItsWindow(day: Int, month: Int, year: Int) {
        let clock = SeasonTestClock(day, month, year)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.select(.noelSoft)
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2025)) == nil)
    }

    // MARK: Settings and motion

    @Test func withAutomaticThemesOffTheArrivalSwitchesNothingOn() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.isAutomatic = false
        #expect(!store.value(for: SettingKey.seasonalThemesAutomatic))
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2026, switchedOn: false, sleigh: true)])
        #expect(model.activeTheme == nil)
        #expect(model.pendingAlert == .noelArrival(year: 2026))
        // Still selectable by hand.
        model.select(.noelSoft)
        #expect(model.activeTheme == .noelSoft)
    }

    @Test func withReduceMotionTheArrivalIsTheAlertAloneAndPackingIsSkipped() {
        let clock = SeasonTestClock(1, 12, 2026)
        clock.reduceMotion = true
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2026, switchedOn: true, sleigh: false)])
        #expect(model.pendingAlert == .noelArrival(year: 2026))
        #expect(!model.snowFalls)
        clock.move(to: 27, 12, 2026)
        let later = clock.model(store: store)
        #expect(later.sceneDidBecomeActive() == [.packed(year: 2026, animated: false)])
        #expect(later.activeTheme == nil)
    }

    @Test func withSeasonalAnimationsOffNothingMovesAsWithReduceMotion() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.animationsEnabled = false
        #expect(!store.value(for: SettingKey.seasonalAnimations))
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2026, switchedOn: true, sleigh: false)])
        #expect(!model.snowFalls)
        model.animationsEnabled = true
        #expect(model.snowFalls)
        clock.move(to: 27, 12, 2026)
        let later = clock.model(store: store)
        later.animationsEnabled = false
        #expect(later.sceneDidBecomeActive() == [.packed(year: 2026, animated: false)])
    }

    @Test func snowFallsOnlyWithANoelThemeOn() {
        let clock = SeasonTestClock(25, 12, 2026)
        let model = clock.model(store: InMemorySettingsStore())
        model.sceneDidBecomeActive()
        #expect(!model.snowFalls)
        model.select(.noelSoft)
        #expect(model.snowFalls)
    }

    // MARK: Helpers

    /// A store where Noël soft was switched on at the arrival of `day`/12/2026 and the alert answered OK.
    static func noelOn(since day: Int) -> (SeasonTestClock, InMemorySettingsStore) {
        let clock = SeasonTestClock(day, 12, 2026)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        model.answerArrival(disable: false)
        return (clock, store)
    }
}
