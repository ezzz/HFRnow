import CoreGraphics
import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The Samain windows and what the scheduler does with them (LOT-191, THEMES.md §5): Spooktober soft is selectable and switched
/// on from 01/10 to 31/10, packed at the first launch 01/11–07/11, restored silently after; the clock is the tests' own.
@MainActor
struct SamainSeasonTests {
    static let clear = SeasonalThemeModel.ScreenState()

    // MARK: Switching on

    @Test func theFirstLaunchOfOctoberSwitchesSpooktoberSoftOnAndAsksForTheArrival() {
        let clock = SeasonTestClock(1, 10, 2027)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2027, switchedOn: true, sleigh: true)])
        #expect(model.activeTheme == .spooktoberSoft)
        #expect(model.selectableFamily == .samain)
        #expect(store.value(for: SettingKey.samainThemeID(year: 2027)) == "spooktober-soft")
        #expect(store.value(for: SettingKey.samainPreviousThemeID(year: 2027)) == ThemeDefinition.legacyID)
        #expect(store.value(for: SettingKey.samainActiveYear) == 2027)
        #expect(model.pendingAlert == .samainArrival(year: 2027))
        #expect(model.crossings.arrivalPending)
        // Noël's keys are untouched.
        #expect(store.value(for: SettingKey.noelActiveYear) == nil)
        #expect(!model.snowFalls)
    }

    /// The title names the situation and is true when nothing is switched on, as Noël's since #1174.
    @Test func theAlertSaysTheOperatorsSentenceWhetherOrNotAThemeWasSwitchedOn() {
        let clock = SeasonTestClock(12, 10, 2027)
        let on = clock.model(store: InMemorySettingsStore())
        on.sceneDidBecomeActive()
        let alert = on.pendingAlert
        #expect(alert.map(on.title(for:)) == "Spooktober est là !")
        #expect(alert?.message == "Thème disponible dans les réglages")
        let off = InMemorySettingsStore()
        off.set(false, for: SettingKey.seasonalThemesAutomatic)
        let manual = clock.model(store: off)
        manual.sceneDidBecomeActive()
        #expect(manual.activeTheme == nil)
        #expect(manual.pendingAlert.map(manual.title(for:)) == "Spooktober est là !")
    }

    @Test func theDayBeforeNothingHappensAndNothingCanBePicked() {
        let clock = SeasonTestClock(30, 9, 2027)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive().isEmpty)
        #expect(model.activeTheme == nil && model.pendingAlert == nil && !model.isSelectable)
        model.select(.spooktoberSoft)
        model.select(.spooktoberAbuse)
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.samainThemeID(year: 2026)) == nil)
    }

    @Test func theLastDayIsStillInsideTheWindow() {
        let clock = SeasonTestClock(31, 10, 2027, hour: 23, minute: 30)
        let model = clock.model(store: InMemorySettingsStore())
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2027, switchedOn: true, sleigh: true)])
        #expect(model.activeTheme == .spooktoberSoft)
    }

    @Test func automaticThemesOffShowsTheArrivalAloneAndTheThemeCanStillBePicked() {
        let clock = SeasonTestClock(5, 10, 2027)
        let store = InMemorySettingsStore()
        store.set(false, for: SettingKey.seasonalThemesAutomatic)
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2027, switchedOn: false, sleigh: true)])
        #expect(model.activeTheme == nil)
        #expect(model.pendingAlert == .samainArrival(year: 2027))
        model.select(.spooktoberSoft)
        #expect(model.activeTheme == .spooktoberSoft)
    }

    // MARK: Answers and picks

    @Test func desactiverRestoresTheThemeAndOptsOutForTheYearOnly() {
        let clock = SeasonTestClock(1, 10, 2027)
        let store = InMemorySettingsStore()
        store.set("test-theme", for: SettingKey.themeID)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        model.answerArrival(disable: true)
        #expect(model.activeTheme == nil && model.pendingAlert == nil)
        #expect(store.value(for: SettingKey.samainOptedOut(year: 2027)))
        #expect(store.value(for: SettingKey.samainPreviousThemeID(year: 2027)) == nil)
        // A later launch of the same season does not switch it on again, and next year it does.
        clock.move(to: 20, 10, 2027)
        let later = clock.model(store: store)
        #expect(later.sceneDidBecomeActive().isEmpty)
        #expect(later.activeTheme == nil)
        clock.move(to: 2, 10, 2028)
        let next = clock.model(store: store)
        #expect(next.sceneDidBecomeActive() == [.arrival(year: 2028, switchedOn: true, sleigh: true)])
        #expect(store.value(for: SettingKey.themeID) == "test-theme")
    }

    @Test func okKeepsTheTheme() {
        let clock = SeasonTestClock(1, 10, 2027)
        let model = clock.model(store: InMemorySettingsStore())
        model.sceneDidBecomeActive()
        model.answerArrival(disable: false)
        #expect(model.activeTheme == .spooktoberSoft && model.pendingAlert == nil)
    }

    @Test func aPickInsideTheWindowIsStoredAndMovingBetweenTheThemesKeepsTheSavedOne() {
        let clock = SeasonTestClock(10, 10, 2027)
        let store = InMemorySettingsStore()
        store.set("test-theme", for: SettingKey.themeID)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        store.set("another-theme", for: SettingKey.themeID)
        model.select(.spooktoberAbuse)
        #expect(model.activeTheme == .spooktoberAbuse)
        #expect(store.value(for: SettingKey.samainThemeID(year: 2027)) == "spooktober-abuse")
        model.select(.spooktoberSoft)
        #expect(store.value(for: SettingKey.samainPreviousThemeID(year: 2027)) == "test-theme")
        model.select(nil)
        #expect(model.activeTheme == nil)
        #expect(store.value(for: SettingKey.samainThemeID(year: 2027)) == nil)
        // A relaunch finds the pick.
        model.select(.spooktoberAbuse)
        #expect(clock.model(store: store).activeTheme == .spooktoberAbuse)
    }

    /// A missing or unknown stored id, or one of another family, reads as Spooktober soft.
    @Test(arguments: [nil, "spooktober-futur", "noel-abuse"])
    func aMissingOrForeignThemeIDReadsAsSpooktoberSoft(stored: String?) {
        let clock = SeasonTestClock(10, 10, 2027)
        let store = InMemorySettingsStore()
        store.set(ThemeDefinition.legacyID, for: SettingKey.samainPreviousThemeID(year: 2027))
        store.set(2027, for: SettingKey.samainActiveYear)
        store.set(stored, for: SettingKey.samainThemeID(year: 2027))
        #expect(clock.model(store: store).activeTheme == .spooktoberSoft)
    }

    // MARK: Packing and restoring

    /// The first launch 01/11 and the seventh: the witch sweeps it away; the store is clean at once.
    @Test(arguments: [1, 7])
    func packingTakesTheThemeDownFromTheFirstToTheSeventhOfNovember(day: Int) throws {
        let clock = SeasonTestClock(15, 10, 2027)
        let store = InMemorySettingsStore()
        let first = clock.model(store: store)
        first.sceneDidBecomeActive()
        first.answerArrival(disable: false)
        clock.move(to: day, 11, 2027)
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.packed(year: 2027, animated: true)])
        #expect(store.value(for: SettingKey.samainThemeID(year: 2027)) == nil)
        #expect(store.value(for: SettingKey.samainPreviousThemeID(year: 2027)) == nil)
        #expect(store.value(for: SettingKey.samainActiveYear) == nil)
        #expect(model.activeTheme == nil)
        // Drawn until the witch is done.
        #expect(try #require(model.packing.current).theme == .spooktoberSoft)
        #expect(model.drawnTheme == .spooktoberSoft)
        model.packing.finish()
        #expect(model.drawnTheme == nil)
        // A second activation the same day is silent: the sweep plays once.
        #expect(model.sceneDidBecomeActive().isEmpty)
    }

    @Test func fromTheEighthOfNovemberTheRestoreIsSilent() {
        let clock = SeasonTestClock(15, 10, 2027)
        let store = InMemorySettingsStore()
        clock.model(store: store).sceneDidBecomeActive()
        clock.move(to: 8, 11, 2027)
        let model = clock.model(store: store)
        #expect(model.activeTheme == nil)
        #expect(model.sceneDidBecomeActive() == [.restoredSilently(year: 2027)])
        #expect(model.packing.current == nil && model.drawnTheme == nil)
        #expect(store.value(for: SettingKey.samainThemeID(year: 2027)) == nil)
    }

    @Test func aPickedAbuseIsPackedLikeTheSoftOne() throws {
        let clock = SeasonTestClock(10, 10, 2027)
        let store = InMemorySettingsStore()
        clock.model(store: store).select(.spooktoberAbuse)
        clock.move(to: 2, 11, 2027)
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.packed(year: 2027, animated: true)])
        #expect(try #require(model.packing.current).theme == .spooktoberAbuse)
    }

    /// Reduce Motion, or « Animations de saison » off: the arrival is the alert alone and the packing restores at once.
    @Test(arguments: [true, false])
    func withoutAnimationsTheArrivalIsTheAlertAloneAndNothingIsPacked(reduceMotion: Bool) {
        let clock = SeasonTestClock(1, 10, 2027)
        let store = InMemorySettingsStore()
        if reduceMotion { clock.reduceMotion = true } else { store.set(false, for: SettingKey.seasonalAnimations) }
        let model = clock.model(store: store)
        #expect(model.sceneDidBecomeActive() == [.arrival(year: 2027, switchedOn: true, sleigh: false)])
        #expect(!model.crossings.arrivalPending)
        #expect(model.pendingAlert == .samainArrival(year: 2027))
        clock.move(to: 3, 11, 2027)
        let later = clock.model(store: store)
        #expect(later.sceneDidBecomeActive() == [.packed(year: 2027, animated: false)])
        #expect(later.packing.current == nil && later.drawnTheme == nil)
    }

    // MARK: Two families

    /// A Samain theme left on is restored silently at Noël's first launch, which then plays its own arrival; the two families'
    /// keys never mix.
    @Test func aLeftOnSamainThemeIsRestoredAtNoelAndNoelIsUnaffected() {
        let clock = SeasonTestClock(10, 10, 2027)
        let store = InMemorySettingsStore()
        clock.model(store: store).sceneDidBecomeActive()
        clock.move(to: 5, 12, 2027)
        let model = clock.model(store: store)
        #expect(model.activeTheme == nil)
        let events = model.sceneDidBecomeActive()
        #expect(events.contains(.restoredSilently(year: 2027)))
        #expect(events.contains(.arrival(year: 2027, switchedOn: true, sleigh: true)))
        #expect(model.activeTheme == .noelSoft)
        #expect(model.selectableFamily == .noel)
        #expect(model.pendingAlert == .noelArrival(year: 2027))
        #expect(store.value(for: SettingKey.samainPreviousThemeID(year: 2027)) == nil)
        #expect(store.value(for: SettingKey.noelThemeID(year: 2027)) == "noel-soft")
    }

    /// Noël's packing days never drop a Samain packing, and the reverse: each family's waiting elves are its own.
    @Test func aWaitingPackingIsOnlyDroppedByItsOwnFamily() {
        let clock = SeasonTestClock(15, 10, 2027)
        let store = InMemorySettingsStore()
        clock.model(store: store).sceneDidBecomeActive()
        clock.move(to: 2, 11, 2027)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        #expect(model.packing.current?.theme == .spooktoberSoft)
        // The next day is still a packing day for Samain: Noël's outside phase must not drop the waiting witch.
        clock.move(to: 3, 11, 2027)
        model.sceneDidBecomeActive()
        #expect(model.packing.current?.theme == .spooktoberSoft)
        // Once the packing days are over her own family drops her.
        clock.move(to: 8, 11, 2027)
        model.sceneDidBecomeActive()
        #expect(model.packing.current == nil)
    }

    @Test func theSectionOfThePickerShowsTheFamilyOfTheDate() {
        func family(_ day: Int, _ month: Int) -> SeasonFamily? {
            SeasonTestClock(day, month, 2027).model(store: InMemorySettingsStore()).selectableFamily
        }
        #expect(family(10, 10) == .samain)
        #expect(family(10, 12) == .noel)
        #expect(family(15, 8) == nil)
        #expect(family(3, 11) == nil)
    }
}
