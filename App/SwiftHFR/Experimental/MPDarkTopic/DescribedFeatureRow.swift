import SwiftUI

// EXPERIMENTAL(mpDarkTopic, #1014): the row of an option whose description sits under its switch, as the other Réglages
// descriptions do, with no ⓘ and no popover (operator, 2026-11-17).
/// A switch with its explanation permanently under it; VoiceOver reads the explanation as the switch's hint.
struct DescribedFeatureRow: View {
    let feature: ExperimentalFeature
    let settings: ExperimentalSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle(feature.title, isOn: Binding(
                get: { settings.isOn(feature) },
                set: { settings.set(feature, isOn: $0) }
            ))
            Text(feature.explanation)
                .scaledFont(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                // The switch's hint already reads it.
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(feature.explanation)
    }
}
