import HFRStorage
import Observation

/// The Réglages › Expérimental switches, one instance for the whole app (`SwiftHFRApp` owns it, #903): views and models read a
/// flag here, never a raw `UserDefaults` key. Each value is read at creation and written back on a change only, so creating the
/// model writes nothing.
@MainActor
@Observable
final class ExperimentalSettings {
    /// The store the switches live in, for the pickers of options that have one (`ImageLoadingChoice`).
    let store: any SettingsStore
    private var stored: [ExperimentalFeature: Bool]

    /// Reads every switch from `store`.
    init(store: any SettingsStore) {
        self.store = store
        stored = Dictionary(uniqueKeysWithValues: ExperimentalFeature.allCases.map { ($0, store.value(for: $0.setting)) })
    }

    /// Whether `feature` is on: its stored value, its default when nothing is stored.
    func isOn(_ feature: ExperimentalFeature) -> Bool {
        stored[feature] ?? feature.setting.defaultValue
    }

    /// Turns `feature` on or off.
    func set(_ feature: ExperimentalFeature, isOn: Bool) {
        guard stored[feature] != isOn else { return }
        stored[feature] = isOn
        // EXPERIMENTAL(imageLoadingChoice, #1003): the option's first activation starts its choice at « Toujours ». Before the
        // switch is written: the reader reads both off the main actor and must never see the option on with a stale choice.
        if feature == .imageLoadingChoice, isOn { ImageLoadingChoice.willTurnOn(store: store) }
        store.set(isOn, for: feature.setting)
    }

    /// `feature` in `settings`, or its default where none is in the environment (previews, hosted tests).
    static func isOn(_ feature: ExperimentalFeature, in settings: ExperimentalSettings?) -> Bool {
        settings?.isOn(feature) ?? feature.setting.defaultValue
    }
}
