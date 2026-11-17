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

    /// Every option is off by default; the modern composer too since #855 (operator, 2026-11-14: legacy's composer is the default).
    @Test func everyOptionIsOffByDefault() {
        let settings = ExperimentalSettings(store: InMemorySettingsStore())
        for feature in ExperimentalFeature.allCases { #expect(!settings.isOn(feature), "\(feature)") }
        #expect(!ExperimentalSettings.isOn(.modernComposer, in: nil))
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
        settings.set(.modernComposer, isOn: true)
        #expect(settings.isOn(.modernComposer))
        #expect(store.rawValue(forKey: "experimental.modernComposer") == .bool(true))
        #expect(ExperimentalSettings(store: store).isOn(.modernComposer))
    }

    /// An option whose path is not built yet is not listed, cannot be switched, and reads its default whatever the store holds.
    @Test func aHiddenOptionIsNeitherListedNorEffective() {
        let hidden: [ExperimentalFeature] = [.flagIconRows]
        let store = InMemorySettingsStore(Dictionary(uniqueKeysWithValues: hidden.map { ($0.setting.key, SettingRawValue.bool(true)) }))
        let settings = ExperimentalSettings(store: store)
        for feature in hidden {
            #expect(!feature.isListed)
            #expect(!settings.isOn(feature), "\(feature)")
            settings.set(feature, isOn: true)
            #expect(!settings.isOn(feature), "\(feature)")
        }
        let listed = ExperimentalTheme.listed.flatMap(\.listedFeatures)
        #expect(listed == [.modernComposer, .searchTab, .mpStorageSwitches, .imageLoadingChoice])
        #expect(ExperimentalTheme.listed == [.composer, .navigation, .messages, .imageLoading])
    }

    @Test func everyListedOptionExplainsItself() {
        for feature in ExperimentalFeature.allCases {
            #expect(!feature.title.isEmpty)
            #expect(feature.explanation.contains("Désactivé"), "\(feature): the ⓘ says what the switch-off path is")
        }
    }
}

/// Réglages › Expérimental is one row that opens a page grouped by theme (#971).
@MainActor
struct ExperimentalPageTests {
    @Test func thePageGroupsEveryListedOptionByTheme() {
        let groups = ExperimentalPageLayout.groups()
        #expect(groups.map(\.theme) == [.composer, .navigation, .messages, .imageLoading])
        #expect(groups == ExperimentalTheme.listed.map { ExperimentalPageLayout.Group(theme: $0, features: $0.listedFeatures) })
        #expect(groups.flatMap(\.features) == ExperimentalFeature.allCases.filter(\.isListed))
        #expect(groups.allSatisfy { group in group.features.allSatisfy { $0.theme == group.theme } })
    }

    /// The row shows when the page has a group, so a theme without a listed option is never a group.
    @Test func aThemeWithoutListedOptionIsLeftOut() {
        let themes = ExperimentalPageLayout.groups().map(\.theme)
        #expect(!themes.contains(.lists))
        #expect(!ExperimentalPageLayout.groups().isEmpty)
        #expect(ExperimentalPageLayout.groups().allSatisfy { !$0.features.isEmpty })
    }

    /// The move to a page keeps every key: nothing is read or written under another name.
    @Test func switchesKeepTheirStorageKey() {
        let store = InMemorySettingsStore()
        let settings = ExperimentalSettings(store: store)
        settings.set(.mpStorageSwitches, isOn: true)
        #expect(store.rawValue(forKey: "experimental.mpStorageSwitches") == .bool(true))
    }
}
