import HFRStorage
import SwiftUI

// Port of Classes/PlusSettingsViewController.m (the theme_noel_disabled cell, shown while theme_noel_period, `:112-115`)
// @ 87fe0d1c. Differences (GAP-147): a pick between the user's theme and Noël soft, and the two seasonal toggles of THEMES.md §1.
/// « Thèmes de saison » in Réglages › Thème, shown inside a season's window only.
struct SeasonalThemesSection: View {
    @Bindable var model: SeasonalThemeModel

    var body: some View {
        Section {
            Picker("Thème de saison", selection: Binding(get: { model.activeTheme }, set: { model.select($0) })) {
                Text("Thème habituel").tag(SeasonalTheme?.none)
                ForEach(SeasonalTheme.allCases) { Text($0.title).tag(SeasonalTheme?.some($0)) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
            Toggle("Thèmes de saison automatiques", isOn: $model.isAutomatic)
            Toggle("Animations de saison", isOn: $model.animationsEnabled)
        } header: {
            Text("Thèmes de saison")
        } footer: {
            Text(
                "Noël soft : accent rouge et neige légère, jusqu’au 26 décembre ; votre thème revient ensuite. "
                    + "Sans animations, la neige ne tombe plus."
            )
        }
    }
}

#Preview("Thèmes de saison") {
    Form { SeasonalThemesSection(model: SeasonalThemeModel(store: InMemorySettingsStore())) }
}
