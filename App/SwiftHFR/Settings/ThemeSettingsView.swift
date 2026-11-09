import HFRModels
import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (themeSection) @ 21173e77. Differences: one appearance picker (ADR 0013 §8);
// a screen behind the "Thème" row (LOT-119 shell) instead of rows inline in the form.
/// The "Thème" settings screen (LOT-121, LOT-122): appearance, accent hue, dark style and brightness, applied live to every
/// screen, with a preview of the chosen dark surfaces.
struct ThemeSettingsView: View {
    @Environment(ThemeSettingsModel.self) private var theme

    var body: some View {
        @Bindable var theme = theme
        Form {
            Section {
                Picker("Thème", selection: $theme.mode) {
                    ForEach(ThemeSettingsModel.Mode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Teinte d'accent") {
                        Text(theme.accentHue, format: .number.precision(.fractionLength(2)))
                    }
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
                    Slider(value: $theme.darkBrightness, in: 0...ThemeAppearance.maximumDarkBrightness, step: 0.01)
                        .accessibilityLabel("Luminosité du thème sombre")
                        .accessibilityValue(Text(theme.darkBrightness, format: .percent.precision(.fractionLength(0))))
                }
            } footer: {
                Text(
                    "Le style s’applique au thème sombre : fonds des écrans et du sujet ouvert. "
                        + "La luminosité s’applique aux fonds sombres du sujet ouvert."
                )
            }
        }
        .navigationTitle("Thème")
        .navigationBarTitleDisplayMode(.inline)
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
    @ScaledMetric private var spacing = 6.0
    @ScaledMetric private var padding = 10.0
    @ScaledMetric private var radius = 8.0

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
                .padding(spacing).frame(maxWidth: .infinity, alignment: .leading)
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
}
