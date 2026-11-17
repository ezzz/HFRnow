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
        crossings.sceneChanged(scene, active: true)
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
        crossings.sceneChanged(scene, active: true)
        spend(10)
        crossings.sceneChanged(scene, active: false)
        spend(180)
        #expect(ask(crossings) == nil)
        crossings.sceneChanged(scene, active: true)
        spend(5)
        crossings.sceneChanged(scene, active: false)
        crossings.sceneChanged(scene, active: true)
        spend(4.9)
        #expect(abs(crossings.foregroundTime - 19.9 * 60) < 0.001)
        #expect(ask(crossings) == nil)
        spend(0.1)
        #expect(ask(crossings) != nil)
    }

    @Test func theNextCrossingWaitsTwentyMinutesAgain() throws {
        let crossings = model([0])
        crossings.sceneChanged(scene, active: true)
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
        crossings.sceneChanged(scene, active: true)
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
        crossings.sceneChanged(scene, active: true)
        spend(20)
        _ = ask(crossings)
        #expect(haptics.played == [.impact(.light)])
        // Asking again while it crosses returns it, without a second haptic.
        _ = ask(crossings)
        #expect(haptics.played == [.impact(.light)])
    }

    @Test func noHapticWithTheHapticsSettingOff() {
        let crossings = model([0], store: InMemorySettingsStore(["haptics": .bool(false)]))
        crossings.sceneChanged(scene, active: true)
        spend(20)
        #expect(ask(crossings) != nil)
        #expect(haptics.played.isEmpty)
    }

    /// Reduce Motion or « Animations de saison » off: nothing crosses and nothing buzzes (THEMES.md §4 rules 1–2).
    @Test func nothingWithoutAnimations() {
        let crossings = model([0])
        crossings.sceneChanged(scene, active: true)
        spend(120)
        #expect(ask(crossings, animations: false) == nil)
        #expect(haptics.played.isEmpty)
    }

    @Test func nothingOutsideNoelSoftOrInTheBackground() {
        let crossings = model([0])
        crossings.sceneChanged(scene, active: true)
        spend(30)
        #expect(ask(crossings, crossingsOn: false) == nil)
        crossings.sceneChanged(scene, active: false)
        #expect(ask(crossings) == nil)
    }

    @Test func oneSceneAtATime() throws {
        let crossings = model([0])
        crossings.sceneChanged(scene, active: true)
        spend(30)
        let crossing = try #require(ask(crossings))
        let other = UUID()
        #expect(ask(crossings, scene: other) == nil)
        crossings.release(scene: other)
        #expect(crossings.current == crossing)
        crossings.release(scene: scene)
        #expect(crossings.current == nil)
    }

    /// An ordinary object cut by a resize just ends: it is not due again.
    @Test func anInterruptedObjectIsNotReplayed() throws {
        let crossings = model([0])
        crossings.sceneChanged(scene, active: true)
        spend(30)
        let crossing = try #require(ask(crossings))
        crossings.interrupt(crossing.id)
        #expect(crossings.current == nil)
        #expect(!crossings.arrivalPending)
        #expect(ask(crossings) == nil)
    }

    /// iPad, two windows: each reports its own phase. Foreground time runs while either is active; the other window leaving
    /// neither stops this scene's crossing nor the count; a scene that is not active gets nothing.
    @Test func anotherWindowsPhaseNeverStopsThisScenesCrossing() throws {
        let crossings = model([0])
        let other = UUID()
        crossings.sceneChanged(scene, active: true)
        spend(10)
        // A second window opening does not restart the count.
        crossings.sceneChanged(other, active: true)
        spend(10)
        crossings.sceneChanged(other, active: false)
        spend(5)
        #expect(abs(crossings.foregroundTime - 25 * 60) < 0.001)
        #expect(ask(crossings, scene: other) == nil)
        let crossing = try #require(ask(crossings))
        crossings.sceneChanged(other, active: true)
        crossings.sceneChanged(other, active: false)
        #expect(crossings.current == crossing)
    }

    /// A scene that went away no longer counts as active: it gets no crossing, and the count stops once it was the last one.
    @Test func aReleasedSceneNoLongerCounts() {
        let crossings = model([0])
        crossings.sceneChanged(scene, active: true)
        spend(30)
        crossings.release(scene: scene)
        let counted = crossings.foregroundTime
        spend(10)
        #expect(crossings.foregroundTime == counted)
        #expect(ask(crossings) == nil)
    }

    @Test func leavingTheForegroundStopsACrossing() {
        let crossings = model([0])
        crossings.sceneChanged(scene, active: true)
        spend(30)
        _ = ask(crossings)
        crossings.sceneChanged(scene, active: false)
        #expect(crossings.current == nil)
    }
}
