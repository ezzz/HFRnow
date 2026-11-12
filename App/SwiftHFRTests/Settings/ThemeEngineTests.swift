import HFRModels
import HFRStorage
@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// The theme engine (LOT-188): the stored theme, what Legacy leaves untouched, what a theme's tokens reach.
@MainActor
struct ThemeEngineTests {
    // MARK: Stored theme

    @Test func anEmptyStoreIsLegacyAndCreatingTheModelWritesNothing() throws {
        let store = InMemorySettingsStore()
        let model = ThemeSettingsModel(store: store, catalog: try ThemeFixtures.catalog())
        #expect(model.theme.isLegacy && model.themeID == nil)
        #expect(model.appearance == .standard)
        #expect(store.rawValue(forKey: "theme_id") == nil)
    }

    @Test func aSelectedThemeIsStoredAndSurvivesARelaunch() throws {
        let catalog = try ThemeFixtures.catalog()
        let store = InMemorySettingsStore()
        let model = ThemeSettingsModel(store: store, catalog: catalog)
        let theme = try #require(catalog.themes.first { $0.id == "test-theme" })
        model.select(theme)
        #expect(store.rawValue(forKey: "theme_id") == .string("test-theme"))
        #expect(ThemeSettingsModel(store: store, catalog: catalog).theme.id == "test-theme")
        model.select(catalog.themes[0])
        #expect(store.rawValue(forKey: "theme_id") == .string("legacy"))
        #expect(ThemeSettingsModel(store: store, catalog: catalog).appearance == .standard)
    }

    /// A theme a later version added, then removed, or a typo: Legacy is shown, and the stored id is left alone.
    @Test func anUnknownIDReadsAsLegacyAndStaysInTheStore() throws {
        let store = InMemorySettingsStore(["theme_id": .string("from-a-later-version")])
        let model = ThemeSettingsModel(store: store, catalog: try ThemeFixtures.catalog())
        #expect(model.theme.isLegacy && model.appearance == .standard)
        model.mode = .dark
        model.accentHue = 0.5
        #expect(store.rawValue(forKey: "theme_id") == .string("from-a-later-version"))
    }

    // MARK: Legacy is today's app

    /// Legacy overrides nothing: no tokens, no design, no forced scheme, the screen fill of its style, the reader's page unflagged.
    @Test func legacyChangesNothing() {
        let standard = ThemeAppearance.standard
        #expect(standard.themeVariants == nil && standard.fontDesign == nil && standard.forcedColorScheme == nil)
        #expect(standard.screenFill == .system)
        var darker = standard
        darker.darkStyle = .darker
        #expect(darker.screenFill == .darkOnly(ThemeColor(hex: 0x0B0B0C)))
        #expect(standard.readerVariables.allSatisfy { !$0.name.hasPrefix("--app-theme-") })
        #expect(standard.readerScript.contains("removeAttribute('data-app-theme')"))
        #expect(!standard.readerScript.contains("setAttribute"))
    }

    // MARK: A theme's tokens

    @Test func aThemeReachesTheTintTheScreenTheFontAndTheReader() throws {
        let catalog = try ThemeFixtures.catalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.select(try #require(catalog.themes.first { $0.id == "test-theme" }))
        let appearance = model.appearance
        #expect(appearance.fontDesign == .rounded && appearance.forcedColorScheme == nil)
        let fill = ThemeAppearance.ScreenFill.theme(
            light: try #require(ThemeRGB(hex: "#E6EEF8")), dark: try #require(ThemeRGB(hex: "#101820"))
        )
        #expect(appearance.screenFill == fill)
        // The tint is the accent as text (accentText): #0057B8 light, #FFC040 dark.
        func rgb(_ color: UIColor, dark: Bool) -> [Int] {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.resolvedColor(with: UITraitCollection(userInterfaceStyle: dark ? .dark : .light))
                .getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return [red, green, blue].map { Int(($0 * 255).rounded()) }
        }
        #expect(rgb(appearance.accentUIColor, dark: false) == [0x00, 0x57, 0xB8])
        #expect(rgb(appearance.accentUIColor, dark: true) == [0xFF, 0xC0, 0x40])
        #expect(rgb(appearance.readerBackground, dark: true) == [0x1A, 0x24, 0x30])
        let variables = Dictionary(uniqueKeysWithValues: appearance.readerVariables.map { ($0.name, $0.value) })
        #expect(variables["--app-theme-light-background"] == "rgb(255, 255, 255)")
        #expect(variables["--app-theme-dark-background"] == "rgb(26, 36, 48)")
        #expect(variables["--app-theme-dark-link"] == "rgb(140, 200, 255)")
        #expect(variables.count == 6 + 2 * ThemeAppearance.readerTokens.count)
        #expect(appearance.readerScript.contains("setAttribute('data-app-theme', '')"))
        // The design reaches the reader too (Fable round 1): the rounded system family.
        #expect(appearance.readerScript.contains("s.setProperty('--app-theme-font', 'ui-rounded, -apple-system, sans-serif');"))
        #expect(!appearance.readerScript.contains("removeAttribute"))
    }

    /// Every variable the app sets is one `reader.css` reads in its theme block, for both appearances, and the reverse.
    @Test func theReaderStylesheetReadsEveryThemeVariable() throws {
        let url = try #require(Bundle.main.url(forResource: "reader", withExtension: "css"))
        let css = try String(contentsOf: url, encoding: .utf8)
        let read = Set(css.matches(of: /var\((--app-theme-(?:light|dark)-[a-z-]+)\)/).map { String($0.output.1) })
        let set = Set(["light", "dark"].flatMap { variant in ThemeAppearance.readerTokens.map { "--app-theme-\(variant)-\($0.name)" } })
        #expect(read == set)
        #expect(css.contains("font-family: var(--app-theme-font);"))
    }

    @Test func aSingleVariantThemeImposesItsAppearance() throws {
        let catalog = try ThemeFixtures.singleVariantCatalog()
        let model = ThemeSettingsModel(store: InMemorySettingsStore(), catalog: catalog)
        model.mode = .light
        model.select(try #require(catalog.themes.first { $0.id == "single-theme" }))
        // Its one variant is the test theme's dark one: the app is dark whatever the picker says.
        #expect(model.appearance.forcedColorScheme == .dark && model.preferredColorScheme == .dark)
        model.select(catalog.themes[0])
        #expect(model.preferredColorScheme == .light)
    }

    // MARK: Shared definitions under a theme (#651: system tones, unchanged by a theme)

    /// #651: the read and unread MP title tones hold on the rows of every bundled theme. A theme does not recolour native rows
    /// or text (LOT-188 spec, "What a theme does not change"): what a theme decides is the appearance its rows show in (its own
    /// for a single variant), so the tones are checked on the system card of each appearance a theme shows in, and the theme's
    /// own pairs by its contrast test (`accentText` on that card included).
    @Test func theMPTitleTonesHoldInEveryBundledTheme() throws {
        let catalog = ThemeCatalog.bundled
        #expect(catalog.rejections.isEmpty, "\(catalog.rejections)")
        for theme in catalog.themes + [try ThemeFixtures.testTheme()] {
            // The appearances the theme shows in: both for Legacy and two-variant themes, its own for a single variant.
            let appearances: [Bool] = if case let .single(tokens)? = theme.variants { [!tokens.isLight] } else { [false, true] }
            for dark in appearances {
                for contrast in [UIAccessibilityContrast.normal, .high] {
                    let traits = UITraitCollection { $0.userInterfaceStyle = dark ? .dark : .light; $0.accessibilityContrast = contrast }
                    let card = UIColor.secondarySystemGroupedBackground.resolvedColor(with: traits)
                    let read = ReadTitleStyle.color(for: traits)
                    let unread = UIColor.label.resolvedColor(with: traits)
                    #expect(ratio(read, card) >= 4.5, "\(theme.id) \(dark ? "dark" : "light") read")
                    #expect(ratio(unread, card) >= 4.5, "\(theme.id) \(dark ? "dark" : "light") unread")
                }
            }
            #expect(theme.contrastViolations.isEmpty, "\(theme.id)")
        }
        // Legacy plus the test theme, in light and dark: a check that ran.
        #expect(catalog.themes.contains { $0.isLegacy })
    }

    /// WCAG ratio of two opaque UIKit colours (alpha composited over `background` first).
    private func ratio(_ foreground: UIColor, _ background: UIColor) -> Double {
        func components(_ color: UIColor) -> [CGFloat] {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return [red, green, blue, alpha]
        }
        let back = components(background), fore = components(foreground)
        let mixed = (0..<3).map { fore[$0] * fore[3] + back[$0] * (1 - fore[3]) }
        return ThemeColor(red: mixed[0], green: mixed[1], blue: mixed[2])
            .contrast(with: ThemeColor(red: back[0], green: back[1], blue: back[2]))
    }
}
