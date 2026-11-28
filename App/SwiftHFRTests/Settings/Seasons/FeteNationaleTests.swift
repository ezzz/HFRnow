import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// The calendar of the 14 July overlay (LOT-194, THEMES.md §5): local Gregorian dates, whatever the device's calendar.
@MainActor
struct FeteNationaleCalendarTests {
    @Test(arguments: [
        (13, 7, 2027, false), (14, 7, 2027, true), (15, 7, 2027, false), (14, 6, 2027, false), (14, 8, 2027, false),
        (14, 7, 2028, true), (14, 1, 2027, false)
    ])
    func onlyThe14thOfJulyIsTheDay(day: Int, month: Int, year: Int, isTheDay: Bool) {
        let date = SeasonTestClock.date(day, month, year)
        #expect(FeteNationaleCalendar.isFeteNationale(date, in: SeasonTestClock.calendar) == isTheDay)
        #expect(FeteNationaleCalendar.year(of: date, in: SeasonTestClock.calendar) == year)
    }

    /// The local day decides, not UTC: 14/07 00:30 in Paris is still 13/07 in UTC, 14/07 23:30 in Paris is 15/07 in Auckland.
    @Test func theDayStartsAndEndsAtLocalMidnight() {
        let justAfter = SeasonTestClock.date(14, 7, 2027, hour: 0, minute: 30)
        let justBefore = SeasonTestClock.date(13, 7, 2027, hour: 23, minute: 59)
        let evening = SeasonTestClock.date(14, 7, 2027, hour: 23, minute: 30)
        #expect(FeteNationaleCalendar.isFeteNationale(justAfter, in: SeasonTestClock.calendar))
        #expect(!FeteNationaleCalendar.isFeteNationale(justBefore, in: SeasonTestClock.calendar))
        let auckland = NoelCalendar.gregorian(in: TimeZone(identifier: "Pacific/Auckland") ?? .gmt)
        #expect(!FeteNationaleCalendar.isFeteNationale(evening, in: auckland))
        #expect(FeteNationaleCalendar.isFeteNationale(evening, in: SeasonTestClock.calendar))
    }

    /// A Buddhist or Japanese device calendar still reads Gregorian dates and years (the key would name another year).
    @Test(arguments: [Calendar.Identifier.buddhist, .japanese, .islamicUmmAlQura, .hebrew])
    func theDeviceCalendarDoesNotMatter(identifier: Calendar.Identifier) {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = SeasonTestClock.calendar.timeZone
        let date = SeasonTestClock.date(14, 7, 2027)
        #expect(FeteNationaleCalendar.isFeteNationale(date, in: calendar))
        #expect(FeteNationaleCalendar.year(of: date, in: calendar) == 2027)
        #expect(!FeteNationaleCalendar.isFeteNationale(SeasonTestClock.date(15, 7, 2027), in: calendar))
    }
}

/// The 14 July overlay (LOT-194): the first launch of the day plays it once a year, on a clear screen, in one scene, unless
/// animations are off or Reduce Motion is on (THEMES.md §4 rules 1–3, 5).
@MainActor
struct FeteNationaleTests {
    static let clear = SeasonalThemeModel.ScreenState()
    let scene = UUID()

    private func launch(
        _ day: Int, _ month: Int = 7, _ year: Int = 2027, store: InMemorySettingsStore = InMemorySettingsStore(),
        reduceMotion: Bool = false
    ) -> (SeasonTestClock, SeasonalThemeModel) {
        let clock = SeasonTestClock(day, month, year)
        clock.reduceMotion = reduceMotion
        let model = clock.model(store: store)
        model.sceneDidBecomeActive()
        model.fete.sceneChanged(scene, active: true)
        return (clock, model)
    }

    private func play(_ model: SeasonalThemeModel) -> FeteNationaleModel.Show? {
        model.fete.start(for: scene, screen: Self.clear, animationsAllowed: model.animationsAllowed)
    }

    @Test func theFirstLaunchOf14JulyPlays() throws {
        let (_, model) = launch(14)
        #expect(model.fete.current?.year == 2027)
        #expect(!model.fete.isPlaying)
        let show = try #require(play(model))
        #expect(show.scene == scene && model.fete.isPlaying(in: scene))
    }

    @Test(arguments: [13, 15])
    func theDaysAroundItNothingPlays(day: Int) {
        let (_, model) = launch(day)
        #expect(model.fete.current == nil)
        #expect(play(model) == nil)
    }

    @Test func otherMonthsAndDecemberNeverPlay() {
        for (day, month) in [(14, 6), (14, 8), (14, 12), (1, 1)] {
            let (_, model) = launch(day, month, 2027)
            #expect(model.fete.current == nil, "\(day)/\(month)")
        }
    }

    /// First launch of the day only: a second activation, a second launch, and a launch after a kill play nothing.
    @Test func aSecondLaunchTheSameDayPlaysNothing() {
        let store = InMemorySettingsStore()
        let (clock, first) = launch(14, store: store)
        #expect(play(first) != nil)
        first.fete.finish()
        first.sceneDidBecomeActive()
        #expect(first.fete.current == nil)
        clock.now += 3600
        let second = clock.model(store: store)
        second.sceneDidBecomeActive()
        #expect(second.fete.current == nil)
        #expect(store.value(for: SettingKey.feteNationaleShown(year: 2027)))
    }

    @Test func theNextYearPlaysAgain() {
        let store = InMemorySettingsStore()
        let (_, first) = launch(14, 7, 2027, store: store)
        first.fete.finish()
        let (_, next) = launch(14, 7, 2028, store: store)
        #expect(next.fete.current?.year == 2028)
        #expect(!store.value(for: SettingKey.feteNationaleShown(year: 2026)))
    }

    /// The time zone of the moment decides the day.
    @Test func theDayFollowsTheDevicesTimeZone() {
        let clock = SeasonTestClock(14, 7, 2027, hour: 23, minute: 30)
        clock.timeZone = TimeZone(identifier: "Pacific/Auckland") ?? .gmt
        let model = clock.model(store: InMemorySettingsStore())
        model.sceneDidBecomeActive()
        #expect(model.fete.current == nil)
        clock.timeZone = SeasonTestClock.calendar.timeZone
        model.sceneDidBecomeActive()
        #expect(model.fete.current != nil)
    }

    /// Reduce Motion: nothing plays, and the day counts as seen.
    @Test func withReduceMotionNothingPlays() {
        let store = InMemorySettingsStore()
        let (_, model) = launch(14, store: store, reduceMotion: true)
        #expect(model.fete.current == nil)
        #expect(play(model) == nil)
        #expect(store.value(for: SettingKey.feteNationaleShown(year: 2027)))
    }

    /// « Animations de saison » off: nothing plays.
    @Test func withSeasonalAnimationsOffNothingPlays() {
        let clock = SeasonTestClock(14, 7, 2027)
        let model = clock.model(store: InMemorySettingsStore())
        model.animationsEnabled = false
        model.sceneDidBecomeActive()
        #expect(model.fete.current == nil)
    }

    @Test func animationsTurnedOffBeforeItPlaysDropIt() {
        let (_, model) = launch(14)
        model.animationsEnabled = false
        #expect(play(model) == nil)
        #expect(model.fete.current == nil)
    }

    /// A queued overlay is dropped once the day is over (the app stayed in the background past midnight).
    @Test func aWaitingOverlayDoesNotSurviveTheDay() {
        let (clock, model) = launch(14)
        clock.move(to: 15, 7, 2027)
        model.sceneDidBecomeActive()
        #expect(model.fete.current == nil)
    }

    /// 3–5 s (THEMES.md §4 rule 3).
    @Test func itLastsBetweenThreeAndFiveSeconds() {
        #expect(FeteNationaleModel.duration >= 3 && FeteNationaleModel.duration <= 5)
    }

    @Test(arguments: [
        SeasonalThemeModel.ScreenState(isCovered: true),
        SeasonalThemeModel.ScreenState(isPresenting: true),
        SeasonalThemeModel.ScreenState(isKeyboardVisible: true)
    ])
    func itWaitsForAClearScreen(screen: SeasonalThemeModel.ScreenState) {
        let (_, model) = launch(14)
        #expect(model.fete.start(for: scene, screen: screen, animationsAllowed: true) == nil)
        #expect(model.fete.current != nil)
        #expect(play(model) != nil)
    }

    @Test func itWaitsForItsSceneAndOnlyOneScenePlaysIt() {
        let (_, model) = launch(14)
        let other = UUID()
        model.fete.sceneChanged(other, active: false)
        #expect(model.fete.start(for: other, screen: Self.clear, animationsAllowed: true) == nil)
        model.fete.sceneChanged(other, active: true)
        #expect(play(model) != nil)
        #expect(model.fete.start(for: other, screen: Self.clear, animationsAllowed: true) == nil)
        #expect(model.fete.isPlaying(in: scene) && !model.fete.isPlaying(in: other))
    }

    @Test func aTapOrTheEndFinishesIt() {
        let (_, model) = launch(14)
        _ = play(model)
        model.fete.finish()
        #expect(model.fete.current == nil && !model.fete.isPlaying)
        #expect(play(model) == nil)
    }

    /// Cut in its first second it waits and plays again, at most twice; then it is over.
    @Test func aCutInTheFirstSecondPlaysAgainAtMostTwice() {
        let (clock, model) = launch(14)
        let alert = SeasonalThemeModel.ScreenState(isPresenting: true)
        for _ in 1...FeteNationaleModel.maxReplays {
            #expect(play(model) != nil)
            clock.now += 0.5
            model.fete.screenChanged(for: scene, screen: alert)
            #expect(model.fete.current != nil && !model.fete.isPlaying)
        }
        #expect(play(model) != nil)
        model.fete.screenChanged(for: scene, screen: alert)
        #expect(model.fete.current == nil)
    }

    @Test func aCutAfterTheFirstSecondIsOver() {
        let (clock, model) = launch(14)
        _ = play(model)
        clock.now += 2
        model.fete.screenChanged(for: scene, screen: SeasonalThemeModel.ScreenState(isKeyboardVisible: true))
        #expect(model.fete.current == nil)
    }

    @Test func theSceneLeavingEndsItOrReplaysIt() {
        let (clock, model) = launch(14)
        _ = play(model)
        clock.now += 0.4
        model.fete.sceneChanged(scene, active: false)
        #expect(model.fete.current != nil && !model.fete.isPlaying)
        model.fete.sceneChanged(scene, active: true)
        _ = play(model)
        clock.now += 2
        model.fete.release(scene: scene)
        #expect(model.fete.current == nil)
    }

    /// « Fête nationale » is spoken once, however often it is replayed (the overlay is hidden from VoiceOver).
    @Test func theSentenceIsAnnouncedOnce() {
        let (clock, model) = launch(14)
        _ = play(model)
        #expect(model.fete.shouldAnnounce())
        clock.now += 0.5
        model.fete.screenChanged(for: scene, screen: SeasonalThemeModel.ScreenState(isPresenting: true))
        _ = play(model)
        #expect(!model.fete.shouldAnnounce())
    }

    /// The Noël scheduler is untouched: 14 July is outside every Noël window.
    @Test func noelStaysOutside() {
        let (_, model) = launch(14)
        #expect(model.activeTheme == nil && model.pendingAlert == nil && !model.isSelectable)
    }
}

/// The choreography stays inside its limits (THEMES.md §4 rules 3, 7, 9).
struct FeteNationaleLayoutTests {
    @Test func theBustFadesInAndOutAndIsFullInTheMiddle() {
        #expect(FeteNationaleLayout.presence(at: 0) == 0)
        #expect(FeteNationaleLayout.presence(at: 1) == 0)
        #expect(FeteNationaleLayout.presence(at: 0.5) == 1)
        #expect(FeteNationaleLayout.presence(at: -1) == 0 && FeteNationaleLayout.presence(at: 2) == 0)
    }

    @Test func everyBurstStartsAndEndsInsideTheRun() {
        for burst in FeteNationaleLayout.bursts {
            #expect(burst.start >= 0 && burst.start + FeteNationaleLayout.burstSpan <= 1)
            #expect((0...1).contains(burst.centre.x) && (0...1).contains(burst.centre.y))
            #expect(FeteNationaleLayout.state(of: burst, at: burst.start - 0.01) == nil)
            #expect(FeteNationaleLayout.state(of: burst, at: burst.start + FeteNationaleLayout.burstSpan + 0.01) == nil)
            let open = FeteNationaleLayout.state(of: burst, at: burst.start + 0.01)
            #expect((open?.scale ?? 0) < 0.5 && open?.opacity == 1)
        }
        #expect(FeteNationaleLayout.bursts.count <= 5)
    }

    @Test func aBurstFadesAwayAtTheEnd() {
        let burst = FeteNationaleLayout.bursts[0]
        let last = FeteNationaleLayout.state(of: burst, at: burst.start + FeteNationaleLayout.burstSpan * 0.99)
        #expect((last?.opacity ?? 1) < 0.05 && (last?.scale ?? 0) > 0.99)
    }

    @Test func theBustIsFortyPercentOfTheBandAtMost300Points() {
        #expect(FeteNationaleLayout.bustHeight(band: 500) == 200)
        #expect(FeteNationaleLayout.bustHeight(band: 2000) == FeteNationaleLayout.maxBustHeight)
        #expect(FeteNationaleLayout.bustHeight(band: -5) == 0)
    }
}
