import SwiftUI

// New in SwiftHFR (#903, operator 2026-11-14): legacy has no experimental options. No GAP row: nothing of legacy changes.
/// The "Expérimental" section at the end of Réglages: one row per sub-menu that lists an option, and the footer. Nothing when
/// no option is listed.
struct ExperimentalSettingsSection: View {
    let settings: ExperimentalSettings

    var body: some View {
        let themes = ExperimentalTheme.listed
        if !themes.isEmpty {
            Section {
                ForEach(themes) { theme in
                    NavigationLink { ExperimentalThemeView(theme: theme, settings: settings).appScreenBackground() } label: {
                        Label(theme.title, systemImage: theme.symbol)
                    }
                }
            } header: {
                Text("Expérimental")
            } footer: {
                Text("Options en cours de mise au point, désactivées par défaut.")
            }
        }
    }
}

/// One sub-menu: the switch of each listed option of `theme`, each with its ⓘ.
struct ExperimentalThemeView: View {
    let theme: ExperimentalTheme
    let settings: ExperimentalSettings

    var body: some View {
        Form {
            ForEach(theme.listedFeatures) { feature in
                ExperimentalFeatureRow(feature: feature, settings: settings)
            }
        }
        .navigationTitle(theme.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A switch and its ⓘ, which shows the explanation under it; VoiceOver reads the explanation as the switch's hint.
struct ExperimentalFeatureRow: View {
    let feature: ExperimentalFeature
    let settings: ExperimentalSettings
    @State private var isExplained = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Toggle(feature.title, isOn: Binding(
                    get: { settings.isOn(feature) },
                    set: { settings.set(feature, isOn: $0) }
                ))
                .accessibilityHint(feature.explanation)
                Button("Explication", systemImage: isExplained ? "info.circle.fill" : "info.circle") {
                    withAnimation { isExplained.toggle() }
                }
                .labelStyle(.iconOnly)
                // A Form row with two controls: without it, a tap anywhere in the row would also press this button.
                .buttonStyle(.borderless)
                // The switch's hint already reads the explanation.
                .accessibilityHidden(true)
            }
            if isExplained {
                Text(feature.explanation)
                    .scaledFont(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            }
        }
    }
}
