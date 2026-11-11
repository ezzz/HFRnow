import Foundation

// Port of Classes/HFRplusAppDelegate.m (applicationDidBecomeActive, the "Noel" dates) @ 87fe0d1c. Differences: yearly windows on
// the user's local calendar instead of 24/12/2022–09/01/2023 hard-coded (`:635-636`); GAP-147.
/// The Noël windows of THEMES.md §5 on local dates. A season is named after the year of its December.
enum NoelCalendar {
    /// Where a date falls in its season.
    enum Phase: Equatable, Sendable {
        /// 01/12–24/12: Noël is selectable, and Noël soft is switched on at the first launch.
        case switchOn
        /// 25/12–26/12: selectable, the arrival plays, nothing is switched on.
        case arrivalOnly
        /// 27/12–02/01: a Noël theme still on is packed at the first launch.
        case packing
        /// 03/01–30/11: a Noël theme still on is restored silently.
        case outside

        /// A Noël theme can be picked, and the « Thèmes de saison » section shows.
        var isSelectable: Bool { self == .switchOn || self == .arrivalOnly }
    }

    /// The Gregorian calendar in `timeZone`: season dates and years never follow a Buddhist or Japanese device calendar.
    static func gregorian(in timeZone: TimeZone) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// The phase of `date` in `calendar`'s time zone (Gregorian dates).
    static func phase(of date: Date, in calendar: Calendar) -> Phase {
        let parts = gregorian(in: calendar.timeZone).dateComponents([.month, .day], from: date)
        switch (parts.month ?? 0, parts.day ?? 0) {
        case (12, 1...24): return .switchOn
        case (12, 25...26): return .arrivalOnly
        case (12, 27...), (1, 1...2): return .packing
        default: return .outside
        }
    }

    /// The season `date` belongs to: its year in December, the year before otherwise (January's packing is December's season).
    static func seasonYear(of date: Date, in calendar: Calendar) -> Int {
        let parts = gregorian(in: calendar.timeZone).dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        return parts.month == 12 ? year : year - 1
    }
}

/// A seasonal theme (THEMES.md §2). Noël abusé joins with the theme engine (LOT-188, PR 4 of LOT-166).
enum SeasonalTheme: String, CaseIterable, Identifiable, Sendable {
    /// The current look with legacy's red accent and light snow.
    case noelSoft = "noel-soft"

    var id: String { rawValue }

    /// Name shown in Réglages › Thème.
    var title: String {
        switch self {
        case .noelSoft: "Noël soft"
        }
    }
}
