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
    /// The colours every screen and the reader use.
    var appearance: ThemeAppearance {
        let selected = self.theme
        return ThemeAppearance(
            dayAccent: dayAccent, nightAccent: nightAccent, darkBrightness: darkBrightness, darkStyle: darkStyle,
            themeVariants: selected.variants, themeFontDesign: selected.fontDesign
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
    func appTheme(_ theme: ThemeSettingsModel) -> some View {
        environment(theme)
            .environment(\.themeAppearance, theme.appearance)
            .tint(theme.appearance.accentColor)
            // nil for Legacy: no design set, as before (LOT-188); a value change only, never a new structure.
            .fontDesign(theme.appearance.fontDesign)
            .background(WindowStyle(scheme: theme.preferredColorScheme, tint: theme.appearance.accentUIColor))
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
    /// the structure; a change between Legacy and a theme, or between Legacy's styles, rebuilds, which the user asked for.
    @ViewBuilder func body(content: Content) -> some View {
        switch appearance.screenFill {
        case let .theme(light, dark):
            let fill = Color(uiColor: ThemeAppearance.dynamic(light: light, dark: dark))
            content
                .scrollContentBackground(.hidden)
                .containerBackground(for: .navigation) { fill }
                .containerBackground(for: .navigationSplitView) { fill }
        case let .darkOnly(color):
            let fill = Color(uiColor: color.uiColor)
            let dark = scheme == .dark
            content
                .scrollContentBackground(dark ? .hidden : .automatic)
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
