import HFRModels
import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (themeSection) @ 21173e77. Differences: one appearance picker (ADR 0013 §8);
// a screen behind the "Thème" row (LOT-119 shell) instead of rows inline in the form; the theme gallery below the pickers
// (LOT-188, GAP-729: legacy @ 87fe0d1c had two themes, light and dark, `AppSettingsView.swift:421-466`).
/// The "Thème" settings screen (LOT-121, LOT-122, LOT-188): appearance, accent hue, dark style and brightness, applied live to
/// every screen, with a preview of the chosen dark surfaces, then the gallery of themes. The hue, style and brightness are
/// Legacy's own colours: they show while Legacy is the theme.
struct ThemeSettingsView: View {
    @Environment(ThemeSettingsModel.self) private var theme
    @Environment(SeasonalThemeModel.self) private var seasonal
    // The sliders' values while a finger is down (#1211): the model, the store and the app behind get the final one on release.
    @State private var hueDraft = SliderDraft<Double>()
    @State private var brightnessDraft = SliderDraft<Double>()

    private var shownHue: Double { hueDraft.shown(saved: theme.accentHue) }
    private var shownBrightness: Double { brightnessDraft.shown(saved: theme.darkBrightness) }

    /// The appearance this screen's previews draw: the model's, with the values being dragged.
    private var previewAppearance: ThemeAppearance {
        var appearance = theme.appearance
        // Only a drag overrides: with none, the stored colours show as they are (they may not be the hue's own tints).
        guard theme.theme.isLegacy else { return appearance }
        if hueDraft.draft != nil {
            appearance.dayAccent = ThemeAppearance.dayTint(hue: shownHue)
            appearance.nightAccent = ThemeAppearance.nightTint(hue: shownHue)
        }
        if brightnessDraft.draft != nil { appearance.darkBrightness = shownBrightness }
        return appearance
    }

    var body: some View {
        @Bindable var theme = theme
        Form {
            Section {
                Group {
                    ThemeModeTiles(appearance: previewAppearance, mode: $theme.mode)
                    if theme.theme.isLegacy {
                        legacyColors
                    }
                }.themedListRow()
            } footer: {
                Group {
                    if let drawn = seasonal.drawnTheme, drawn.isEngineTheme {
                        Text("\(drawn.title) est affiché jusqu’à la fin de la saison : ces réglages s’appliqueront ensuite.")
                    } else if theme.theme.isLegacy {
                        Text(Self.footer(for: theme.mode))
                    } else if theme.appearance.forcedColorScheme != nil {
                        Text("« \(theme.theme.name) » n’a qu’une variante : clair = sombre.")
                    }
                }.themedSectionHeader()
            }
            // Only inside a season's window, as legacy's Noël cell (`PlusSettingsViewController.m:112-115` @ 87fe0d1c); above the
            // gallery, whose families never show a seasonal one (LOT-188: their window is LOT-166's).
            if seasonal.isSelectable {
                SeasonalThemesSection(model: seasonal)
            }
            ThemeGallery()
        }
        .navigationTitle("Thème")
        .navigationBarTitleDisplayMode(.inline)
    }

    /// What the style controls of `mode` do (#1213).
    private static func footer(for mode: ThemeSettingsModel.Mode) -> String {
        let light = "Le style clair s’applique aux fonds des écrans et du sujet ouvert."
        let dark = "Le style sombre s’applique aux fonds des écrans et du sujet ouvert. "
            + "La luminosité s’applique aux fonds sombres du sujet ouvert."
        return switch mode {
        case .light: light
        case .dark: dark
        case .system: light + " " + dark
        }
    }

    /// Legacy's accent hue, then the light and dark controls the mode shows (LOT-121, LOT-122, #1213).
    @ViewBuilder private var legacyColors: some View {
        @Bindable var theme = theme
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Teinte d'accent") {
                Text(shownHue, format: .number.precision(.fractionLength(2)))
            }
            .accessibilityHidden(true) // the slider below speaks both
            DraftSlider(draft: $hueDraft, saved: theme.accentHue, range: 0...1, step: 0.001) { theme.accentHue = $0 }
            .tint(Color(uiColor: ThemeAppearance.dayTint(hue: shownHue).uiColor))
            .accessibilityLabel("Teinte d'accent")
            .accessibilityValue(Text(shownHue, format: .number.precision(.fractionLength(2))))
        }
        ForEach(theme.mode.controls, id: \.self) { control in
            controlView(control)
        }
    }

    /// One mode-dependent control. When both groups show (following iOS), each opens with its own title.
    @ViewBuilder private func controlView(_ control: ThemeSettingsModel.ThemeControl) -> some View {
        @Bindable var theme = theme
        switch control {
        case .lightStyle:
            if theme.mode == .system { groupTitle("Thème clair") }
            Picker("Style du thème clair", selection: $theme.lightStyle) {
                ForEach(LightStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            LightStylePreview(appearance: previewAppearance)
        case .darkStyle:
            if theme.mode == .system { groupTitle("Thème sombre") }
            Picker("Style du thème sombre", selection: $theme.darkStyle) {
                ForEach(DarkStyle.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            DarkStylePreview(appearance: previewAppearance)
        case .darkBrightness:
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Luminosité du thème sombre") {
                    Text(shownBrightness, format: .percent.precision(.fractionLength(0)))
                }
                .accessibilityHidden(true)
                DraftSlider(
                    draft: $brightnessDraft, saved: theme.darkBrightness, range: 0...ThemeAppearance.maximumDarkBrightness, step: 0.01
                ) { theme.darkBrightness = $0 }
                .accessibilityLabel("Luminosité du thème sombre")
                .accessibilityValue(Text(shownBrightness, format: .percent.precision(.fractionLength(0))))
            }
        }
    }

    private func groupTitle(_ title: String) -> some View {
        Text(title).font(.footnote).fontWeight(.semibold).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
    }
}

extension LightStyle {
    /// Picker label.
    var title: String {
        switch self {
        case .blanc: "Blanc"
        case .doux: "Doux"
        }
    }
}

extension DarkStyle {
    /// Picker label.
    var title: String {
        switch self {
        case .standard: "Standard"
        case .darker: "Plus sombre"
        case .oled: "Noir OLED"
        }
    }
}

/// A sample of the chosen dark surfaces whatever the current theme: a message on the screen background with its separator, a
/// border-only quote (as the reader draws it, #819) and the accent, drawn from the surfaces the reader receives
/// (`ThemeAppearance.readerSurfaces`: same brightness, same cap).
private struct DarkStylePreview: View {
    let appearance: ThemeAppearance
    // Dynamic Type scales the sample's insets with its text.
    @ScaledMetric(relativeTo: .callout) private var spacing = 6.0
    @ScaledMetric(relativeTo: .callout) private var quotePadding = 6.0
    @ScaledMetric(relativeTo: .callout) private var padding = 10.0
    @ScaledMetric(relativeTo: .callout) private var radius = 8.0

    var body: some View {
        let surfaces = Dictionary(uniqueKeysWithValues: appearance.readerSurfaces.map { ($0.variable, $0.color) })
        let black = ThemeColor(hex: 0)
        let background = surfaces["--app-dark-background"] ?? black
        let separator = surfaces["--app-dark-separator"] ?? black
        VStack(alignment: .leading, spacing: spacing) {
            Text("Aperçu du thème sombre").font(.caption).foregroundStyle(Color(uiColor: ThemeAppearance.darkSecondaryText.uiColor))
            Text("Un message du sujet").foregroundStyle(Color(uiColor: ThemeAppearance.darkText.uiColor))
            Text("Une citation").font(.callout)
                .foregroundStyle(Color(uiColor: appearance.nightAccent.uiColor))
                .padding(quotePadding).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { Rectangle().fill(Color(uiColor: ThemeColor(hex: 0x636366).uiColor)).frame(width: 2) }
            Rectangle().fill(Color(uiColor: separator.uiColor)).frame(height: 1)
        }
        .padding(padding)
        .background(Color(uiColor: background.uiColor), in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color(uiColor: separator.uiColor), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu du thème sombre")
    }
}

/// A sample of the chosen light surfaces: a message on the page with its separator, a border-only quote and the accent, drawn from
/// what the reader receives for the light style (`ThemeAppearance+LightStyle`).
private struct LightStylePreview: View {
    let appearance: ThemeAppearance
    @ScaledMetric(relativeTo: .callout) private var spacing = 6.0
    @ScaledMetric(relativeTo: .callout) private var quotePadding = 6.0
    @ScaledMetric(relativeTo: .callout) private var padding = 10.0
    @ScaledMetric(relativeTo: .callout) private var radius = 8.0

    var body: some View {
        let look = appearance.tileLook(dark: false)
        let surfaces = Dictionary(uniqueKeysWithValues: appearance.lightSurfaces.map { ($0.variable, $0.color) })
        let separator = surfaces["--app-light-separator"] ?? ThemeColor(hex: 0xD1D1D6)
        VStack(alignment: .leading, spacing: spacing) {
            Text("Aperçu du thème clair").font(.caption).foregroundStyle(Color(uiColor: look.line.uiColor))
            Text("Un message du sujet").foregroundStyle(Color(uiColor: ThemeColor(hex: 0x1C1C1E).uiColor))
            Text("Une citation").font(.callout)
                .foregroundStyle(Color(uiColor: look.line.uiColor))
                .padding(quotePadding).frame(maxWidth: .infinity, alignment: .leading)
                .overlay(alignment: .leading) { Rectangle().fill(Color(uiColor: ThemeColor(hex: 0x8E8E93).uiColor)).frame(width: 2) }
            Rectangle().fill(Color(uiColor: separator.uiColor)).frame(height: 1)
        }
        .padding(padding)
        .background(Color(uiColor: look.surface.uiColor), in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color(uiColor: separator.uiColor), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu du thème clair")
    }
}

#Preview("Thème") {
    ThemedNavigationStack { ThemeSettingsView() }
        .environment(ThemeSettingsModel(store: InMemorySettingsStore()))
        .environment(SeasonalThemeModel(store: InMemorySettingsStore()))
}
