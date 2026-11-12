import CoreGraphics
import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// The arrival sleigh (LOT-166, THEMES.md §5): on the first launch of the window it crosses, a quarter of the window high (at
/// most 240 pt), in at most 3 s, facing its travel, and only then does the « Oh Oh Oh ! » alert come.
@MainActor
struct NoelSleighArrivalTests {
    static let clear = SeasonalThemeModel.ScreenState()
    let haptics = HapticRecorder()
    let scene = UUID()

    private func launch(_ clock: SeasonTestClock, store: any SettingsStore = InMemorySettingsStore()) -> SeasonalThemeModel {
        let crossings = NoelCrossingModel(now: { clock.now }, random: SeededRandom(3), haptics: haptics.feedback())
        let model = SeasonalThemeModel(
            store: store, now: { clock.now }, timeZone: { clock.timeZone }, reduceMotion: { clock.reduceMotion },
            crossings: crossings
        )
        model.sceneDidBecomeActive()
        crossings.foregroundChanged(active: true)
        return model
    }

    private func sleigh(_ model: SeasonalThemeModel, windowHeight: CGFloat = 874) -> NoelCrossingModel.Crossing? {
        model.crossings.crossing(
            for: scene, area: CGSize(width: 402, height: 650), windowHeight: windowHeight, screen: Self.clear,
            animationsAllowed: model.animationsAllowed, crossingsOn: model.activeTheme == .noelSoft
        )
    }

    @Test(arguments: [(1, 12), (24, 12), (25, 12), (26, 12)])
    func theSleighCrossesBeforeTheAlert(day: Int, month: Int) throws {
        let model = launch(SeasonTestClock(day, month, 2026))
        #expect(model.crossings.arrivalPending)
        // The alert waits for the sleigh.
        #expect(model.alert(for: scene, screen: Self.clear) == nil)
        let crossing = try #require(sleigh(model))
        #expect(crossing.isArrival && crossing.item == .sleigh)
        #expect(crossing.path.duration <= 3)
        #expect(crossing.path.entry == .leading || crossing.path.entry == .trailing)
        #expect(haptics.played == [.impact(.light)])
        #expect(model.alert(for: scene, screen: Self.clear) == nil)
        model.crossings.finish(crossing.id)
        #expect(model.alert(for: scene, screen: Self.clear) == .noelArrival(year: 2026))
    }

    @Test(arguments: [(874.0, 218.5), (402.0, 100.5), (1366.0, 240.0)])
    func theSleighIsAQuarterOfTheWindowAtMost240Points(window: Double, height: Double) throws {
        let model = launch(SeasonTestClock(1, 12, 2026))
        let crossing = try #require(sleigh(model, windowHeight: window))
        #expect(abs(Double(crossing.size.height) - height) < 1e-9)
        #expect(abs(crossing.size.width / crossing.size.height - NoelCrossingItem.sleigh.aspectRatio) < 1e-9)
    }

    /// Reduce Motion or « Animations de saison » off: the arrival is the alert alone, without a haptic (THEMES.md §4 rules 1–2).
    @Test func withoutAnimationsTheAlertComesAlone() {
        let clock = SeasonTestClock(1, 12, 2026)
        clock.reduceMotion = true
        let model = launch(clock)
        #expect(!model.crossings.arrivalPending)
        #expect(sleigh(model) == nil)
        #expect(model.alert(for: scene, screen: Self.clear) == .noelArrival(year: 2026))
        #expect(haptics.played.isEmpty)
    }

    @Test func animationsTurnedOffBeforeTheSleighDropIt() {
        let model = launch(SeasonTestClock(1, 12, 2026))
        model.animationsEnabled = false
        #expect(sleigh(model) == nil)
        #expect(!model.crossings.arrivalPending)
        #expect(model.alert(for: scene, screen: Self.clear) == .noelArrival(year: 2026))
    }

    @Test func aTapClosesTheSleighAndTheAlertFollows() throws {
        let model = launch(SeasonTestClock(1, 12, 2026))
        let crossing = try #require(sleigh(model))
        model.crossings.finish(crossing.id)
        #expect(model.crossings.current == nil)
        #expect(sleigh(model) == nil)
        #expect(model.alert(for: scene, screen: Self.clear) == .noelArrival(year: 2026))
    }

    @Test func theSleighWaitsForAClearScreen() {
        let model = launch(SeasonTestClock(1, 12, 2026))
        let keyboard = SeasonalThemeModel.ScreenState(isKeyboardVisible: true)
        let blocked = model.crossings.crossing(
            for: scene, area: CGSize(width: 402, height: 650), windowHeight: 874, screen: keyboard, animationsAllowed: true,
            crossingsOn: true
        )
        #expect(blocked == nil)
        #expect(model.crossings.arrivalPending)
        #expect(sleigh(model) != nil)
    }

    /// A layer asks before it is laid out: the sleigh stays due until it can cross.
    @Test func anEmptyAreaKeepsTheSleighDue() {
        let model = launch(SeasonTestClock(1, 12, 2026))
        let early = model.crossings.crossing(
            for: scene, area: .zero, windowHeight: 874, screen: Self.clear, animationsAllowed: true, crossingsOn: true
        )
        #expect(early == nil)
        #expect(model.crossings.arrivalPending)
        #expect(model.alert(for: scene, screen: Self.clear) == nil)
        #expect(sleigh(model)?.isArrival == true)
    }

    @Test func noSleighOnALaterLaunchOfTheSeason() {
        let clock = SeasonTestClock(1, 12, 2026)
        let store = InMemorySettingsStore()
        _ = launch(clock, store: store)
        clock.move(to: 2, 12, 2026)
        let later = launch(clock, store: store)
        #expect(!later.crossings.arrivalPending)
    }
}
