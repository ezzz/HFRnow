import Foundation

/// A group of the icon picker (ICONS.md §2).
enum AppIconPack: String, CaseIterable, Identifiable, Sendable {
    case legacy
    case beta
    case xface
    case season
    case glass

    var id: String { rawValue }

    /// Section title.
    var title: String {
        switch self {
        case .legacy: "Legacy"
        case .beta: "Beta"
        case .xface: "X-face"
        case .season: "Saisons"
        case .glass: "Liquid Glass"
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

    /// True when the calendar day of `date` is inside the window, in the calendar's time zone. The day is the Gregorian one, as the
    /// seasonal theme's (`NoelCalendar`): an Islamic, Hebrew or Persian device calendar never moves the window (#1199).
    func contains(_ date: Date, calendar: Calendar) -> Bool {
        let day = NoelCalendar.gregorian(in: calendar.timeZone).dateComponents([.month, .day], from: date)
        let value = (day.month ?? 0) * 100 + (day.day ?? 0)
        let start = startMonth * 100 + startDay
        let end = endMonth * 100 + endDay
        return start <= end ? (start...end).contains(value) : (value >= start || value <= end)
    }

    /// The year in which the last occurrence of the window ended on or before `date`: what a "window already answered" mark is
    /// keyed on, so a launch on 03/01 belongs to the Noël that ended the previous 26/12.
    func lastEndYear(before date: Date, calendar: Calendar) -> Int {
        let parts = NoelCalendar.gregorian(in: calendar.timeZone).dateComponents([.year, .month, .day], from: date)
        let year = parts.year ?? 0
        let today = (parts.month ?? 0) * 100 + (parts.day ?? 0)
        return today >= endMonth * 100 + endDay ? year : year - 1
    }
}

// Port of HFRswift/Swift/AppSettingsView.swift (AppIconOption, lines 33-83) @ 87fe0d1c. Differences: the art is the layered `.icon` of
// each legacy set (redone or reused by the Mac art PR, same names); `redface3dbig` is new (`Icon-RedFace3DBig`, no legacy value);
// packs, date windows and the seasonal icons are new (GAP-148, LOT-189); the X-face, Halloween, spring, summer and winter
// icons, Orange, Classique Blue and Beta rouge are the art of LOT-190 (#731); the Liquid Glass pack is new (#1409).
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
    case classicBlue = "classic-blue"
    case orange
    case betaRed = "beta-red"
    case xface
    case xfacePride = "xface-pride"
    case xfacePrideOutline = "xface-pride-outline"
    case xfaceGradientLight = "xface-gradient-light"
    case xfaceGradientDark = "xface-gradient-dark"
    case xfaceGold = "xface-gold"
    case xfaceGoldOnBlack = "xface-gold-on-black"
    case xfaceGoldOutline = "xface-gold-outline"
    case xface5250 = "xface-5250"
    case xfaceNegative = "xface-negative"
    case xfaceNegativeInverted = "xface-negative-inverted"
    case xfaceSunset = "xface-sunset"
    case halloweenJack = "halloween-jack"
    case halloweenHfr = "halloween-hfr"
    case spring
    case summer
    case winter
    case glassH = "glass-h"
    case glassFaceRing = "glass-face-ring"
    case glassFaceDisc = "glass-face-disc"

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
        case .classicBlue: "Classique Blue"
        case .orange: "Orange"
        case .betaRed: "Beta rouge"
        case .xface: "X-face"
        case .xfacePride: "Fierté"
        case .xfacePrideOutline: "Fierté contour"
        case .xfaceGradientLight: "Dégradé clair"
        case .xfaceGradientDark: "Dégradé sombre"
        case .xfaceGold: "Or"
        case .xfaceGoldOnBlack: "Or sur noir"
        case .xfaceGoldOutline: "Or contour"
        case .xface5250: "Terminal 5250"
        case .xfaceNegative: "Négatif"
        case .xfaceNegativeInverted: "Négatif inversé"
        case .xfaceSunset: "Coucher de soleil"
        case .halloweenJack: "Halloween citrouille"
        case .halloweenHfr: "Halloween HFR"
        case .spring: "Printemps"
        case .summer: "Été"
        case .winter: "Hiver"
        case .glassH: "H plein cadre"
        case .glassFaceRing: "Face anneau"
        case .glassFaceDisc: "Face disque"
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
        case .classicBlue: "Icon-CLASSIC-BLUE"
        case .orange: "Icon-ORANGE"
        case .betaRed: "Icon-BETA-RED"
        case .xface: "Icon-XFACE"
        case .xfacePride: "Icon-XFACE-PRIDE"
        case .xfacePrideOutline: "Icon-XFACE-PRIDE-OUTLINE"
        case .xfaceGradientLight: "Icon-XFACE-GRADIENT-LIGHT"
        case .xfaceGradientDark: "Icon-XFACE-GRADIENT-DARK"
        case .xfaceGold: "Icon-XFACE-GOLD"
        case .xfaceGoldOnBlack: "Icon-XFACE-GOLD-ON-BLACK"
        case .xfaceGoldOutline: "Icon-XFACE-GOLD-OUTLINE"
        case .xface5250: "Icon-XFACE-5250"
        case .xfaceNegative: "Icon-XFACE-NEGATIVE"
        case .xfaceNegativeInverted: "Icon-XFACE-NEGATIVE-INVERTED"
        case .xfaceSunset: "Icon-XFACE-SUNSET"
        case .halloweenJack: "Icon-HALLOWEEN-JACK"
        case .halloweenHfr: "Icon-HALLOWEEN-HFR"
        case .spring: "Icon-SPRING"
        case .summer: "Icon-SUMMER"
        case .winter: "Icon-WINTER"
        case .glassH: "Icon-GLASS-H"
        case .glassFaceRing: "Icon-GLASS-FACE-RING"
        case .glassFaceDisc: "Icon-GLASS-FACE-DISC"
        }
    }

    /// The picker group.
    var pack: AppIconPack {
        switch self {
        case .superblue, .classic, .classicRed, .classicBlue, .redface, .redfaceBlue, .blue, .white, .orange, .redface3dbig: .legacy
        case .beta, .betaRed: .beta
        case .xface, .xfacePride, .xfacePrideOutline, .xfaceGradientLight, .xfaceGradientDark, .xfaceGold, .xfaceGoldOnBlack,
             .xfaceGoldOutline, .xface5250, .xfaceNegative, .xfaceNegativeInverted, .xfaceSunset:
            .xface
        case .noelRedface, .noelHfr, .halloweenJack, .halloweenHfr, .spring, .summer, .winter: .season
        case .glassH, .glassFaceRing, .glassFaceDisc: .glass
        }
    }

    /// The days the icon is offered; nil is all year.
    var window: IconWindow? {
        switch self {
        case .noelRedface, .noelHfr: IconWindow(startMonth: 12, startDay: 1, endMonth: 12, endDay: 26)
        case .halloweenJack, .halloweenHfr: IconWindow(startMonth: 10, startDay: 1, endMonth: 10, endDay: 31)
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
