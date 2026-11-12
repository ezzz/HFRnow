import Foundation

/// A group of the icon picker (ICONS.md §2).
enum AppIconPack: String, CaseIterable, Identifiable, Sendable {
    case legacy
    case beta
    case xface
    case season

    var id: String { rawValue }

    /// Section title.
    var title: String {
        switch self {
        case .legacy: "Legacy"
        case .beta: "Beta"
        case .xface: "X-face"
        case .season: "Saisons"
        }
    }
}

/// The days of the year an icon is offered, both ends included (ICONS.md §2: Noël is 01/12 to 26/12). A window whose start is
/// after its end wraps the new year.
struct IconWindow: Equatable, Sendable {
    let startMonth: Int
    let startDay: Int
    let endMonth: Int
    let endDay: Int

    /// True when the calendar day of `date` is inside the window, in the calendar's time zone.
    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let day = calendar.dateComponents([.month, .day], from: date)
        let value = (day.month ?? 0) * 100 + (day.day ?? 0)
        let start = startMonth * 100 + startDay
        let end = endMonth * 100 + endDay
        return start <= end ? (start...end).contains(value) : (value >= start || value <= end)
    }

    /// The year in which the last occurrence of the window ended on or before `date`: what a "window already answered" mark is
    /// keyed on, so a launch on 03/01 belongs to the Noël that ended the previous 26/12.
    func lastEndYear(before date: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let today = (parts.month ?? 0) * 100 + (parts.day ?? 0)
        return today >= endMonth * 100 + endDay ? year : year - 1
    }
}

// Port of HFRswift/Swift/AppSettingsView.swift (AppIconOption, lines 33-83) @ 87fe0d1c. Differences: the art is the layered `.icon` of
// each legacy set (redone or reused by the Mac art PR, same names); `redface3dbig` is new (`Icon-RedFace3DBig`, no legacy value);
// packs, date windows and the seasonal icons are new (GAP-148, LOT-189).
// The `.icon` names live here only: a redrawn icon swaps in under the same name with no code change; adding an icon is a new case
// here (raw value, title, name, pack, window) plus its `.icon`, its previews and its name in the build settings (ICONS.md §5).
/// One choice of the icon picker.
enum AppIconOption: String, CaseIterable, Identifiable, Sendable {
    /// The primary icon (legacy "Défaut", key `superblue`).
    case superblue
    case classic
    case classicRed = "classic-red"
    case redface
    case redfaceBlue = "redface-blue"
    case beta
    case blue
    case white
    case redface3dbig
    case noelRedface = "noel-redface"
    case noelHfr = "noel-hfr"

    var id: String { rawValue }

    /// Picker label (legacy titles).
    var title: String {
        switch self {
        case .superblue: "Défaut"
        case .classic: "Classique Yellow"
        case .classicRed: "Classique Red"
        case .redface: "REDFACE"
        case .redfaceBlue: "REDFACE Blue"
        case .beta: "Beta"
        case .blue: "Blue"
        case .white: "White"
        case .redface3dbig: "REDFACE 3D Big"
        case .noelRedface: "Noël REDFACE"
        case .noelHfr: "Noël HFR"
        }
    }

    /// The name given to `setAlternateIconName`; nil is the primary icon. Each matches an `.icon` in `App/SwiftHFR/` and
    /// `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`; the legacy ones are the legacy names (`alternateIconName`, :64-83).
    var alternateIconName: String? {
        switch self {
        case .superblue: nil
        case .classic: "Icon-CLASSIC"
        case .classicRed: "Icon-CLASSIC-RED"
        case .redface: "Icon-REDFACE"
        case .redfaceBlue: "Icon-REDFACEBLUE"
        case .beta: "Icon-BETA"
        case .blue: "Icon-BLUE"
        case .white: "Icon-WHITE"
        case .redface3dbig: "Icon-RedFace3DBig"
        case .noelRedface: "Icon-NOEL-REDFACE"
        case .noelHfr: "Icon-NOEL-HFR"
        }
    }

    /// The picker group.
    var pack: AppIconPack {
        switch self {
        case .superblue, .classic, .classicRed, .redface, .redfaceBlue, .blue, .white, .redface3dbig: .legacy
        case .beta: .beta
        case .noelRedface, .noelHfr: .season
        }
    }

    /// The days the icon is offered; nil is all year.
    var window: IconWindow? {
        switch self {
        case .noelRedface, .noelHfr: IconWindow(startMonth: 12, startDay: 1, endMonth: 12, endDay: 26)
        default: nil
        }
    }

    /// The `.icon` bundle the option's art lives in (the primary icon is `Icon-RedFace3D`, #581).
    var iconBundleName: String { alternateIconName ?? "Icon-RedFace3D" }

    /// The preview image set in `Assets.xcassets/IconPreviews/`, rendered from the `.icon` by `scripts/icon-previews.sh` (the system
    /// has no API to read an alternate icon's image). Convention: `IconPreview-` + the `.icon` bundle name.
    var previewImageName: String { "IconPreview-\(iconBundleName)" }

    /// True when the option can be chosen on `date`.
    func isOffered(on date: Date, calendar: Calendar) -> Bool {
        window?.contains(date, calendar: calendar) ?? true
    }
}
