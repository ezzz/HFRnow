import Foundation
import HFRStorage

// No legacy counterpart @ 87fe0d1c: legacy had a Christmas mode only and no Halloween theme (GAP-147, LOT-191 gap row).
/// The Samain windows of THEMES.md §5 on local dates: Spooktober is selectable and switched on the whole of October, a Samain
/// theme still on is packed at the first launch 01/11–07/11 (the seven days Noël's packing has), and restored silently after
/// that. A season is named after the year of its October. Same phases as `NoelCalendar`, whose helpers it reuses.
enum SamainCalendar {
    /// The phase of `date` in `calendar`'s time zone (Gregorian dates, whatever the device's calendar).
    static func phase(of date: Date, in calendar: Calendar) -> NoelCalendar.Phase {
        let parts = NoelCalendar.gregorian(in: calendar.timeZone).dateComponents([.month, .day], from: date)
        switch (parts.month ?? 0, parts.day ?? 0) {
        case (10, _): return .switchOn
        case (11, 1...7): return .packing
        default: return .outside
        }
    }

    /// The season `date` belongs to: its year from October on, the year before until then (the packing days are October's).
    static func seasonYear(of date: Date, in calendar: Calendar) -> Int {
        let parts = NoelCalendar.gregorian(in: calendar.timeZone).dateComponents([.year, .month], from: date)
        let year = parts.year ?? 0
        return (parts.month ?? 0) >= 10 ? year : year - 1
    }
}

/// A family of seasonal themes: the windows, the device-only keys and the items of its arrival (THEMES.md §5). The scheduler
/// treats each the same way; only these values differ.
enum SeasonFamily: CaseIterable, Sendable {
    case noel
    case samain

    /// Where `date` falls in this family's season.
    func phase(of date: Date, in calendar: Calendar) -> NoelCalendar.Phase {
        switch self {
        case .noel: NoelCalendar.phase(of: date, in: calendar)
        case .samain: SamainCalendar.phase(of: date, in: calendar)
        }
    }

    /// The season `date` belongs to, as the keys name it.
    func seasonYear(of date: Date, in calendar: Calendar) -> Int {
        switch self {
        case .noel: NoelCalendar.seasonYear(of: date, in: calendar)
        case .samain: SamainCalendar.seasonYear(of: date, in: calendar)
        }
    }

    /// The theme switched on automatically, and the one an unknown or missing stored id reads as.
    var defaultTheme: SeasonalTheme {
        switch self {
        case .noel: .noelSoft
        case .samain: .spooktoberSoft
        }
    }

    /// What crosses on the arrival, one at random (a quarter of the window high): Santa's sleigh; a witch on a broom, a ghost, a
    /// bat or a vampire (operator, 2026-10-28).
    var arrivalItems: [NoelCrossingItem] {
        switch self {
        case .noel: [.sleigh]
        case .samain: NoelCrossingItem.samainArrival
        }
    }

    // MARK: Device-only keys (ADR 0013 matrix E)

    var activeYear: Setting<Int?> {
        switch self {
        case .noel: SettingKey.noelActiveYear
        case .samain: SettingKey.samainActiveYear
        }
    }

    func arrivalShown(year: Int) -> Setting<Bool> {
        switch self {
        case .noel: SettingKey.noelArrivalShown(year: year)
        case .samain: SettingKey.samainArrivalShown(year: year)
        }
    }

    func arrivalPending(year: Int) -> Setting<Bool> {
        switch self {
        case .noel: SettingKey.noelArrivalPending(year: year)
        case .samain: SettingKey.samainArrivalPending(year: year)
        }
    }

    func optedOut(year: Int) -> Setting<Bool> {
        switch self {
        case .noel: SettingKey.noelOptedOut(year: year)
        case .samain: SettingKey.samainOptedOut(year: year)
        }
    }

    func previousThemeID(year: Int) -> Setting<String?> {
        switch self {
        case .noel: SettingKey.noelPreviousThemeID(year: year)
        case .samain: SettingKey.samainPreviousThemeID(year: year)
        }
    }

    func themeID(year: Int) -> Setting<String?> {
        switch self {
        case .noel: SettingKey.noelThemeID(year: year)
        case .samain: SettingKey.samainThemeID(year: year)
        }
    }

    func packingShown(year: Int) -> Setting<Bool> {
        switch self {
        case .noel: SettingKey.noelPackingShown(year: year)
        case .samain: SettingKey.samainPackingShown(year: year)
        }
    }
}
