import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// The arrival alert across launches, screens and scenes (LOT-166, THEMES.md §4 rule 5, §5): it waits for an answer, for a clear
/// screen and for one scene.
@MainActor
struct SeasonalArrivalTests {
    static let clear = SeasonalThemeModel.ScreenState()

    @Test func anArrivalKilledBeforeItWasSeenIsShownAtTheNextLaunch() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        let first = clock.model(store: store)
        first.sceneDidBecomeActive()
        #expect(first.pendingAlert == .noelArrival(year: 2026))
        // Killed before any answer; relaunched later that day, then the next day.
        clock.move(to: 1, 12, 2026, hour: 18)
        let second = clock.model(store: store)
        #expect(second.sceneDidBecomeActive().isEmpty)
        #expect(second.pendingAlert == .noelArrival(year: 2026))
        #expect(second.activeTheme == .noelSoft)
        second.answerArrival(disable: true)
        #expect(second.activeTheme == nil)
        clock.move(to: 2, 12, 2026)
        let third = clock.model(store: store)
        #expect(third.pendingAlert == nil)
        #expect(third.sceneDidBecomeActive().isEmpty)
        #expect(third.pendingAlert == nil)
    }

    @Test func anArrivalNeverAnsweredIsDroppedWhenTheWindowCloses() {
        let clock = SeasonTestClock(26, 12, 2026)
        let store = InMemorySettingsStore()
        clock.model(store: store).sceneDidBecomeActive()
        clock.move(to: 27, 12, 2026)
        let later = clock.model(store: store)
        #expect(later.pendingAlert == nil)
        later.sceneDidBecomeActive()
        #expect(!store.value(for: SettingKey.noelArrivalPending(year: 2026)))
    }

    @Test(arguments: [
        SeasonalThemeModel.ScreenState(isCovered: true),
        SeasonalThemeModel.ScreenState(isPresenting: true),
        SeasonalThemeModel.ScreenState(isKeyboardVisible: true)
    ])
    func theAlertWaitsWhileTheLockASheetOrTheKeyboardIsUp(blocked: SeasonalThemeModel.ScreenState) {
        let clock = SeasonTestClock(1, 12, 2026)
        let model = clock.model(store: InMemorySettingsStore())
        model.sceneDidBecomeActive()
        let scene = UUID()
        #expect(model.alert(for: scene, screen: blocked) == nil)
        #expect(model.pendingAlert == .noelArrival(year: 2026))
        #expect(model.alert(for: scene, screen: Self.clear) == .noelArrival(year: 2026))
    }

    /// iPad with two windows: one scene presents the alert; the other gets it only if the first goes away unanswered.
    @Test func onlyOneSceneShowsTheAlert() {
        let clock = SeasonTestClock(1, 12, 2026)
        let model = clock.model(store: InMemorySettingsStore())
        model.sceneDidBecomeActive()
        let left = UUID(), right = UUID()
        #expect(model.alert(for: left, screen: Self.clear) == .noelArrival(year: 2026))
        #expect(model.alert(for: right, screen: Self.clear) == nil)
        // The scene showing it keeps it, even under its own alert.
        #expect(model.alert(for: left, screen: SeasonalThemeModel.ScreenState(isPresenting: true)) == .noelArrival(year: 2026))
        model.releaseAlert(for: left)
        #expect(model.alert(for: right, screen: Self.clear) == .noelArrival(year: 2026))
        model.answerArrival(disable: false)
        #expect(model.alert(for: left, screen: Self.clear) == nil)
        #expect(model.alert(for: right, screen: Self.clear) == nil)
    }
}
