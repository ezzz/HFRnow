import CoreGraphics
import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// The packing elves (LOT-166 PR 3, THEMES.md §5): on the first launch 27/12–02/01 with a Noël theme on, the store is restored
/// at once while the theme stays drawn until the elves have played (≤ 5 s, one scene, a clear screen); then the user's theme.
@MainActor
struct NoelPackingTests {
    static let clear = SeasonalThemeModel.ScreenState()
    let scene = UUID()

    /// The first launch of 27/12 after Noël soft was on since 10/12, in the foreground.
    private func packingLaunch(
        reduceMotion: Bool = false, store: InMemorySettingsStore = InMemorySettingsStore()
    ) -> (SeasonTestClock, SeasonalThemeModel) {
        let clock = SeasonTestClock(10, 12, 2026)
        let first = clock.model(store: store)
        first.sceneDidBecomeActive()
        first.answerArrival(disable: false)
        clock.move(to: 27, 12, 2026)
        clock.reduceMotion = reduceMotion
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        model.packing.foregroundChanged(active: true)
        return (clock, model)
    }

    @Test func theStoreIsRestoredAtOnceWhileTheThemeStaysDrawnUntilTheElvesHavePlayed() throws {
        let store = InMemorySettingsStore()
        let (_, model) = packingLaunch(store: store)
        #expect(store.value(for: SettingKey.noelPreviousThemeID(year: 2026)) == nil)
        #expect(store.value(for: SettingKey.noelActiveYear) == nil)
        #expect(model.activeTheme == nil)
        #expect(model.drawnTheme == .noelSoft)
        #expect(model.snowFalls)
        #expect(!model.packing.isPlaying)
        let packing = try #require(model.packing.start(for: scene, screen: Self.clear, animationsAllowed: model.animationsAllowed))
        #expect(packing.year == 2026 && packing.theme == .noelSoft && packing.scene == scene)
        #expect(model.packing.isPlaying)
        #expect(model.drawnTheme == .noelSoft)
        model.packing.finish()
        #expect(model.drawnTheme == nil)
        #expect(!model.snowFalls)
    }

    /// An overlay lasts at most 5 s (THEMES.md §4 rule 3).
    @Test func theElvesPlayAtMostFiveSeconds() {
        #expect(NoelPackingModel.duration <= 5)
    }

    /// Reduce Motion: packing restores without the elves, and nothing stays drawn (THEMES.md §4 rule 1).
    @Test func withoutAnimationsTheThemeGoesAtOnce() {
        let (_, model) = packingLaunch(reduceMotion: true)
        #expect(model.packing.current == nil)
        #expect(model.drawnTheme == nil)
        #expect(model.packing.start(for: scene, screen: Self.clear, animationsAllowed: model.animationsAllowed) == nil)
    }

    @Test func animationsTurnedOffBeforeTheElvesDropThem() {
        let (_, model) = packingLaunch()
        model.animationsEnabled = false
        #expect(model.packing.start(for: scene, screen: Self.clear, animationsAllowed: model.animationsAllowed) == nil)
        #expect(model.packing.current == nil)
        #expect(model.drawnTheme == nil)
    }

    /// Never over input (THEMES.md §4 rule 5): the elves wait for the lock, a sheet and the keyboard to go.
    @Test(arguments: [
        SeasonalThemeModel.ScreenState(isCovered: true),
        SeasonalThemeModel.ScreenState(isPresenting: true),
        SeasonalThemeModel.ScreenState(isKeyboardVisible: true)
    ])
    func theElvesWaitForAClearScreen(screen: SeasonalThemeModel.ScreenState) {
        let (_, model) = packingLaunch()
        #expect(model.packing.start(for: scene, screen: screen, animationsAllowed: true) == nil)
        #expect(model.drawnTheme == .noelSoft)
        #expect(model.packing.start(for: scene, screen: Self.clear, animationsAllowed: true) != nil)
    }

    @Test func theElvesWaitForTheForegroundAndAWaitingPackingSurvivesTheBackground() {
        let (_, model) = packingLaunch()
        model.packing.foregroundChanged(active: false)
        #expect(model.packing.start(for: scene, screen: Self.clear, animationsAllowed: true) == nil)
        #expect(model.drawnTheme == .noelSoft)
        model.packing.foregroundChanged(active: true)
        #expect(model.packing.start(for: scene, screen: Self.clear, animationsAllowed: true) != nil)
        // Leaving while they play ends them: the decorations go with them.
        model.packing.foregroundChanged(active: false)
        #expect(model.packing.current == nil)
        #expect(model.drawnTheme == nil)
    }

    @Test func aSheetOrTheKeyboardStopsTheElves() {
        let (_, model) = packingLaunch()
        _ = model.packing.start(for: scene, screen: Self.clear, animationsAllowed: true)
        model.packing.screenChanged(for: UUID(), screen: .init(isKeyboardVisible: true))
        #expect(model.packing.isPlaying)
        model.packing.screenChanged(for: scene, screen: .init(isKeyboardVisible: true))
        #expect(model.packing.current == nil)
        #expect(model.drawnTheme == nil)
    }

    /// iPad with two windows: one scene plays the elves; the other draws the decorations until they are done.
    @Test func oneSceneOnlyPlaysTheElves() {
        let (_, model) = packingLaunch()
        let other = UUID()
        #expect(model.packing.start(for: scene, screen: Self.clear, animationsAllowed: true) != nil)
        #expect(model.packing.start(for: other, screen: Self.clear, animationsAllowed: true) == nil)
        #expect(model.packing.start(for: scene, screen: Self.clear, animationsAllowed: true)?.scene == scene)
        model.packing.release(scene: other)
        #expect(model.packing.isPlaying)
        model.packing.release(scene: scene)
        #expect(model.packing.current == nil)
    }

    /// Killed while the elves wait or play: the next launch shows the user's theme, without elves.
    @Test func aKillMeanwhileLosesNothing() {
        let store = InMemorySettingsStore()
        let (clock, _) = packingLaunch(store: store)
        let next = clock.model(store: store)
        #expect(next.sceneDidBecomeActive().isEmpty)
        #expect(next.drawnTheme == nil)
        #expect(next.packing.current == nil)
    }

    /// A second activation the same day does not queue the elves again.
    @Test func theElvesPlayOncePerSeason() {
        let (_, model) = packingLaunch()
        model.packing.finish()
        #expect(model.sceneDidBecomeActive().isEmpty)
        #expect(model.packing.current == nil)
        #expect(model.drawnTheme == nil)
    }

    /// Elves still waiting when the packing days end (an app left open, the screen never clear): the theme goes at the next
    /// activation; elves already playing are left to finish.
    @Test func waitingElvesAreDroppedAfterThePackingDays() {
        let (clock, model) = packingLaunch()
        clock.move(to: 3, 1, 2027)
        model.sceneDidBecomeActive()
        #expect(model.packing.current == nil)
        #expect(model.drawnTheme == nil)
    }

    @Test func playingElvesAreNotCutByAnActivation() {
        let (clock, model) = packingLaunch()
        _ = model.packing.start(for: scene, screen: Self.clear, animationsAllowed: true)
        clock.move(to: 3, 1, 2027)
        model.sceneDidBecomeActive()
        #expect(model.packing.isPlaying)
    }

    /// The packing keeps the seasonal theme that was drawn, which stays drawn until the elves are done.
    @Test func thePackingKeepsTheThemeThatWasDrawn() throws {
        let (_, model) = packingLaunch()
        #expect(try #require(model.packing.current).theme == .noelSoft)
    }
}

/// Where the elves stand (`NoelPackingLayout`): inside the band, never above its top, hidden below its bottom edge at the start
/// and at the end.
struct NoelPackingLayoutTests {
    /// The band of an iPhone 18 Pro in portrait: the window less the top and bottom bands and the safe areas.
    static let phone = CGSize(width: 402, height: 610)

    @Test(arguments: [(874.0, 500.0, 174.8), (1366.0, 900.0, 180.0), (874.0, 120.0, 120.0), (0.0, 500.0, 0.0)])
    func anElfIsAFifthOfTheWindowAtMost180PointsAndNeverTallerThanTheBand(window: Double, band: Double, height: Double) {
        #expect(abs(Double(NoelPackingLayout.elfHeight(window: window, band: band)) - height) < 1e-9)
    }

    @Test(arguments: [0.0, 1.0, -0.5, 1.5])
    func theElvesAreHiddenBelowTheBandAtTheStartAndTheEnd(progress: Double) {
        let frames = NoelPackingLayout.frames(in: Self.phone, windowHeight: 874, progress: progress)
        #expect(!frames.isEmpty)
        for frame in frames { #expect(frame.minY >= Self.phone.height) }
    }

    @Test(arguments: [(402.0, 874.0), (320.0, 568.0), (1024.0, 1366.0), (507.0, 1366.0), (874.0, 402.0)])
    func whileTheyPackTheyStandInsideTheBand(width: Double, window: Double) {
        let area = CGSize(width: width, height: max(window - 264, 0))
        for step in 0...40 {
            let progress = 0.2 + 0.6 * Double(step) / 40
            let frames = NoelPackingLayout.frames(in: area, windowHeight: window, progress: progress)
            #expect((1...NoelPackingLayout.maxElves).contains(frames.count))
            for frame in frames {
                #expect(frame.minX >= 0 && frame.maxX <= area.width)
                #expect(frame.minY >= 0 && frame.maxY <= area.height + 1e-9)
            }
            // Side by side, never overlapping.
            for (left, right) in zip(frames, frames.dropFirst()) { #expect(left.maxX < right.minX) }
        }
    }

    @Test func anEmptyBandHasNoElves() {
        #expect(NoelPackingLayout.frames(in: .zero, windowHeight: 874, progress: 0.5).isEmpty)
        #expect(NoelPackingLayout.frames(in: CGSize(width: 40, height: 400), windowHeight: 874, progress: 0.5).isEmpty)
    }

    @Test func theRiseGoesUpThenDown() {
        #expect(NoelPackingLayout.rise(at: 0) == 0)
        #expect(NoelPackingLayout.rise(at: 0.1) == 0.5)
        #expect(NoelPackingLayout.rise(at: 0.5) == 1)
        #expect(NoelPackingLayout.rise(at: 1) == 0)
    }
}
