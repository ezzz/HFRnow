import HFRStorage
import SwiftUI

// Port of Classes/PlusSettingsViewController.m (the theme_noel_disabled cell, shown while theme_noel_period, `:112-115`)
// @ 87fe0d1c. Differences (GAP-147): a pick between the user's theme, Noël soft and Noël abusé, and the two seasonal toggles
// of THEMES.md §1.
/// « Thèmes de saison » in Réglages › Thème, shown inside a season's window only.
struct SeasonalThemesSection: View {
    @Bindable var model: SeasonalThemeModel

    var body: some View {
        Section {
            Group {
                Picker("Thème de saison", selection: Binding(get: { model.activeTheme }, set: { model.select($0) })) {
                    Text("Thème habituel").tag(SeasonalTheme?.none)
                    ForEach(SeasonalTheme.allCases) { Text($0.title).tag(SeasonalTheme?.some($0)) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Toggle("Thèmes de saison automatiques", isOn: $model.isAutomatic)
                Toggle("Animations de saison", isOn: $model.animationsEnabled)
            }.themedListRow()
        } header: {
            Text("Thèmes de saison").themedSectionHeader()
        } footer: {
            Group {
                Text(
                    "Noël soft : neige légère et accent rouge sur le thème Legacy (un thème de la galerie garde son accent). "
                        + "Noël abusé : vert sapin, guirlande, sapin et cadeaux, identique en clair et en sombre. "
                        + "Jusqu’au 26 décembre ; votre thème revient ensuite. Sans animations, la neige ne tombe plus."
                )
            }.themedSectionHeader()
        }
    }
}

#Preview("Thèmes de saison") {
    Form { SeasonalThemesSection(model: SeasonalThemeModel(store: InMemorySettingsStore())) }
}
