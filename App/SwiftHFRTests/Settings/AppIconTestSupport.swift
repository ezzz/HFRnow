import Foundation
@testable import SwiftHFR

/// A switcher that records what the model applied; shared by the icon tests.
@MainActor
final class FakeIconSwitcher: AlternateIconSwitching {
    struct Refusal: Error {}

    init(current: String? = nil) { alternateIconName = current }
    var supportsAlternateIcons = true
    var fails = false
    var applied: [String?] = []
    var alternateIconName: String?
    var gate: CheckedContinuation<Void, Never>?
    var suspends = false

    func setAlternateIconName(_ name: String?) async throws {
        if suspends { await withCheckedContinuation { gate = $0 } }
        if fails { throw Refusal() }
        applied.append(name)
        alternateIconName = name
    }
}

/// A fixed Gregorian calendar and dates in it, so the date windows never depend on the machine's time zone.
enum IconTestCalendar {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour)) ?? .distantPast
    }
}
