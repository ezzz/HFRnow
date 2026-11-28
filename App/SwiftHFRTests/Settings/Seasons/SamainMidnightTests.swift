import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// Samain overlays that wait for a clear screen across midnight (LOT-191, the class #1438 found for the Fête nationale): a sweep
/// queued on 07/11 must not play on 08/11, nor an arrival queued at 23:59 on 31/10 on 01/11 with « Spooktober est là ! ».
@MainActor
struct SamainMidnightTests {
    private let clear = SeasonalThemeModel.ScreenState(isCovered: false, isPresenting: false, isKeyboardVisible: false)

    /// A model that opened on 15/10, answered the arrival and was left on until `day`/`month` at `hour`, with the sweep queued.
    private func packingModel(
        _ clock: SeasonTestClock, store: InMemorySettingsStore
    ) -> SeasonalThemeModel {
        let first = clock.model(store: store)
        first.sceneDidBecomeActive()
        first.answerArrival(disable: false)
        clock.move(to: 7, 11, 2027, hour: 23)
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        return model
    }

    @Test func aSweepQueuedOnThe7thIsDroppedAtMidnight() throws {
        let clock = SeasonTestClock(15, 10, 2027)
        let model = packingModel(clock, store: InMemorySettingsStore())
        #expect(try #require(model.packing.current).theme == .spooktoberSoft)
        // Still the 7th: it waits.
        model.dropOverlaysOutOfSeason()
        #expect(model.packing.current != nil)
        clock.move(to: 8, 11, 2027, hour: 0)
        model.dropOverlaysOutOfSeason()
        #expect(model.packing.current == nil && model.drawnTheme == nil)
    }

    @Test func aSweepAlreadyPlayingIsNotCutAtMidnight() {
        let clock = SeasonTestClock(15, 10, 2027)
        let model = packingModel(clock, store: InMemorySettingsStore())
        let scene = UUID()
        model.packing.sceneChanged(scene, active: true)
        #expect(model.packing.start(for: scene, screen: clear, animationsAllowed: true) != nil)
        clock.move(to: 8, 11, 2027, hour: 0)
        model.dropOverlaysOutOfSeason()
        #expect(model.packing.isPlaying(in: scene))
    }

    @Test func anArrivalQueuedAt2359On31OctoberIsDroppedAtMidnight() {
        let clock = SeasonTestClock(31, 10, 2027, hour: 23, minute: 59)
        let store = InMemorySettingsStore()
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        #expect(model.crossings.arrivalPending)
        #expect(model.pendingAlert == .samainArrival(year: 2027))
        model.dropOverlaysOutOfSeason()
        #expect(model.crossings.arrivalPending && model.pendingAlert != nil)
        clock.move(to: 1, 11, 2027, hour: 0)
        model.dropOverlaysOutOfSeason()
        #expect(!model.crossings.arrivalPending)
        #expect(model.pendingAlert == nil)
        #expect(!store.value(for: SettingKey.samainArrivalPending(year: 2027)))
    }

    /// Samain's drop never touches Noël's own waiting overlays: that class is Noël's own follow-up (#1440).
    @Test func aWaitingNoelArrivalIsLeftAlone() {
        let clock = SeasonTestClock(24, 12, 2027, hour: 23, minute: 59)
        let model = clock.model(store: InMemorySettingsStore())
        model.sceneDidBecomeActive()
        #expect(model.crossings.arrivalPending)
        clock.move(to: 25, 12, 2027, hour: 0)
        model.dropOverlaysOutOfSeason()
        #expect(model.crossings.arrivalPending)
    }

    /// The witch sweeping hides the decorations on the screens' backgrounds, which fade; once she is done they are gone with
    /// the theme.
    @Test func theDecorationsAreHiddenWhileTheWitchSweeps() {
        let clock = SeasonTestClock(15, 10, 2027)
        let model = packingModel(clock, store: InMemorySettingsStore())
        #expect(!model.packing.hidesDecorations)
        let scene = UUID()
        model.packing.sceneChanged(scene, active: true)
        _ = model.packing.start(for: scene, screen: clear, animationsAllowed: true)
        #expect(model.packing.hidesDecorations)
        model.packing.finish()
        #expect(!model.packing.hidesDecorations && model.drawnTheme == nil)
    }
}
