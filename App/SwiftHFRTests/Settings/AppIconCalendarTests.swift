import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// The icon windows are Gregorian whatever the device calendar, as the seasonal theme's are (#1199, `NoelCalendar`).
@MainActor
struct AppIconCalendarTests {
    private static let noel = IconWindow(startMonth: 12, startDay: 1, endMonth: 12, endDay: 26)

    private static let calendars: [Calendar.Identifier] = [.islamicUmmAlQura, .hebrew, .persian, .buddhist, .japanese]

    private func deviceCalendar(_ identifier: Calendar.Identifier) -> Calendar {
        var calendar = Calendar(identifier: identifier)
        calendar.timeZone = IconTestCalendar.calendar.timeZone
        return calendar
    }

    @Test(arguments: calendars)
    func iconWindowsAreGregorianWhateverTheDeviceCalendar(identifier: Calendar.Identifier) {
        let calendar = deviceCalendar(identifier)
        #expect(Self.noel.contains(IconTestCalendar.date(2026, 12, 10), calendar: calendar), "10 December is inside Noël's window")
        #expect(!Self.noel.contains(IconTestCalendar.date(2026, 6, 10), calendar: calendar), "10 June is not")
    }

    @Test(arguments: calendars)
    func theLastEndYearIsTheGregorianOne(identifier: Calendar.Identifier) {
        let calendar = deviceCalendar(identifier)
        #expect(Self.noel.lastEndYear(before: IconTestCalendar.date(2027, 1, 3), calendar: calendar) == 2026)
        #expect(Self.noel.lastEndYear(before: IconTestCalendar.date(2026, 12, 27), calendar: calendar) == 2026)
        #expect(Self.noel.lastEndYear(before: IconTestCalendar.date(2026, 12, 10), calendar: calendar) == 2025)
    }

    /// The picker offers the Noël icons in December on a device whose calendar is not Gregorian, and not in June.
    @Test(arguments: [Calendar.Identifier.islamicUmmAlQura, .hebrew, .persian])
    func thePickerOffersTheNoelIconsInDecemberOnAnyCalendar(identifier: Calendar.Identifier) {
        let calendar = deviceCalendar(identifier)
        func offered(on date: Date) -> Set<AppIconOption> {
            let model = AppIconSettingsModel(
                store: InMemorySettingsStore(), switcher: FakeIconSwitcher(current: nil), calendar: calendar, now: { date }
            )
            return Set(model.sections.flatMap(\.options))
        }
        #expect(offered(on: IconTestCalendar.date(2026, 12, 10)).contains(.noelHfr))
        #expect(!offered(on: IconTestCalendar.date(2026, 6, 10)).contains(.noelHfr))
    }
}
