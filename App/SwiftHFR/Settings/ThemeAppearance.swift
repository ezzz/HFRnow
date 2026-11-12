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
    /// The colours of the gallery's theme (LOT-188), or nil for Legacy: the values above, today's app, untouched. A theme's
    /// tokens replace the accent, the screen background and the reader's palette; the hue, style and brightness above then only
    /// feed what the theme does not define (the reader's `--app-dark-*` surfaces, which its own palette covers).
    var themeVariants: ThemeDefinition.Variants?
    /// The theme's text design (LOT-188); `.default` for Legacy.
    var themeFontDesign = ThemeDefinition.FontDesign.default

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

    /// `accentColor` as a dynamic UIKit colour (the window's tint), resolved per trait collection. A theme tints with its
    /// `accentText`: SwiftUI's one tint colours text and glyphs (buttons, links), which THEMES.md §3 holds to 4.5:1 on `surface`;
    /// its `accent` (fills) is read from the tokens by the views that fill (`BadgeCapsule` reads `unread`).
    var accentUIColor: UIColor {
        if let themeVariants { return Self.dynamic(light: themeVariants.light.accentText, dark: themeVariants.dark.accentText) }
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

    /// A colour that resolves to `light` or `dark` with the trait collection's style.
    static func dynamic(light: ThemeRGB, dark: ThemeRGB) -> UIColor {
        let (light, dark) = (ThemeColor(rgb: light).uiColor, ThemeColor(rgb: dark).uiColor)
        return UIColor { $0.userInterfaceStyle == .dark ? dark : light }
    }

    /// The colour of a token, per appearance, or nil for Legacy.
    func themeColor(_ token: KeyPath<ThemeTokens, ThemeRGB>) -> UIColor? {
        themeVariants.map { Self.dynamic(light: $0.light[keyPath: token], dark: $0.dark[keyPath: token]) }
    }

    /// The appearance a single-variant theme imposes (« clair = sombre »: the system's text and chrome must match its one
    /// palette), or nil: Legacy and two-variant themes follow the "Thème" picker.
    var forcedColorScheme: ColorScheme? {
        guard case let .single(tokens)? = themeVariants else { return nil }
        return tokens.isLight ? .light : .dark
    }

    /// The text design of every screen, or nil to leave the system's (Legacy, and themes asking for `default`).
    var fontDesign: Font.Design? {
        guard themeVariants != nil else { return nil }
        return switch themeFontDesign {
        case .default: nil
        case .rounded: .rounded
        case .monospaced: .monospaced
        }
    }

    /// What paints behind every screen (`appScreenBackground()`). The case decides the view structure: only a change of theme
    /// or of dark style changes it, never an appearance flip (LOT-122: one structure per appearance).
    enum ScreenFill: Equatable {
        /// The system's, untouched: Legacy in the standard style.
        case system
        /// Legacy's darker and OLED styles: this colour in dark, the system's in light.
        case darkOnly(ThemeColor)
        /// A theme's `background`, in both appearances (a dynamic colour).
        case theme(light: ThemeRGB, dark: ThemeRGB)
    }

    /// The screen fill of the current theme and style.
    var screenFill: ScreenFill {
        if let themeVariants { return .theme(light: themeVariants.light.background, dark: themeVariants.dark.background) }
        return darkScreenBackground.map(ScreenFill.darkOnly) ?? .system
    }

    /// The background of every screen in the dark theme, or nil for the system's (`standard`).
    var darkScreenBackground: ThemeColor? {
        switch darkStyle {
        case .standard: nil
        case .darker: ThemeColor(hex: 0x0B0B0C)
        case .oled: ThemeColor(hex: 0x000000)
        }
    }

    /// The CSS variables `reader.css` reads: both accents and the dark surfaces at `darkBrightness`; with a theme, its tokens
    /// for both appearances too (`--app-theme-light-*`, `--app-theme-dark-*`), which `reader.css` reads only while `<html>`
    /// carries `data-app-theme` (`readerScript`), so Legacy's page is today's.
    var readerVariables: [(name: String, value: String)] {
        [("--app-action-light", dayAccent.cssRGB), ("--app-action-dark", nightAccent.cssRGB)]
            + readerSurfaces.map { ($0.variable, $0.color.cssRGB) }
            + readerThemeVariables
    }

    /// The reader's text family for the theme's design (`--app-theme-font`), or nil for the page's own; app constants, never
    /// page text. `[code]` keeps its monospace rule.
    var readerFontFamily: String? {
        switch fontDesign {
        case .rounded?: "ui-rounded, -apple-system, sans-serif"
        case .monospaced?: "ui-monospace, Menlo, monospace"
        default: nil
        }
    }

    /// The reader's variable of each token (`reader.css`, theme block). The page is the theme's `surface` (the reader is a
    /// list of messages, the rows and cards of THEMES.md §3, where its text rules hold); placeholders sit on `quoteBackground`.
    static let readerTokens: [(name: String, token: KeyPath<ThemeTokens, ThemeRGB> & Sendable)] = [
        ("text", \.textPrimary), ("secondary", \.textSecondary), ("background", \.surface), ("separator", \.separator),
        ("quote-border", \.quoteBorder), ("quote-background", \.quoteBackground), ("placeholder", \.quoteBackground),
        ("action", \.accentText), ("link", \.link), ("code-background", \.codeBackground), ("code-text", \.codeText),
        ("spoiler-background", \.spoilerBackground), ("spoiler-text", \.spoilerText)
    ]

    private var readerThemeVariables: [(name: String, value: String)] {
        guard let themeVariants else { return [] }
        return [("light", themeVariants.light), ("dark", themeVariants.dark)].flatMap { variant, tokens in
            Self.readerTokens.map { (name: "--app-theme-\(variant)-\($0.name)", value: ThemeColor(rgb: tokens[keyPath: $0.token]).cssRGB) }
        }
    }

    /// The reader's dark surfaces as the page shows them: the style's palette at `darkBrightness`, capped as `readerSurface` says.
    /// The settings preview draws from these, so it shows what the reader shows.
    var readerSurfaces: [(variable: String, color: ThemeColor)] {
        Self.readerDarkSurfaces(darkStyle).map { ($0.variable, readerSurface($0.variable, $0.color)) }
    }

    /// The reader page's background, for the web view's own layer (what shows while the page bounces past its ends): the system's
    /// in light, the page's `--app-dark-background` in dark.
    var readerBackground: UIColor {
        if let surface = themeColor(\.surface) { return surface }
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

    /// The script that sets `readerVariables` on the document's root element, then sets `data-app-theme` on it with a theme or
    /// removes it for Legacy (a live switch back); every value is an `rgb()` the app formats from numbers, never page text.
    var readerScript: String {
        // Inside a function: the reader's world is shared by every user script, so nothing is declared at its top level.
        let lines = readerVariables.map { "s.setProperty('\($0.name)', '\($0.value)');" }
        guard themeVariants != nil else {
            let flag = "document.documentElement.removeAttribute('data-app-theme');"
            return (["(() => { const s = document.documentElement.style;"] + lines + [flag, "})();"]).joined(separator: " ")
        }
        let font = readerFontFamily.map { "s.setProperty('--app-theme-font', '\($0)');" } ?? "s.removeProperty('--app-theme-font');"
        let flag = "document.documentElement.setAttribute('data-app-theme', '');"
        return (["(() => { const s = document.documentElement.style;"] + lines + [font, flag, "})();"]).joined(separator: " ")
    }
}

extension ThemeColor {
    /// The colour of a theme token (LOT-188).
    init(rgb: ThemeRGB) {
        self.init(
            red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255, alpha: Double(rgb.alpha) / 255
        )
    }

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

extension View {
    /// `.buttonStyle(.borderedProminent)` for Legacy, as before; under a gallery theme (LOT-188), a capsule filled with its
    /// `accent` and labelled in its `onAccent` (`ThemedProminentButtonStyle`). The app's tint is the theme's `accentText`, a text
    /// colour, on which the system style's own white label need not be legible.
    func appProminentButtonStyle() -> some View { modifier(AppProminentButtonStyle()) }
}

private struct AppProminentButtonStyle: ViewModifier {
    @Environment(\.themeAppearance) private var appearance

    @ViewBuilder func body(content: Content) -> some View {
        if let fill = appearance.themeColor(\.accent), let label = appearance.themeColor(\.onAccent) {
            content.buttonStyle(ThemedProminentButtonStyle(fill: Color(uiColor: fill), label: Color(uiColor: label)))
        } else {
            content.buttonStyle(.borderedProminent)
        }
    }
}

/// A prominent button that draws its own fill and label colours, so neither depends on how the system style orders them.
struct ThemedProminentButtonStyle: ButtonStyle {
    let fill: Color
    let label: Color
    @Environment(\.isEnabled) private var isEnabled
    @ScaledMetric(relativeTo: .body) private var horizontal = 14.0
    @ScaledMetric(relativeTo: .body) private var vertical = 7.0

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundStyle(label)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(fill, in: Capsule())
            .opacity(isEnabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
            .contentShape(Capsule())
    }
}
