import Foundation
@testable import SwiftHFR
import Testing

/// The Noël windows on local dates (THEMES.md §5): selectable 01/12–26/12, switched on 01/12–24/12, packing 27/12–02/01.
@MainActor
struct NoelCalendarTests {
    @Test(arguments: [
        (30, 11, 2026, NoelCalendar.Phase.outside, 2025),
        (1, 12, 2026, .switchOn, 2026),
        (24, 12, 2026, .switchOn, 2026),
        (25, 12, 2026, .arrivalOnly, 2026),
        (26, 12, 2026, .arrivalOnly, 2026),
        (27, 12, 2026, .packing, 2026),
        (31, 12, 2026, .packing, 2026),
        (1, 1, 2027, .packing, 2026),
        (2, 1, 2027, .packing, 2026),
        (3, 1, 2027, .outside, 2026),
        (15, 7, 2027, .outside, 2026)
    ])
    func eachDateHasItsPhaseAndSeason(day: Int, month: Int, year: Int, phase: NoelCalendar.Phase, season: Int) {
        let date = SeasonTestClock.date(day, month, year)
        #expect(NoelCalendar.phase(of: date, in: SeasonTestClock.calendar) == phase)
        #expect(NoelCalendar.seasonYear(of: date, in: SeasonTestClock.calendar) == season)
    }

    /// The local day decides, not UTC: 01/12 00:30 in Paris is still 30/11 in UTC.
    @Test func theWindowOpensAtLocalMidnight() {
        let justAfter = SeasonTestClock.date(1, 12, 2026, hour: 0, minute: 30)
        let justBefore = SeasonTestClock.date(30, 11, 2026, hour: 23, minute: 59)
        #expect(NoelCalendar.phase(of: justAfter, in: SeasonTestClock.calendar) == .switchOn)
        #expect(NoelCalendar.phase(of: justBefore, in: SeasonTestClock.calendar) == .outside)
    }

    @Test func onlyTheFirstTwentySixDaysOfDecemberAreSelectable() {
        #expect(NoelCalendar.Phase.switchOn.isSelectable)
        #expect(NoelCalendar.Phase.arrivalOnly.isSelectable)
        #expect(!NoelCalendar.Phase.packing.isSelectable)
        #expect(!NoelCalendar.Phase.outside.isSelectable)
    }
}
