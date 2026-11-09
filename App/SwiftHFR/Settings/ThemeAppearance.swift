import Foundation
import HFRModels
import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/Common.swift (ThemeUserColorStore.defaultTintColor, adjustedDarkThemeColor; AppThemePalette) and
// AppSettingsView.swift (applyTintHue) @ 21173e77. Differences: one value type the app root and the reader share; the reader
// gets its colours as CSS variables set from its own content world, not a stylesheet built per theme (LOT-083 CSP).
/// The colours the "Thème" settings decide (LOT-121): the accent of each variant and the dark-theme brightness. The app root
/// tints every screen with `accentColor`; the reader receives the same values through `readerScript`.
struct ThemeAppearance: Equatable, Sendable {
    /// Accent in the light theme (`theme_day_color_action`).
    var dayAccent: ThemeColor
    /// Accent in the dark theme (`theme_night_color_action`).
    var nightAccent: ThemeColor
    /// Multiplier of the dark surfaces' brightness, 0...`maximumDarkBrightness` (`theme_night_brightness`).
    var darkBrightness: Double
    /// How dark the dark surfaces are (`theme_dark_style`, LOT-122); the brightness multiplier applies on top of it.
    var darkStyle = DarkStyle.standard

    /// Legacy default accent hue, 190° (`AppSettingsView.swift:16`).
    static let defaultHue = 190.0 / 360.0
    /// Legacy default and top of the dark brightness slider (`AppSettingsView.swift:17-18`).
    static let defaultDarkBrightness = 1.0
    static let maximumDarkBrightness = 1.5
    /// The legacy defaults: hue 190°, brightness 100 %.
    static let standard = ThemeAppearance(
        dayAccent: dayTint(hue: defaultHue), nightAccent: nightTint(hue: defaultHue), darkBrightness: defaultDarkBrightness
    )

    /// The light-theme accent of `hue` (0...1): saturation 0.65, brightness 1 (`AppSettingsView.swift:328`).
    static func dayTint(hue: Double) -> ThemeColor { ThemeColor(hue: hue, saturation: 0.65, brightness: 1.0) }
    /// The dark-theme accent of `hue`: saturation 0.70, brightness 0.95 (`AppSettingsView.swift:329`).
    static func nightTint(hue: Double) -> ThemeColor { ThemeColor(hue: hue, saturation: 0.70, brightness: 0.95) }

    /// The accent of the current variant: the light accent in light mode, the dark one in dark mode.
    var accentColor: Color { Color(uiColor: accentUIColor) }

    /// `accentColor` as a dynamic UIKit colour (the window's tint), resolved per trait collection.
    var accentUIColor: UIColor {
        let day = dayAccent.uiColor
        let night = nightAccent.uiColor
        return UIColor { $0.userInterfaceStyle == .dark ? night : day }
    }

    /// `color` with its brightness scaled by `darkBrightness` above `minimumWhiteLevel` (0...255), as legacy scaled every
    /// dark surface (`ThemeUserColorStore.adjustedDarkThemeColor`, `Common.swift:607-643`). Black stays black at level 0.
    func adjustedDark(_ color: ThemeColor, minimumWhiteLevel: Double = 0) -> ThemeColor {
        let multiplier = min(max(darkBrightness, 0), Self.maximumDarkBrightness)
        let floor = min(max(minimumWhiteLevel / 255, 0), 1)
        let hsb = color.hsb
        let adjusted = min(max(multiplier * (hsb.brightness - floor) + floor, 0), 1)
        return ThemeColor(hue: hsb.hue, saturation: hsb.saturation, brightness: adjusted, alpha: color.alpha)
    }

    /// The reader's dark surfaces of `style` at brightness 100 %. `standard` is the `reader.css` dark palette (LOT-083), so the
    /// default is unchanged. These feed `reader.css`'s tokens: its message rule and alternate surface (#568) derive from the
    /// text colour and `--app-dark-background`, so there is no second separator spec here.
    static func readerDarkSurfaces(_ style: DarkStyle) -> [(variable: String, color: ThemeColor)] {
        let palette: [Int] = switch style {
        case .standard: [0x000000, 0x1C1C1E, 0x2C2C2E, 0x38383A]
        case .darker: [0x0B0B0C, 0x17181A, 0x232326, 0x2E2E31]
        case .oled: [0x000000, 0x111113, 0x1C1C1E, 0x38383A]
        }
        let names = ["--app-dark-background", "--app-dark-quote-background", "--app-dark-placeholder", "--app-dark-separator"]
        return zip(names, palette).map { ($0, ThemeColor(hex: $1)) }
    }

    /// The background of every screen in the dark theme, or nil for the system's (`standard`).
    var darkScreenBackground: ThemeColor? {
        switch darkStyle {
        case .standard: nil
        case .darker: ThemeColor(hex: 0x0B0B0C)
        case .oled: ThemeColor(hex: 0x000000)
        }
    }

    /// The CSS variables `reader.css` reads: both accents and the dark surfaces at `darkBrightness`.
    var readerVariables: [(name: String, value: String)] {
        [("--app-action-light", dayAccent.cssRGB), ("--app-action-dark", nightAccent.cssRGB)]
            + readerSurfaces.map { ($0.variable, $0.color.cssRGB) }
    }

    /// The reader's dark surfaces as the page shows them: the style's palette at `darkBrightness`, capped as `readerSurface` says.
    /// The settings preview draws from these, so it shows what the reader shows.
    var readerSurfaces: [(variable: String, color: ThemeColor)] {
        Self.readerDarkSurfaces(darkStyle).map { ($0.variable, readerSurface($0.variable, $0.color)) }
    }

    /// The reader page's background, for the web view's own layer (what shows while the page bounces past its ends): the system's
    /// in light, the page's `--app-dark-background` in dark.
    var readerBackground: UIColor {
        let dark = readerSurfaces.first { $0.variable == "--app-dark-background" }?.color.uiColor ?? .black
        return UIColor { $0.userInterfaceStyle == .dark ? dark : UIColor.systemBackground.resolvedColor(with: $0) }
    }

    /// The dark theme's text and secondary text (`reader.css` dark palette), which the contrast checks and the settings preview use.
    static let darkText = ThemeColor(hex: 0xF2F2F7)
    static let darkSecondaryText = ThemeColor(hex: 0xA1A1A6)

    /// A reader surface at `darkBrightness`. The darker and OLED styles never lift the page background above their own value:
    /// at 150 % the darker background (#0B0B0C) would put a continuation date (secondary text at 75 % opacity on the tinted
    /// header) under 4.5:1 (CodeRabbit on #589); the slider still darkens it, and still scales the other surfaces.
    private func readerSurface(_ variable: String, _ color: ThemeColor) -> ThemeColor {
        guard darkStyle != .standard, variable == "--app-dark-background", darkBrightness > 1 else { return adjustedDark(color) }
        var capped = self
        capped.darkBrightness = 1
        return capped.adjustedDark(color)
    }

    /// The script that sets `readerVariables` on the document's root element; every value is an `rgb()` the app formats from
    /// numbers, never page text.
    var readerScript: String {
        // Inside a function: the reader's world is shared by every user script, so nothing is declared at its top level.
        let lines = readerVariables.map { "s.setProperty('\($0.name)', '\($0.value)');" }
        return (["(() => { const s = document.documentElement.style;"] + lines + ["})();"]).joined(separator: " ")
    }
}

extension ThemeColor {
    /// A colour from hue, saturation and brightness in 0...1, as `UIColor(hue:saturation:brightness:alpha:)` builds it.
    init(hue: Double, saturation: Double, brightness: Double, alpha: Double = 1) {
        let hue = min(max(hue, 0), 1)
        let saturation = min(max(saturation, 0), 1)
        let brightness = min(max(brightness, 0), 1)
        let sector = (hue * 6).truncatingRemainder(dividingBy: 6)
        let fraction = sector - sector.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * fraction)
        let rising = brightness * (1 - saturation * (1 - fraction))
        switch Int(sector) {
        case 0: self.init(red: brightness, green: rising, blue: low, alpha: alpha)
        case 1: self.init(red: falling, green: brightness, blue: low, alpha: alpha)
        case 2: self.init(red: low, green: brightness, blue: rising, alpha: alpha)
        case 3: self.init(red: low, green: falling, blue: brightness, alpha: alpha)
        case 4: self.init(red: rising, green: low, blue: brightness, alpha: alpha)
        default: self.init(red: brightness, green: low, blue: falling, alpha: alpha)
        }
    }

    /// A colour from a 0xRRGGBB literal.
    init(hex: Int) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255
        )
    }

    /// Hue, saturation and brightness in 0...1.
    struct HSB: Equatable {
        /// Hue; a grey has hue 0.
        var hue: Double
        /// Saturation.
        var saturation: Double
        /// Brightness (the largest channel).
        var brightness: Double
    }

    /// Hue, saturation and brightness, as `UIColor.getHue` reads them.
    var hsb: HSB {
        let red = min(max(red, 0), 1), green = min(max(green, 0), 1), blue = min(max(blue, 0), 1)
        let maximum = max(red, green, blue)
        let delta = maximum - min(red, green, blue)
        guard maximum > 0, delta > 0 else { return HSB(hue: 0, saturation: 0, brightness: maximum) }
        var hue: Double = if maximum == red {
            (green - blue) / delta
        } else if maximum == green {
            2 + (blue - red) / delta
        } else {
            4 + (red - green) / delta
        }
        hue /= 6
        if hue < 0 { hue += 1 }
        return HSB(hue: hue, saturation: delta / maximum, brightness: maximum)
    }

    /// `rgb(r, g, b)` with integer channels, for the reader's CSS variables.
    var cssRGB: String {
        let channels = [red, green, blue].map { Int((min(max($0, 0), 1) * 255).rounded()) }
        return "rgb(\(channels[0]), \(channels[1]), \(channels[2]))"
    }

    /// WCAG 2 contrast ratio against `other`, 1...21.
    func contrast(with other: ThemeColor) -> Double {
        func luminance(_ color: ThemeColor) -> Double {
            func linear(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(color.red) + 0.7152 * linear(color.green) + 0.0722 * linear(color.blue)
        }
        let (lighter, darker) = (max(luminance(self), luminance(other)), min(luminance(self), luminance(other)))
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// The UIKit colour (sRGB).
    var uiColor: UIColor { UIColor(red: red, green: green, blue: blue, alpha: alpha) }
}

extension EnvironmentValues {
    /// The theme colours; the app root sets them from the "Thème" settings, the reader reads them.
    @Entry var themeAppearance = ThemeAppearance.standard
}
