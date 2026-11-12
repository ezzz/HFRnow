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

    var body: some View {
        @Bindable var theme = theme
        Form {
            Section {
                Picker("Thème", selection: $theme.mode) {
                    ForEach(ThemeSettingsModel.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                if theme.theme.isLegacy {
                    legacyColors
                }
            } footer: {
                if theme.theme.isLegacy {
                    Text(
                        "Le style s’applique au thème sombre : fonds des écrans et du sujet ouvert. "
                            + "La luminosité s’applique aux fonds sombres du sujet ouvert."
                    )
                } else if theme.appearance.forcedColorScheme != nil {
                    Text("« \(theme.theme.name) » n’a qu’une variante : clair = sombre.")
                }
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

    /// Legacy's accent hue, dark style and brightness (LOT-121, LOT-122).
    @ViewBuilder private var legacyColors: some View {
        @Bindable var theme = theme
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Teinte d'accent") {
                Text(theme.accentHue, format: .number.precision(.fractionLength(2)))
            }
            .accessibilityHidden(true) // the slider below speaks both
            Slider(value: $theme.accentHue, in: 0...1, step: 0.001)
                .tint(Color(uiColor: ThemeAppearance.dayTint(hue: theme.accentHue).uiColor))
                .accessibilityLabel("Teinte d'accent")
                .accessibilityValue(Text(theme.accentHue, format: .number.precision(.fractionLength(2))))
        }
        Picker("Style du thème sombre", selection: $theme.darkStyle) {
            ForEach(DarkStyle.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        DarkStylePreview(appearance: theme.appearance)
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("Luminosité du thème sombre") {
                Text(theme.darkBrightness, format: .percent.precision(.fractionLength(0)))
            }
            .accessibilityHidden(true)
            Slider(value: $theme.darkBrightness, in: 0...ThemeAppearance.maximumDarkBrightness, step: 0.01)
                .accessibilityLabel("Luminosité du thème sombre")
                .accessibilityValue(Text(theme.darkBrightness, format: .percent.precision(.fractionLength(0))))
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
/// quote and the accent, drawn from the surfaces the reader receives (`ThemeAppearance.readerSurfaces`: same brightness, same cap).
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
        let quote = surfaces["--app-dark-quote-background"] ?? black
        let separator = surfaces["--app-dark-separator"] ?? black
        VStack(alignment: .leading, spacing: spacing) {
            Text("Aperçu du thème sombre").font(.caption).foregroundStyle(Color(uiColor: ThemeAppearance.darkSecondaryText.uiColor))
            Text("Un message du sujet").foregroundStyle(Color(uiColor: ThemeAppearance.darkText.uiColor))
            Text("Une citation").font(.callout)
                .foregroundStyle(Color(uiColor: appearance.nightAccent.uiColor))
                .padding(quotePadding).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(uiColor: quote.uiColor))
            Rectangle().fill(Color(uiColor: separator.uiColor)).frame(height: 1)
        }
        .padding(padding)
        .background(Color(uiColor: background.uiColor), in: RoundedRectangle(cornerRadius: radius))
        .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Color(uiColor: separator.uiColor), lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Aperçu du thème sombre")
    }
}

#Preview("Thème") {
    ThemedNavigationStack { ThemeSettingsView() }
        .environment(ThemeSettingsModel(store: InMemorySettingsStore()))
        .environment(SeasonalThemeModel(store: InMemorySettingsStore()))
}
