import Foundation
import HFRStorage
@testable import SwiftHFR

/// A clock the tests move by hand: no real waiting (LOT-166).
@MainActor
final class SeasonTestClock {
    var now: Date
    var reduceMotion = false
    /// The device's time zone, which the user may change during a run.
    var timeZone = SeasonTestClock.calendar.timeZone

    init(_ day: Int, _ month: Int, _ year: Int, hour: Int = 10, minute: Int = 0) {
        now = Self.date(day, month, year, hour: hour, minute: minute)
    }

    func move(to day: Int, _ month: Int, _ year: Int, hour: Int = 10) {
        now = Self.date(day, month, year, hour: hour)
    }

    /// Local dates: the window follows the user's calendar, so the tests use a non-UTC zone.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Paris") ?? .gmt
        return calendar
    }()

    static func date(_ day: Int, _ month: Int, _ year: Int, hour: Int = 10, minute: Int = 0) -> Date {
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute)
        return calendar.date(from: components) ?? .distantPast
    }

    /// A model on `store` reading this clock, as the app builds it at each launch.
    func model(store: any SettingsStore) -> SeasonalThemeModel {
        SeasonalThemeModel(store: store, now: { self.now }, timeZone: { self.timeZone }, reduceMotion: { self.reduceMotion })
    }
}
