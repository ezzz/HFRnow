import HFRStorage
import Observation

/// The Réglages › Expérimental switches, one instance for the whole app (`SwiftHFRApp` owns it, #903): views and models read a
/// flag here, never a raw `UserDefaults` key. Each value is read at creation and written back on a change only, so creating the
/// model writes nothing.
@MainActor
@Observable
final class ExperimentalSettings {
    private let store: any SettingsStore
    private var stored: [ExperimentalFeature: Bool]

    /// Reads every switch from `store`.
    init(store: any SettingsStore) {
        self.store = store
        stored = Dictionary(uniqueKeysWithValues: ExperimentalFeature.allCases.map { ($0, store.value(for: $0.setting)) })
    }

    /// Whether `feature` is on: its stored value when it is listed, its default otherwise (a hidden option never runs).
    func isOn(_ feature: ExperimentalFeature) -> Bool {
        guard feature.isListed else { return feature.setting.defaultValue }
        return stored[feature] ?? feature.setting.defaultValue
    }

    /// Turns `feature` on or off; a hidden option cannot be changed.
    func set(_ feature: ExperimentalFeature, isOn: Bool) {
        guard feature.isListed, stored[feature] != isOn else { return }
        stored[feature] = isOn
        store.set(isOn, for: feature.setting)
    }

    /// `feature` in `settings`, or its default where none is in the environment (previews, hosted tests).
    static func isOn(_ feature: ExperimentalFeature, in settings: ExperimentalSettings?) -> Bool {
        settings?.isOn(feature) ?? feature.setting.defaultValue
    }
}
