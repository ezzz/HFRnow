import Foundation

// Port of Classes/HFRplusAppDelegate.m (applicationDidBecomeActive, the "Noel" dates) @ 87fe0d1c. Differences: yearly windows on
// the user's local calendar instead of 24/12/2022–09/01/2023 hard-coded (`:635-636`); GAP-147.
/// The Noël windows of THEMES.md §5 on local dates. A season is named after the year of its December.
enum NoelCalendar {
    /// Where a date falls in its season.
    enum Phase: Equatable, Sendable {
        /// 01/12–24/12 (Samain: 01/10–31/10): selectable, and the soft theme is switched on at the first launch.
        case switchOn
        /// 25/12–26/12: selectable, the arrival plays, nothing is switched on.
        case arrivalOnly
        /// 27/12–02/01 (Samain: 01/11–07/11): a seasonal theme still on is packed at the first launch.
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

/// A seasonal theme (THEMES.md §2); its raw value is its id (`season.<family>.<year>.themeID`, and the theme file of the ones
/// the engine draws).
enum SeasonalTheme: String, CaseIterable, Identifiable, Sendable {
    /// The current look with light snow, and legacy's red accent over Legacy (a gallery theme keeps its accent).
    case noelSoft = "noel-soft"
    /// A theme of the engine (LOT-188, `Themes/noel-abuse/`): fir green, one variant, its art behind the content.
    case noelAbuse = "noel-abuse"
    /// A theme of the engine (LOT-191, `Themes/spooktober-soft/`): light and dark, a bit of web, a candelabra and a bat behind
    /// the content, a ghost, a witch or lightning crossing now and then.
    case spooktoberSoft = "spooktober-soft"
    /// A theme of the engine (LOT-191, `Themes/spooktober-abuse/`): orange, black and purple, one variant, lots of art.
    case spooktoberAbuse = "spooktober-abuse"

    var id: String { rawValue }

    /// The family whose window it belongs to.
    var family: SeasonFamily {
        switch self {
        case .noelSoft, .noelAbuse: .noel
        case .spooktoberSoft, .spooktoberAbuse: .samain
        }
    }

    /// Name shown in Réglages › Thème.
    var title: String {
        switch self {
        case .noelSoft: "Noël soft"
        case .noelAbuse: "Noël abusé"
        case .spooktoberSoft: "Spooktober soft"
        case .spooktoberAbuse: "Spooktober abusé"
        }
    }

    /// A theme of the engine, drawn from its file over whatever the user's theme is (Noël soft is an overlay of the look).
    var isEngineTheme: Bool { self != .noelSoft }

    /// Things cross the screen now and then while it is on (THEMES.md §4 rule 4).
    var hasCrossings: Bool { self == .noelSoft || self == .spooktoberSoft }

    /// What crosses while it is on, one at random every 20–90 min.
    var crossingItems: [NoelCrossingItem] {
        self == .spooktoberSoft ? NoelCrossingItem.samainCrossing : NoelCrossingItem.crossing
    }
}
