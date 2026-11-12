import CoreGraphics
import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// When objects cross Noël soft (LOT-166, THEMES.md §4 rules 1, 4, 5): 20–90 min of foreground time apart, never sooner than
/// 20, only on a clear screen, with a light haptic through `HapticFeedback`, none without animations. Clock and random numbers
/// are the tests' own: no waiting.
@MainActor
struct NoelCrossingModelTests {
    static let clear = SeasonalThemeModel.ScreenState()
    static let area = CGSize(width: 402, height: 650)
    let clock = SeasonTestClock(5, 12, 2026)
    let haptics = HapticRecorder()
    let scene = UUID()

    private func model(_ random: [Double] = [0], store: InMemorySettingsStore = InMemorySettingsStore()) -> NoelCrossingModel {
        NoelCrossingModel(now: { clock.now }, random: ScriptedRandom(random), haptics: haptics.feedback(store: store))
    }

    private func ask(
        _ model: NoelCrossingModel, scene: UUID? = nil, screen: SeasonalThemeModel.ScreenState = clear,
        animations: Bool = true, crossingsOn: Bool = true
    ) -> NoelCrossingModel.Crossing? {
        model.crossing(
            for: scene ?? self.scene, on: .init(area: Self.area, windowHeight: 874), screen: screen, animationsAllowed: animations,
            crossingsOn: crossingsOn
        )
    }

    private func spend(_ minutes: Double) { clock.now += minutes * 60 }

    @Test func theGapIsDrawnBetweenTwentyAndNinetyMinutes() {
        #expect(model([0]).nextGap == 20 * 60)
        #expect(model([0.5]).nextGap == 55 * 60)
        #expect(model([0.999_999]).nextGap < 90 * 60)
        #expect(model([0.999_999]).nextGap > 89 * 60)
    }

    @Test func nothingCrossesBeforeTwentyMinutesOfForegroundTime() {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(19.9)
        #expect(ask(crossings) == nil)
        spend(0.2)
        let crossing = ask(crossings)
        #expect(crossing != nil)
        #expect(crossing?.isArrival == false)
        #expect(crossing?.size.height == NoelCrossingModel.itemHeight)
    }

    /// Hours in the background count for nothing: only active time does, across any number of returns.
    @Test func onlyForegroundTimeCounts() {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(10)
        crossings.foregroundChanged(active: false)
        spend(180)
        #expect(ask(crossings) == nil)
        crossings.foregroundChanged(active: true)
        spend(5)
        crossings.foregroundChanged(active: false)
        crossings.foregroundChanged(active: true)
        spend(4.9)
        #expect(abs(crossings.foregroundTime - 19.9 * 60) < 0.001)
        #expect(ask(crossings) == nil)
        spend(0.1)
        #expect(ask(crossings) != nil)
    }

    @Test func theNextCrossingWaitsTwentyMinutesAgain() throws {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(25)
        let first = try #require(ask(crossings))
        crossings.finish(first.id)
        #expect(crossings.current == nil)
        spend(19.9)
        #expect(ask(crossings) == nil)
        spend(0.1)
        #expect(ask(crossings) != nil)
    }

    @Test(arguments: [
        SeasonalThemeModel.ScreenState(isCovered: true),
        SeasonalThemeModel.ScreenState(isPresenting: true),
        SeasonalThemeModel.ScreenState(isKeyboardVisible: true)
    ])
    func nothingCrossesOverTheLockASheetAnAlertOrTheKeyboard(blocked: SeasonalThemeModel.ScreenState) throws {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(30)
        #expect(ask(crossings, screen: blocked) == nil)
        #expect(haptics.played.isEmpty)
        // Once clear it crosses; the same screen coming up stops it at once.
        let crossing = try #require(ask(crossings))
        crossings.screenChanged(for: scene, screen: Self.clear)
        #expect(crossings.current == crossing)
        crossings.screenChanged(for: scene, screen: blocked)
        #expect(crossings.current == nil)
    }

    @Test func aCrossingStartsWithOneLightHaptic() {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(20)
        _ = ask(crossings)
        #expect(haptics.played == [.impact(.light)])
        // Asking again while it crosses returns it, without a second haptic.
        _ = ask(crossings)
        #expect(haptics.played == [.impact(.light)])
    }

    @Test func noHapticWithTheHapticsSettingOff() {
        let crossings = model([0], store: InMemorySettingsStore(["haptics": .bool(false)]))
        crossings.foregroundChanged(active: true)
        spend(20)
        #expect(ask(crossings) != nil)
        #expect(haptics.played.isEmpty)
    }

    /// Reduce Motion or « Animations de saison » off: nothing crosses and nothing buzzes (THEMES.md §4 rules 1–2).
    @Test func nothingWithoutAnimations() {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(120)
        #expect(ask(crossings, animations: false) == nil)
        #expect(haptics.played.isEmpty)
    }

    @Test func nothingOutsideNoelSoftOrInTheBackground() {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(30)
        #expect(ask(crossings, crossingsOn: false) == nil)
        crossings.foregroundChanged(active: false)
        #expect(ask(crossings) == nil)
    }

    @Test func oneSceneAtATime() throws {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(30)
        let crossing = try #require(ask(crossings))
        let other = UUID()
        #expect(ask(crossings, scene: other) == nil)
        crossings.release(scene: other)
        #expect(crossings.current == crossing)
        crossings.release(scene: scene)
        #expect(crossings.current == nil)
    }

    @Test func leavingTheForegroundStopsACrossing() {
        let crossings = model([0])
        crossings.foregroundChanged(active: true)
        spend(30)
        _ = ask(crossings)
        crossings.foregroundChanged(active: false)
        #expect(crossings.current == nil)
    }
}
