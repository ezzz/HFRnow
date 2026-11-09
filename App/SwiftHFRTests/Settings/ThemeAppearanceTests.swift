import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The colour rules ported from legacy (LOT-121): the accent of a hue, the dark brightness formula and the reader's variables.
struct ThemeAppearanceTests {
    private func close(_ lhs: ThemeColor, _ rhs: ThemeColor, tolerance: Double = 0.002) -> Bool {
        abs(lhs.red - rhs.red) < tolerance && abs(lhs.green - rhs.green) < tolerance && abs(lhs.blue - rhs.blue) < tolerance
            && abs(lhs.alpha - rhs.alpha) < tolerance
    }

    @Test(arguments: [0.0, 0.1, 190.0 / 360.0, 0.33, 0.5, 0.66, 0.8, 0.999, 1.0])
    func hueColoursMatchUIKit(hue: Double) {
        for (saturation, brightness) in [(0.65, 1.0), (0.70, 0.95), (0.3, 0.2)] {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1)
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            let ours = ThemeColor(hue: hue, saturation: saturation, brightness: brightness)
            #expect(close(ours, ThemeColor(red: red, green: green, blue: blue, alpha: alpha)), "\(hue) \(saturation) \(brightness)")
            // And back: the slider shows the hue it wrote (1 and 0 are the same hue).
            #expect(abs(ours.hsb.hue - hue.truncatingRemainder(dividingBy: 1)) < 0.001)
        }
    }

    @Test func theDefaultAccentIsTheLegacyCyan() {
        // UIColor(hue: 190/360, saturation: 0.65, brightness: 1) and (…, 0.70, 0.95): `Common.swift:514-520` at 21173e77.
        #expect(ThemeAppearance.standard.dayAccent.cssRGB == "rgb(89, 227, 255)")
        #expect(ThemeAppearance.standard.nightAccent.cssRGB == "rgb(73, 214, 242)")
    }

    @Test func darkBrightnessScalesAboveTheMinimumAsLegacyDid() {
        let grey = ThemeColor(hex: 0x1C1C1E)
        var appearance = ThemeAppearance.standard
        #expect(close(appearance.adjustedDark(grey), grey))
        appearance.darkBrightness = 0
        #expect(appearance.adjustedDark(grey).hsb.brightness == 0)
        // With a floor of 20/255 the colour goes down to the floor, not to black (`withMin:20.0`, ThemeColors.m:512).
        #expect(abs(appearance.adjustedDark(grey, minimumWhiteLevel: 20).hsb.brightness - 20.0 / 255) < 1e-9)
        appearance.darkBrightness = 1.5
        #expect(abs(appearance.adjustedDark(grey).hsb.brightness - 1.5 * grey.hsb.brightness) < 1e-9)
        // Capped at 1.5, as the slider.
        appearance.darkBrightness = 3
        #expect(abs(appearance.adjustedDark(grey).hsb.brightness - 1.5 * grey.hsb.brightness) < 1e-9)
    }

    @Test func theReaderGetsBothAccentsAndTheScaledDarkSurfaces() {
        var appearance = ThemeAppearance.standard
        appearance.darkBrightness = 1.5
        let variables = Dictionary(uniqueKeysWithValues: appearance.readerVariables.map { ($0.name, $0.value) })
        #expect(variables["--app-action-light"] == "rgb(89, 227, 255)")
        #expect(variables["--app-action-dark"] == "rgb(73, 214, 242)")
        #expect(variables["--app-dark-background"] == "rgb(0, 0, 0)")
        // 0x1C1C1E: brightness 30/255 × 1.5 = 45/255.
        #expect(variables["--app-dark-quote-background"] == "rgb(42, 42, 45)")
        #expect(variables.count == 6)
    }

    @Test func theReaderScriptOnlyEverWritesFormattedColours() {
        let script = ThemeAppearance.standard.readerScript
        // A function run at once: nothing declared at the top level of the shared reader world.
        #expect(script.hasPrefix("(() => { const s = document.documentElement.style; "))
        #expect(script.hasSuffix(" })();"))
        #expect(script.contains("s.setProperty('--app-action-light', 'rgb(89, 227, 255)');"))
        // Nothing but the six setters between the prefix and the closing: no page text can reach it.
        let setters = script.split(separator: ";").dropFirst().dropLast()
        #expect(setters.count == 6)
        #expect(setters.allSatisfy { $0.contains("s.setProperty('--app-") && $0.contains("'rgb(") })
    }

    @Test @MainActor func theNativeAccentFollowsTheVariant() {
        let appearance = ThemeAppearance(
            dayAccent: ThemeColor(red: 1, green: 0, blue: 0), nightAccent: ThemeColor(red: 0, green: 0, blue: 1), darkBrightness: 1
        )
        let color = UIColor(appearance.accentColor)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(red > 0.99 && blue < 0.01)
        color.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark)).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        #expect(blue > 0.99 && red < 0.01)
    }

    @Test func theStandardStyleKeepsTheReaderDarkPalette() {
        let variables = Dictionary(uniqueKeysWithValues: ThemeAppearance.standard.readerVariables.map { ($0.name, $0.value) })
        #expect(variables["--app-dark-background"] == "rgb(0, 0, 0)")
        #expect(variables["--app-dark-quote-background"] == "rgb(28, 28, 30)")
        #expect(variables["--app-dark-placeholder"] == "rgb(44, 44, 46)")
        #expect(variables["--app-dark-separator"] == "rgb(56, 56, 58)")
        #expect(ThemeAppearance.standard.darkScreenBackground == nil)
    }

    @Test func theDarkerAndOLEDStylesSetTheScreenAndTheReaderSurfaces() {
        var appearance = ThemeAppearance.standard
        appearance.darkStyle = .darker
        #expect(appearance.darkScreenBackground?.cssRGB == "rgb(11, 11, 12)")
        #expect(Dictionary(uniqueKeysWithValues: appearance.readerVariables.map { ($0.name, $0.value) })["--app-dark-background"]
            == "rgb(11, 11, 12)")
        appearance.darkStyle = .oled
        #expect(appearance.darkScreenBackground?.cssRGB == "rgb(0, 0, 0)")
        // The brightness slider still scales the chosen surfaces: 0 % is black in every style.
        appearance.darkStyle = .darker
        appearance.darkBrightness = 0
        let variables = Dictionary(uniqueKeysWithValues: appearance.readerVariables.map { ($0.name, $0.value) })
        #expect(variables["--app-dark-background"] == "rgb(0, 0, 0)")
    }

    /// Acceptance criterion of #213: text, secondary text and the default night accent are at least 4.5:1 on every surface of the
    /// dark styles as the reader shows them (`readerSurfaces`), at 100 % and, for darker and OLED, at every brightness up to 150 %.
    /// Standard above 100 % is LOT-121's slider (the legacy surfaces scaled up), not claimed here.
    @Test(arguments: [
        (DarkStyle.standard, 1.0), (.darker, 1.0), (.darker, 1.25), (.darker, 1.5), (.oled, 1.0), (.oled, 1.25), (.oled, 1.5)
    ])
    func textHasAtLeast4_5ToOneOnEveryDarkSurface(style: DarkStyle, brightness: Double) {
        var appearance = ThemeAppearance.standard
        appearance.darkStyle = style
        appearance.darkBrightness = brightness
        for surface in appearance.readerSurfaces where surface.variable != "--app-dark-separator" {
            let name = "\(style) at \(brightness) on \(surface.variable)"
            #expect(ThemeAppearance.darkText.contrast(with: surface.color) >= 4.5, "text, \(name)")
            #expect(ThemeAppearance.darkSecondaryText.contrast(with: surface.color) >= 4.5, "secondary, \(name)")
            #expect(appearance.nightAccent.contrast(with: surface.color) >= 4.5, "accent, \(name)")
        }
    }

    /// Light: --text #1c1c1e and --secondary #6c6c70 on --background #ffffff and the quote #f2f2f7 of reader.css.
    @Test func lightTextHasAtLeast4_5ToOne() {
        for light in [ThemeColor(hex: 0xFFFFFF), ThemeColor(hex: 0xF2F2F7)] {
            #expect(ThemeColor(hex: 0x1C1C1E).contrast(with: light) >= 4.5)
            #expect(ThemeColor(hex: 0x6C6C70).contrast(with: light) >= 4.5)
        }
    }

    /// The reader's text colours are the ones `reader.css` sets, which the contrast checks and the preview use.
    @Test func theTextConstantsAreReaderCSSs() throws {
        let url = try #require(Bundle.main.url(forResource: "reader", withExtension: "css"))
        let css = try String(contentsOf: url, encoding: .utf8)
        #expect(css.contains("--text: #f2f2f7;") && css.contains("--secondary: #a1a1a6;"))
        #expect(ThemeAppearance.darkText.cssRGB == "rgb(242, 242, 247)" && ThemeAppearance.darkSecondaryText.cssRGB == "rgb(161, 161, 166)")
    }

    /// The preview and the reader draw the same surfaces: at 150 % the darker background is capped at its own value.
    @Test func theReaderSurfacesAreWhatTheReaderReceives() {
        var appearance = ThemeAppearance.standard
        appearance.darkStyle = .darker
        appearance.darkBrightness = 1.5
        let surfaces = appearance.readerSurfaces
        let background = surfaces.first { $0.variable == "--app-dark-background" }?.color.cssRGB
        #expect(background == "rgb(11, 11, 12)", "capped: \(String(describing: background))")
        let variables = Dictionary(uniqueKeysWithValues: appearance.readerVariables.map { ($0.name, $0.value) })
        #expect(surfaces.allSatisfy { variables[$0.variable] == $0.color.cssRGB })
    }

    @Test func contrastMatchesWCAGReferenceValues() {
        #expect(abs(ThemeColor(hex: 0x000000).contrast(with: ThemeColor(hex: 0xFFFFFF)) - 21) < 1e-9)
        #expect(abs(ThemeColor(hex: 0x777777).contrast(with: ThemeColor(hex: 0xFFFFFF)) - 4.48) < 0.01)
    }

    /// A continuation message is drawn at 75 % opacity over the page (`.continuation`), its header tinted with 3 % of the accent:
    /// its date, `--secondary` text, keeps 4.5:1 on that header at every brightness (CodeRabbit on #589 measured 4.46:1 at 150 %).
    @Test(arguments: DarkStyle.allCases, [0.0, 0.5, 1.0, 1.25, 1.5])
    func aContinuationDateKeepsItsContrastAtEveryBrightness(style: DarkStyle, brightness: Double) throws {
        var appearance = ThemeAppearance.standard
        appearance.darkStyle = style
        appearance.darkBrightness = brightness
        let value = try #require(appearance.readerVariables.first { $0.name == "--app-dark-background" }?.value)
        let channels = value.dropFirst(4).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        func mix(_ lhs: [Double], _ rhs: [Double], _ weight: Double) -> [Double] { zip(lhs, rhs).map { $0 * (1 - weight) + $1 * weight } }
        func colour(_ rgb: [Double]) -> ThemeColor { ThemeColor(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255) }
        let accent = [appearance.nightAccent.red, appearance.nightAccent.green, appearance.nightAccent.blue].map { $0 * 255 }
        let header = mix(channels, accent, 0.03)
        // Opacity 0.75 blends the header and the text toward the page behind them.
        let shownHeader = mix(channels, header, 0.75)
        let shownText = mix(channels, [161, 161, 166], 0.75)
        #expect(colour(shownText).contrast(with: colour(shownHeader)) >= 4.5, "\(style) at \(brightness): \(channels)")
    }

    /// #577 draws even messages on `--surface-alt` (text over the background, 9 % in dark) and their quotes on `--placeholder`:
    /// the secondary text keeps 4.5:1 on both, in the darker and OLED styles at every brightness.
    @Test(arguments: [DarkStyle.darker, .oled], [0.0, 0.5, 1.0, 1.5])
    func secondaryTextHoldsOnTheAlternateSurfaceAndOnQuotes(style: DarkStyle, brightness: Double) throws {
        var appearance = ThemeAppearance.standard
        appearance.darkStyle = style
        appearance.darkBrightness = brightness
        func channels(_ name: String) throws -> [Double] {
            let value = try #require(appearance.readerVariables.first { $0.name == name }?.value)
            return value.dropFirst(4).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        }
        func colour(_ rgb: [Double]) -> ThemeColor { ThemeColor(red: rgb[0] / 255, green: rgb[1] / 255, blue: rgb[2] / 255) }
        let secondary = ThemeAppearance.darkSecondaryText
        let background = try channels("--app-dark-background")
        let alternate = zip(background, [242.0, 242, 247]).map { $0 * 0.91 + $1 * 0.09 }
        #expect(secondary.contrast(with: colour(alternate)) >= 4.5, "\(style) at \(brightness): alternate surface")
        let placeholder = try channels("--app-dark-placeholder")
        #expect(secondary.contrast(with: colour(placeholder)) >= 4.5, "\(style) at \(brightness): quote surface")
    }
}
