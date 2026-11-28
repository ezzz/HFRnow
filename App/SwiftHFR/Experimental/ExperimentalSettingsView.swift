import SwiftUI

// New in SwiftHFR (#903, operator 2026-11-14): legacy has no experimental options. No GAP row: nothing of legacy changes.
/// What Réglages › Expérimental lists: the options grouped by theme, in display order, empty themes left out (#971).
enum ExperimentalPageLayout {
    /// One theme and its options on the page.
    struct Group: Equatable {
        let theme: ExperimentalTheme
        let features: [ExperimentalFeature]
    }

    /// The groups of the listed options (every theme with at least one), in display order; empty when none is listed, which
    /// hides the Réglages row. Built from `ExperimentalTheme.listed`, the one source of what is listed.
    static func groups() -> [Group] {
        ExperimentalTheme.listed.map { Group(theme: $0, features: $0.listedFeatures) }
    }
}

/// The single "Expérimental" row at the end of Réglages (#971): a monochrome warning symbol and a link to the page of options.
/// Nothing when no option is listed.
struct ExperimentalSettingsSection: View {
    let settings: ExperimentalSettings

    var body: some View {
        let groups = ExperimentalPageLayout.groups()
        if !groups.isEmpty {
            Section {
                ThemedRows {
                    NavigationLink {
                        ExperimentalPageView(groups: groups, settings: settings).appScreenBackground()
                    } label: {
                        Label {
                            Text("Expérimental")
                        } icon: {
                            // Text colour, not tinted; decorative, so VoiceOver reads the row's title only.
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(Color.primary)
                                .accessibilityHidden(true)
                        }
                    }
                }
            }
        }
    }
}

/// The "Expérimental" page: one section per theme with each option's switch and ⓘ (a description under the switch instead for
/// `showsExplanationUnderSwitch` options), and the footer on the last section.
struct ExperimentalPageView: View {
    let groups: [ExperimentalPageLayout.Group]
    let settings: ExperimentalSettings

    var body: some View {
        Form {
            ForEach(groups, id: \.theme) { group in
                Section {
                    ThemedRows {
                        ForEach(group.features) { feature in
                            // EXPERIMENTAL(mpDarkTopic, #1014): a description under the switch, no ⓘ and no popover.
                            if feature.showsExplanationUnderSwitch {
                                DescribedFeatureRow(feature: feature, settings: settings)
                            } else {
                                ExperimentalFeatureRow(feature: feature, settings: settings)
                            }
                            // EXPERIMENTAL(imageLoadingChoice, #902): the picker shows once the option is on.
                            if feature == .imageLoadingChoice, settings.isOn(feature) {
                                ImageLoadingChoicePicker(store: settings.store)
                            }
                        }
                    }
                } header: {
                    Text(group.theme.title).themedSectionHeader()
                } footer: {
                    Group {
                        if group.theme == groups.last?.theme {
                            Text("Options en cours de mise au point, désactivées par défaut.")
                        }
                    }.themedSectionHeader()
                }
            }
        }
        .navigationTitle("Expérimental")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A switch and its ⓘ, which shows the explanation under it; VoiceOver reads the explanation as the switch's hint. An option that
/// shows its explanation under the switch (`showsExplanationUnderSwitch`) uses `DescribedFeatureRow` instead.
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
