import Foundation
@testable import SwiftHFR
import Testing

/// The Samain windows on local Gregorian dates (LOT-191, THEMES.md §5): selectable and switched on 01/10–31/10, packed at the first
/// launch 01/11–07/11, restored silently after; the season is named after the year of its October.
@MainActor
struct SamainCalendarTests {
    private func phase(_ day: Int, _ month: Int, hour: Int = 10) -> NoelCalendar.Phase {
        SamainCalendar.phase(of: SeasonTestClock.date(day, month, 2027, hour: hour), in: SeasonTestClock.calendar)
    }

    @Test func theWindowsRunFromTheFirstOfOctoberToTheSeventhOfNovember() {
        #expect(phase(30, 9) == .outside)
        #expect(phase(1, 10) == .switchOn)
        #expect(phase(15, 10) == .switchOn)
        #expect(phase(31, 10) == .switchOn)
        #expect(phase(1, 11) == .packing)
        #expect(phase(7, 11) == .packing)
        #expect(phase(8, 11) == .outside)
        #expect(phase(25, 12) == .outside)
        #expect(phase(1, 10).isSelectable && phase(31, 10).isSelectable)
        #expect(!phase(30, 9).isSelectable && !phase(1, 11).isSelectable)
    }

    /// A season is named after the year of its October, so the packing days and the months after belong to it.
    @Test func aSeasonIsNamedAfterTheYearOfItsOctober() {
        func year(_ day: Int, _ month: Int) -> Int {
            SamainCalendar.seasonYear(of: SeasonTestClock.date(day, month, 2027), in: SeasonTestClock.calendar)
        }
        #expect(year(30, 9) == 2026)
        #expect(year(1, 10) == 2027)
        #expect(year(7, 11) == 2027)
        #expect(year(25, 12) == 2027)
        #expect(SamainCalendar.seasonYear(of: SeasonTestClock.date(15, 3, 2028), in: SeasonTestClock.calendar) == 2027)
    }

    /// Local dates: 23:30 on 31/10 in Paris is already 01/11 in Auckland; and a Buddhist or Japanese device calendar names the
    /// same Gregorian days.
    @Test func theDayIsTheLocalOneInTheGregorianCalendar() throws {
        let late = SeasonTestClock.date(31, 10, 2027, hour: 23, minute: 30)
        let paris = SeasonTestClock.calendar
        #expect(SamainCalendar.phase(of: late, in: paris) == .switchOn)
        var auckland = Calendar(identifier: .gregorian)
        auckland.timeZone = try #require(TimeZone(identifier: "Pacific/Auckland"))
        #expect(SamainCalendar.phase(of: late, in: auckland) == .packing)
        for identifier in [Calendar.Identifier.buddhist, .japanese, .islamicUmmAlQura] {
            var other = Calendar(identifier: identifier)
            other.timeZone = paris.timeZone
            #expect(SamainCalendar.phase(of: late, in: other) == .switchOn, "\(identifier)")
            #expect(SamainCalendar.seasonYear(of: late, in: other) == 2027, "\(identifier)")
        }
    }

    @Test func theFamilyReadsItsOwnKeysAndTheirSeason() {
        #expect(SeasonFamily.samain.themeID(year: 2027).key == "season.samain.2027.themeID")
        #expect(SeasonFamily.samain.activeYear.key == "season.samain.activeYear")
        #expect(SeasonFamily.noel.themeID(year: 2026).key == "season.noel.2026.themeID")
        #expect(SeasonalTheme.spooktoberSoft.family == .samain && SeasonalTheme.noelAbuse.family == .noel)
        #expect(SeasonFamily.samain.defaultTheme == .spooktoberSoft)
        #expect(SeasonFamily.samain.arrivalItems == [.witch, .ghost, .bat, .vampire])
    }
}
