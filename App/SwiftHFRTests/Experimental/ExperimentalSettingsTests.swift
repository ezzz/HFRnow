import HFRStorage
@testable import SwiftHFR
import Testing

/// Réglages › Expérimental (#903): one device key per option, read through `ExperimentalSettings` only, and no dead switch.
@MainActor
struct ExperimentalSettingsTests {
    @Test func everyOptionHasItsOwnDeviceKey() {
        let keys = ExperimentalFeature.allCases.map(\.setting.key)
        #expect(Set(keys).count == keys.count)
        #expect(ExperimentalFeature.allCases.allSatisfy { $0.setting.scope == .device })
        #expect(Set(keys).isSubset(of: Set(SettingKey.allKeys)))
    }

    /// Off by default, except the modern composer until #855 delivers the legacy one (the app always has a composer).
    @Test func everyOptionIsOffByDefaultButTheModernComposer() {
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        #expect(settings.isOn(.modernComposer))
        for feature in ExperimentalFeature.allCases where feature != .modernComposer { #expect(!settings.isOn(feature), "\(feature)") }
        #expect(ExperimentalSettings.isOn(.modernComposer, in: nil))
        #expect(!ExperimentalSettings.isOn(.flagIconRows, in: nil))
    }

    @Test func creatingTheModelWritesNothing() {
        let store = InMemorySettingsStore()
        _ = ExperimentalSettings(store: store)
        for feature in ExperimentalFeature.allCases { #expect(store.rawValue(forKey: feature.setting.key) == nil) }
    }

    @Test func aSwitchIsWrittenToItsKeyAndReadBack() {
        let store = InMemorySettingsStore()
        let settings = ExperimentalSettings(store: store)
        settings.set(.modernComposer, isOn: false)
        #expect(!settings.isOn(.modernComposer))
        #expect(store.rawValue(forKey: "experimental.modernComposer") == .bool(false))
        #expect(!ExperimentalSettings(store: store).isOn(.modernComposer))
    }

    /// An option whose path is not built yet is not listed, cannot be switched, and reads its default whatever the store holds.
    @Test func aHiddenOptionIsNeitherListedNorEffective() {
        let hidden: [ExperimentalFeature] = [.searchTab, .flagIconRows, .imageLoadingChoice]
        let store = InMemorySettingsStore(Dictionary(uniqueKeysWithValues: hidden.map { ($0.setting.key, SettingRawValue.bool(true)) }))
        let settings = ExperimentalSettings(store: store)
        for feature in hidden {
            #expect(!feature.isListed)
            #expect(!settings.isOn(feature), "\(feature)")
            settings.set(feature, isOn: true)
            #expect(!settings.isOn(feature), "\(feature)")
        }
        let listed = ExperimentalTheme.listed.flatMap(\.listedFeatures)
        #expect(listed == [.modernComposer, .mpStorageSwitches])
        #expect(ExperimentalTheme.listed == [.composer, .messages])
    }

    @Test func everyListedOptionExplainsItself() {
        for feature in ExperimentalFeature.allCases {
            #expect(!feature.title.isEmpty)
            #expect(feature.explanation.contains("Désactivé"), "\(feature): the ⓘ says what the switch-off path is")
        }
    }
}
