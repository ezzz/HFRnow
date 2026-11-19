import HFRModels
import HFRStorage
import Observation
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift ("Thème" section: loadTintHueIfNeeded, applyTintHue, applyDarkThemeBrightness)
// and Common.swift (AppThemeResolver, AppThemeStore) @ 21173e77. Differences: one appearance picker instead of "Changement
// de thème" + "Luminosité du thème" (ADR 0013 §8); creating the model writes nothing (legacy wrote the brightness default
// on first read).
/// The "Thème" settings, one instance for the whole app (`SwiftHFRApp` owns it): the appearance (system, light, dark), the
/// accent hue and the dark-theme brightness. Each value is read from its legacy keys at creation and written back on every
/// change; `preferredColorScheme` and `appearance` are what the app root applies to every screen and the reader (LOT-121).
@MainActor
@Observable
final class ThemeSettingsModel {
    /// The one appearance picker (ADR 0013 §8), stored under the legacy `auto_theme` and `theme` keys.
    enum Mode: CaseIterable, Hashable {
        /// Follow iOS (`auto_theme` = 3).
        case system
        /// Always light (`auto_theme` = 0, `theme` = 0).
        case light
        /// Always dark (`auto_theme` = 0, `theme` = 1).
        case dark

        /// Picker label, as legacy's options (`AppSettingsView.swift:140-148`).
        var title: String {
            switch self {
            case .system: "Automatique (iOS)"
            case .light: "Clair"
            case .dark: "Sombre"
            }
        }

        /// The label under the mode's tile (#1213).
        var tileTitle: String {
            switch self {
            case .system: "Système"
            case .light: "Clair"
            case .dark: "Sombre"
            }
        }

        /// What VoiceOver says for the mode's tile (#1213).
        var tileAccessibilityLabel: String {
            switch self {
            case .system: "Thème du système"
            case .light: "Thème clair"
            case .dark: "Thème sombre"
            }
        }

        /// The Legacy controls this mode shows below the tiles, besides the accent hue (#1213): the light style for light, the dark
        /// style and brightness for dark, both groups when following iOS.
        var controls: [ThemeControl] {
            switch self {
            case .light: [.lightStyle]
            case .dark: [.darkStyle, .darkBrightness]
            case .system: [.lightStyle, .darkStyle, .darkBrightness]
            }
        }
    }

    /// A Legacy control of the "Thème" screen that depends on the mode (#1213).
    enum ThemeControl: Hashable {
        /// The « Style du thème clair » picker, with its preview.
        case lightStyle
        /// The « Style du thème sombre » picker, with its preview.
        case darkStyle
        /// The « Luminosité du thème sombre » slider.
        case darkBrightness
    }

    /// System, light or dark.
    var mode: Mode {
        didSet {
            guard mode != oldValue else { return }
            // Legacy setUsesSystemColorScheme / setManualLegacyThemeValue (`Common.swift:358-367`): the manual variant is
            // kept when following iOS.
            switch mode {
            case .system:
                store.set(AutoThemeMode.system, for: SettingKey.autoTheme)
            case .light, .dark:
                store.set(AutoThemeMode.manual, for: SettingKey.autoTheme)
                store.set(mode == .dark ? ThemeVariant.dark : .light, for: SettingKey.manualTheme)
            }
        }
    }
    /// Accent hue, 0...1; a change writes both accents (`applyTintHue`).
    var accentHue: Double {
        didSet {
            let clamped = Self.clamp(accentHue, to: 0...1)
            if clamped != accentHue { accentHue = clamped }
            guard accentHue != oldValue else { return }
            dayAccent = ThemeAppearance.dayTint(hue: accentHue)
            nightAccent = ThemeAppearance.nightTint(hue: accentHue)
            store.set(dayAccent, for: SettingKey.dayActionColor)
            store.set(nightAccent, for: SettingKey.nightActionColor)
        }
    }
    /// Dark surfaces' brightness, 0...1.5 (1 = unchanged).
    var darkBrightness: Double {
        didSet {
            let clamped = Self.clamp(darkBrightness, to: 0...ThemeAppearance.maximumDarkBrightness)
            if clamped != darkBrightness { darkBrightness = clamped }
            if darkBrightness != oldValue { store.set(darkBrightness, for: SettingKey.nightBrightness) }
        }
    }
    /// How dark the dark theme is (standard, darker, OLED black); `theme_dark_style`, device-only (LOT-122).
    var darkStyle: DarkStyle {
        didSet {
            if darkStyle != oldValue { store.set(darkStyle, for: SettingKey.darkStyle) }
        }
    }
    /// How the light theme looks (« Blanc », « Doux »); `theme_light_style`, device-only (#1213).
    var lightStyle: LightStyle {
        didSet {
            if lightStyle != oldValue { store.set(lightStyle, for: SettingKey.lightStyle) }
        }
    }
    /// The stored theme id (`theme_id`, LOT-188), as stored: nil or an id no bundled theme has reads as Legacy, and stays.
    private(set) var themeID: String?
    /// The bundled themes (LOT-188).
    let catalog: ThemeCatalog
    /// The gallery's theme: the stored one, or Legacy.
    var theme: ThemeDefinition { catalog.theme(id: themeID) }

    /// Selects `theme` and stores its id; Legacy is stored as its id too, so a later default cannot change the user's choice.
    func select(_ theme: ThemeDefinition) {
        guard theme.id != themeID else { return }
        themeID = theme.id
        store.set(theme.id, for: SettingKey.themeID)
    }

    /// Accent of the light theme: the stored colour, which an older version may have set to any colour, or the default.
    private(set) var dayAccent: ThemeColor
    /// Accent of the dark theme.
    private(set) var nightAccent: ThemeColor

    /// The scheme the app forces, or nil to follow iOS (`AppThemeResolver.preferredColorScheme`). A single-variant theme
    /// imposes its own (LOT-188), whatever the picker says.
    var preferredColorScheme: ColorScheme? {
        if let forced = appearance.forcedColorScheme { return forced }
        return switch mode {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    /// The appearance the app root draws: the user's, with `seasonal` (LOT-166) drawn over it from this model's catalog.
    func appearance(drawing seasonal: SeasonalTheme?) -> ThemeAppearance {
        appearance.applying(seasonal, catalog: catalog)
    }

    /// The scheme the window takes while `appearance` is drawn: the one a single-variant theme imposes (the gallery's, or a
    /// seasonal one such as Noël abusé drawn over it, LOT-166), else `preferredColorScheme`.
    func colorScheme(drawing appearance: ThemeAppearance) -> ColorScheme? {
        appearance.forcedColorScheme ?? preferredColorScheme
    }

    /// The colours every screen and the reader use.
    var appearance: ThemeAppearance {
        let selected = self.theme
        return ThemeAppearance(
            dayAccent: dayAccent, nightAccent: nightAccent, darkBrightness: darkBrightness, darkStyle: darkStyle,
            lightStyle: lightStyle,
            themeVariants: selected.variants, themeFontDesign: selected.fontDesign, themeDecorations: selected.decorations
        )
    }

    @ObservationIgnored private let store: any SettingsStore

    /// Reads the current values from `store`; writes nothing. `catalog` is the bundled themes unless a test gives its own.
    init(store: any SettingsStore, catalog: ThemeCatalog = .bundled) {
        self.store = store
        self.catalog = catalog
        themeID = store.value(for: SettingKey.themeID)
        mode = switch store.value(for: SettingKey.autoTheme) {
        case .system: .system
        case .manual: store.value(for: SettingKey.manualTheme) == .dark ? .dark : .light
        }
        let storedDay = store.value(for: SettingKey.dayActionColor)
        dayAccent = storedDay ?? ThemeAppearance.standard.dayAccent
        nightAccent = store.value(for: SettingKey.nightActionColor) ?? ThemeAppearance.standard.nightAccent
        // The slider shows the hue of the light accent, as legacy's `resolvedTintHue` did.
        accentHue = storedDay?.hsb.hue ?? ThemeAppearance.defaultHue
        darkStyle = store.value(for: SettingKey.darkStyle)
        lightStyle = store.value(for: SettingKey.lightStyle)
        darkBrightness = Self.clamp(
            store.value(for: SettingKey.nightBrightness) ?? ThemeAppearance.defaultDarkBrightness,
            to: 0...ThemeAppearance.maximumDarkBrightness
        )
    }

    private static func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
        guard value.isFinite else { return range.lowerBound }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

extension View {
    /// One appearance and one accent for every screen, sheets and the reader included (LOT-121). The scheme is set on the
    /// window, as legacy did (`HFRplusAppDelegate.m:392`), so presented sheets and the reader's `WKWebView`
    /// (`prefers-color-scheme`) read the same trait, and nil hands it back to iOS at once. The app root applies it once.
    /// A `seasonal` theme (LOT-166) is drawn over the user's colours without changing them; Noël abusé, a single-variant theme
    /// of the engine, imposes its appearance like a gallery one.
    func appTheme(_ theme: ThemeSettingsModel, seasonal: SeasonalTheme? = nil) -> some View {
        let appearance = theme.appearance(drawing: seasonal)
        let scheme = theme.colorScheme(drawing: appearance)
        return environment(theme)
            .environment(\.themeAppearance, appearance)
            .tint(appearance.accentColor)
            // nil for Legacy: no design set, as before (LOT-188); a value change only, never a new structure.
            .fontDesign(appearance.fontDesign)
            .background(WindowStyle(scheme: scheme, tint: appearance.accentUIColor))
    }
}

/// Sets the hosting window's `overrideUserInterfaceStyle` (`.unspecified` follows iOS) and its `tintColor`, which UIKit
/// chrome such as alerts reads, as legacy's app delegate did (`HFRplusAppDelegate.m:368, 392`).
private struct WindowStyle: UIViewRepresentable {
    let scheme: ColorScheme?
    let tint: UIColor

    final class Anchor: UIView {
        var style = UIUserInterfaceStyle.unspecified {
            didSet { apply() }
        }
        var accent: UIColor? {
            didSet { apply() }
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window else { return }
            window.overrideUserInterfaceStyle = style
            window.tintColor = accent
        }
    }

    func makeUIView(context: Context) -> Anchor {
        let anchor = Anchor()
        anchor.isUserInteractionEnabled = false
        return anchor
    }

    func updateUIView(_ anchor: Anchor, context: Context) {
        anchor.accent = tint
        anchor.style = switch scheme {
        case .dark: .dark
        case .light: .light
        default: .unspecified
        }
    }
}

extension View {
    /// The dark theme's screen background for the "darker" and "OLED" styles (LOT-122), for the root view of a navigation
    /// container: lists and forms let it show through and the container paints it. The standard style is the system's,
    /// untouched; in light the other styles keep the system's background on stacks (see `AppScreenBackground`).
    /// A container the modifier is not applied to keeps the system's fill (see LOT-122 spec).
    func appScreenBackground() -> some View { modifier(AppScreenBackground()) }
}

private struct AppScreenBackground: ViewModifier {
    @Environment(\.themeAppearance) private var appearance
    @Environment(\.colorScheme) private var scheme

    /// Only the style chooses the structure; the appearance only changes values. A flip between light and dark (iOS's sunset
    /// schedule, Control Center) must not give the wrapped screen (a reader's web view, a composer, a list) a new identity, or
    /// its state resets. A change of the style in Settings rebuilds, which the user asked for.
    ///
    /// Standard applies nothing at all: an empty `containerBackground` is not "no modifier", it clears the stack's own opaque
    /// fill (measured). In light a darker or OLED user gets the system's background on stacks; a split column and a sheet lose
    /// their own fill (the iPad sidebar's material, the sheet's shade) there, which no empty or fallback form avoids.
    ///
    /// A theme (LOT-188) paints its `background` in both appearances with one dynamic colour, so a flip changes a value, not
    /// the structure; a change between Legacy and a theme, or between Legacy's styles, rebuilds, which the user asked for. One
    /// change is not the user's: Noël abusé (LOT-166) drawn over Legacy is a theme too, so its packing, once a year at the
    /// first launch from 27/12, rebuilds the screens it wraps when the elves are done.
    func body(content: Content) -> some View {
        // #1120 (operator, 2026-11-18): every screen's top bar sits on Apple's soft scroll-edge effect, set once here because every
        // screen root carries this modifier. Measured: the automatic style draws a hard-edged frosted band 116 pt tall; the soft
        // one fades the content out toward the bar. No custom blur or material (#1070).
        screen(content).scrollEdgeEffectStyle(.soft, for: .top)
    }

    @ViewBuilder private func screen(_ content: Content) -> some View {
        switch appearance.screenFill {
        case let .theme(light, dark):
            let fill = Color(uiColor: ThemeAppearance.dynamic(light: light, dark: dark))
            // A theme's art sits on its background, behind the content (LOT-166: Noël abusé); each column draws its own.
            let decorations = appearance.themeDecorations
            content
                .scrollContentBackground(.hidden)
                .environment(\.screenPaintsLists, true)
                .containerBackground(for: .navigation) { ThemeScreenBackdrop(fill: fill, decorations: decorations) }
                .containerBackground(for: .navigationSplitView) { ThemeScreenBackdrop(fill: fill, decorations: decorations) }
        case let .softLight(light, dark):
            // Doux (#1213): one dynamic colour in both appearances, like a theme's, so a flip changes a value, not the structure.
            // The dark side the style leaves to the system is the system's own background (black in dark, as the lists show it).
            let systemDark = UIColor.systemBackground.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
            let fill = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark ? (dark?.uiColor ?? systemDark) : light.uiColor })
            content
                .scrollContentBackground(.hidden)
                .environment(\.screenPaintsLists, true)
                .containerBackground(for: .navigation) { fill }
                .containerBackground(for: .navigationSplitView) { fill }
        case let .darkOnly(color):
            let fill = Color(uiColor: color.uiColor)
            let dark = scheme == .dark
            content
                .scrollContentBackground(dark ? .hidden : .automatic)
                .environment(\.screenPaintsLists, dark)
                .containerBackground(for: .navigation) { if dark { fill } else { Rectangle().fill(.background) } }
                // A column of a split view (iPad sidebar, content, detail) has its own container, set the same way.
                .containerBackground(for: .navigationSplitView) { if dark { fill } }
        case .system:
            content
        }
    }
}

/// A `NavigationStack` whose root view carries `appScreenBackground()`.
struct ThemedNavigationStack<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        NavigationStack { content.appScreenBackground() }
    }
}
