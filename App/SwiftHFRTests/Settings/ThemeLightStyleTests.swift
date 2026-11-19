import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing

/// #1213: the light style, « Blanc » (today's look, unchanged) or « Doux » (warm, low glare), and the « Thème » tiles.
@MainActor
struct ThemeLightStyleTests {
    private func variables(_ appearance: ThemeAppearance) -> [String: String] {
        Dictionary(uniqueKeysWithValues: appearance.readerVariables.map { ($0.name, $0.value) })
    }

    private var doux: ThemeAppearance {
        var appearance = ThemeAppearance.standard
        appearance.lightStyle = .doux
        return appearance
    }

    // MARK: Blanc is today's look

    /// « Blanc » sends nothing new to the reader and paints nothing on the screens: the light look of today, byte for byte.
    @Test func blancAddsNoVariableNoScreenFillAndNoLightSurface() {
        let blanc = ThemeAppearance.standard
        #expect(blanc.lightStyle == .blanc)
        #expect(blanc.lightSurfaces.isEmpty)
        #expect(blanc.lightScreenBackground == nil)
        #expect(blanc.screenFill == .system)
        #expect(variables(blanc).keys.allSatisfy { !$0.hasPrefix("--app-light-") })
        #expect(variables(blanc).count == 6)
    }

    // MARK: Doux

    /// The proposed values (validated by the operator on the PR's screenshot): an off-white page, a placeholder step darker, a warmer
    /// quiet separator, and a secondary text a notch darker so it keeps its contrast on the warm surfaces. The default quote has no
    /// fill (#819), so no quote surface is sent.
    @Test func douxSendsItsWarmSurfacesToTheReader() {
        let sent = variables(doux)
        #expect(sent["--app-light-background"] == "rgb(245, 244, 239)")
        #expect(sent["--app-light-placeholder"] == "rgb(233, 231, 222)")
        #expect(sent["--app-light-separator"] == "rgb(214, 211, 200)")
        #expect(sent["--app-light-secondary"] == "rgb(99, 99, 102)")
        #expect(sent.count == 10)
    }

    /// Text (#1C1C1E) and the secondary text of Doux keep 4.5:1 on every Doux surface that carries text, and on the tints the
    /// reader lays over the page (the folded quote's 5 % of the text colour, the classic header's 15 % of the accent).
    @Test func textAndSecondaryTextKeepTheirContrastOnDoux() {
        let text = ThemeColor(hex: 0x1C1C1E)
        let secondary = ThemeColor(hex: 0x636366)
        let surfaces = Dictionary(uniqueKeysWithValues: doux.lightSurfaces.map { ($0.variable, $0.color) })
        for name in ["--app-light-background", "--app-light-placeholder"] {
            let surface = surfaces[name] ?? ThemeColor(hex: 0)
            #expect(text.contrast(with: surface) >= 4.5, "text on \(name)")
            #expect(secondary.contrast(with: surface) >= 4.5, "secondary on \(name)")
        }
        let page = surfaces["--app-light-background"] ?? ThemeColor(hex: 0)
        func over(_ tint: ThemeColor, _ weight: Double) -> ThemeColor {
            ThemeColor(
                red: page.red * (1 - weight) + tint.red * weight, green: page.green * (1 - weight) + tint.green * weight,
                blue: page.blue * (1 - weight) + tint.blue * weight
            )
        }
        #expect(secondary.contrast(with: over(text, 0.05)) >= 4.5, "folded quote")
        #expect(secondary.contrast(with: over(ThemeAppearance.standard.dayAccent, 0.15)) >= 4.5, "classic header")
        #expect(secondary.contrast(with: over(ThemeAppearance.standard.dayAccent, 0.03)) >= 4.5, "modern header")
    }

    /// The native screens follow: Doux paints its page in light and leaves dark to the dark style (the system's in the standard one).
    @Test func douxPaintsTheScreensInLightOnly() {
        #expect(doux.lightScreenBackground?.cssRGB == "rgb(245, 244, 239)")
        #expect(doux.screenFill == .softLight(light: ThemeColor(hex: 0xF5F4EF), dark: nil))
        var withOLED = doux
        withOLED.darkStyle = .oled
        #expect(withOLED.screenFill == .softLight(light: ThemeColor(hex: 0xF5F4EF), dark: ThemeColor(hex: 0)))
        // Blanc keeps the dark styles' fill exactly as before.
        var blancOLED = ThemeAppearance.standard
        blancOLED.darkStyle = .oled
        #expect(blancOLED.screenFill == .darkOnly(ThemeColor(hex: 0)))
    }

    /// A gallery theme has its own palette: Doux is ignored there, like the dark style.
    @Test func aGalleryThemeIgnoresTheLightStyle() throws {
        let theme = try #require(ThemeCatalog.bundled.themes.first { !$0.isLegacy })
        var appearance = doux
        appearance.themeVariants = theme.variants
        #expect(appearance.lightScreenBackground != nil) // the style is still stored…
        if case .theme = appearance.screenFill {} else { Issue.record("…but the theme's fill wins: \(appearance.screenFill)") }
    }

    /// The reader's script sets Doux's variables, and takes them back off for Blanc (a live switch back).
    @Test func theReaderScriptSetsDouxAndRemovesItForBlanc() {
        #expect(doux.readerScript.contains("s.setProperty('--app-light-background', 'rgb(245, 244, 239)');"))
        let blanc = ThemeAppearance.standard.readerScript
        for name in ["background", "placeholder", "separator", "secondary"] {
            #expect(blanc.contains("s.removeProperty('--app-light-\(name)');"), "\(name)")
        }
        #expect(!blanc.contains("setProperty('--app-light-"))
    }

    // MARK: The setting

    @Test func theLightStyleDefaultsToBlancPersistsAndFeedsTheAppearance() {
        let store = InMemorySettingsStore()
        let model = ThemeSettingsModel(store: store)
        #expect(model.lightStyle == .blanc)
        #expect(model.appearance.lightStyle == .blanc)
        #expect(store.rawValue(forKey: "theme_light_style") == nil)
        model.lightStyle = .doux
        #expect(store.value(for: SettingKey.lightStyle) == .doux)
        #expect(model.appearance.lightStyle == .doux)
        #expect(ThemeSettingsModel(store: store).lightStyle == .doux)
    }

    @Test func anUnknownStoredLightStyleReadsAsBlanc() {
        let model = ThemeSettingsModel(store: InMemorySettingsStore(["theme_light_style": .int(9)]))
        #expect(model.lightStyle == .blanc)
    }

    // MARK: The controls follow « Thème »

    @Test func eachModeShowsOnlyItsOwnControls() {
        #expect(ThemeSettingsModel.Mode.light.controls == [.lightStyle])
        #expect(ThemeSettingsModel.Mode.dark.controls == [.darkStyle, .darkBrightness])
        #expect(ThemeSettingsModel.Mode.system.controls == [.lightStyle, .darkStyle, .darkBrightness])
    }

    // MARK: The tiles

    /// Choosing a tile sets the mode, which the model stores under the legacy appearance keys; the tiles come in the order the
    /// screen shows them.
    @Test func choosingATileSetsTheModeAndTheStoredSetting() {
        #expect(ThemeModeTiles.order == [.light, .dark, .system])
        let store = InMemorySettingsStore()
        let model = ThemeSettingsModel(store: store)
        var chosen = model.mode
        let binding = Binding(get: { chosen }, set: { chosen = $0; model.mode = $0 })
        ThemeModeTiles.select(.dark, in: binding)
        #expect(chosen == .dark && model.mode == .dark)
        #expect(store.value(for: SettingKey.autoTheme) == .manual && store.value(for: SettingKey.manualTheme) == .dark)
        ThemeModeTiles.select(.system, in: binding)
        #expect(store.value(for: SettingKey.autoTheme) == .system)
    }

    @Test func theTilesAreLabelledForVoiceOver() {
        #expect(ThemeSettingsModel.Mode.allCases.map(\.tileTitle) == ["Système", "Clair", "Sombre"])
        #expect(ThemeSettingsModel.Mode.allCases.map(\.tileAccessibilityLabel) == ["Thème du système", "Thème clair", "Thème sombre"])
    }

    /// The tiles draw the surfaces the reader shows: the light one the light style's page, the dark one the dark style's page at
    /// the chosen brightness, and each dot is that variant's accent (so it follows the hue slider).
    @Test func theTilesDrawTheSurfacesTheReaderShowsAndTheChosenAccent() {
        let blanc = ThemeAppearance.standard
        #expect(blanc.tileLook(dark: false).surface == ThemeColor(hex: 0xFFFFFF))
        #expect(doux.tileLook(dark: false).surface == ThemeColor(hex: 0xF5F4EF))
        #expect(blanc.tileLook(dark: false).dot == blanc.dayAccent)
        #expect(blanc.tileLook(dark: true).dot == blanc.nightAccent)
        var dark = ThemeAppearance.standard
        for style in DarkStyle.allCases {
            dark.darkStyle = style
            let page = dark.readerSurfaces.first { $0.variable == "--app-dark-background" }?.color
            #expect(dark.tileLook(dark: true).surface == page, "\(style)")
        }
        dark.darkStyle = .standard
        dark.darkBrightness = 0
        #expect(dark.tileLook(dark: true).surface == ThemeColor(hex: 0))
        let red = ThemeAppearance(
            dayAccent: ThemeAppearance.dayTint(hue: 0), nightAccent: ThemeAppearance.nightTint(hue: 0), darkBrightness: 1
        )
        #expect(red.tileLook(dark: false).dot == ThemeAppearance.dayTint(hue: 0))
        #expect(red.tileLook(dark: true).dot == ThemeAppearance.nightTint(hue: 0))
    }

    /// A gallery theme draws its own tokens in the tiles.
    @Test func aGalleryThemeDrawsItsOwnTokensInTheTiles() throws {
        let theme = try #require(ThemeCatalog.bundled.themes.first { !$0.isLegacy })
        var appearance = ThemeAppearance.standard
        appearance.themeVariants = theme.variants
        let variants = try #require(theme.variants)
        #expect(appearance.tileLook(dark: false).surface == ThemeColor(rgb: variants.light.surface))
        #expect(appearance.tileLook(dark: true).surface == ThemeColor(rgb: variants.dark.surface))
    }
}
