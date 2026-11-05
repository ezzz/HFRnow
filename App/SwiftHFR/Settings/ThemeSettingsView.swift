import HFRStorage
import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (themeSection) @ 21173e77. Differences: one appearance picker (ADR 0013 §8);
// a screen behind the "Thème" row (LOT-119 shell) instead of rows inline in the form.
/// The "Thème" settings screen (LOT-121): appearance, accent hue and dark-theme brightness, applied live to every screen.
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
                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Luminosité du thème sombre") {
                        Text(theme.darkBrightness, format: .percent.precision(.fractionLength(0)))
                    }
                    Slider(value: $theme.darkBrightness, in: 0...ThemeAppearance.maximumDarkBrightness, step: 0.01)
                        .accessibilityLabel("Luminosité du thème sombre")
                        .accessibilityValue(Text(theme.darkBrightness, format: .percent.precision(.fractionLength(0))))
                }
            } footer: {
                Text("La luminosité s’applique aux fonds sombres du sujet ouvert.")
            }
        }
        .navigationTitle("Thème")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Thème") {
    NavigationStack { ThemeSettingsView() }
        .environment(ThemeSettingsModel(store: InMemorySettingsStore()))
}
