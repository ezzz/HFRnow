import SwiftUI

// New in SwiftHFR (#903, operator 2026-11-14): legacy has no experimental options. No GAP row: nothing of legacy changes.
/// What Réglages › Expérimental lists: the options grouped by theme, in display order, empty themes left out (#971).
enum ExperimentalPageLayout {
    /// One theme and its options on the page.
    struct Group: Equatable {
        let theme: ExperimentalTheme
        let features: [ExperimentalFeature]
    }

    /// The groups of `features` (the listed options by default); empty when none is listed, which hides the Réglages row.
    static func groups(of features: [ExperimentalFeature] = ExperimentalFeature.allCases.filter(\.isListed)) -> [Group] {
        ExperimentalTheme.allCases.compactMap { theme in
            let inTheme = features.filter { $0.theme == theme }
            return inTheme.isEmpty ? nil : Group(theme: theme, features: inTheme)
        }
    }
}

/// The single "Expérimental" row at the end of Réglages (#971): a monochrome warning symbol and a link to the page of options.
/// Nothing when no option is listed.
struct ExperimentalSettingsSection: View {
    let settings: ExperimentalSettings
    var groups: [ExperimentalPageLayout.Group] = ExperimentalPageLayout.groups()

    var body: some View {
        if !groups.isEmpty {
            Section {
                NavigationLink {
                    ExperimentalPageView(groups: groups, settings: settings).appScreenBackground()
                } label: {
                    Label {
                        Text("Expérimental")
                    } icon: {
                        // Text colour, not tinted; decorative, so VoiceOver reads the row's title only.
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.primary)
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }
}

/// The "Expérimental" page: one section per theme with each option's switch and ⓘ, and the footer on the last section.
struct ExperimentalPageView: View {
    let groups: [ExperimentalPageLayout.Group]
    let settings: ExperimentalSettings

    var body: some View {
        Form {
            ForEach(groups, id: \.theme) { group in
                Section {
                    ForEach(group.features) { feature in
                        ExperimentalFeatureRow(feature: feature, settings: settings)
                    }
                } header: {
                    Text(group.theme.title)
                } footer: {
                    if group.theme == groups.last?.theme {
                        Text("Options en cours de mise au point, désactivées par défaut.")
                    }
                }
            }
        }
        .navigationTitle("Expérimental")
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
