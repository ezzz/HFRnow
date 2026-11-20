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
        #expect(!ExperimentalSettings.isOn(.denseRows, in: nil))
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

    /// Every option is listed once built, section by section (#905 built the last hidden one); the enum is declared in that order.
    @Test func everyOptionIsListed() {
        let listed = ExperimentalTheme.listed.flatMap(\.listedFeatures)
        #expect(listed == [.modernComposer, .searchTab, .denseRows, .mpDarkTopic, .imageLoadingChoice])
        #expect(ExperimentalTheme.listed == [.composer, .navigation, .lists, .messages, .imageLoading])
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
        // The dense rows (#905) are the « Listes » section, between the tab bar and the messages (enum order).
        #expect(groups.map(\.theme) == [.composer, .navigation, .lists, .messages, .imageLoading])
        #expect(groups == ExperimentalTheme.listed.map { ExperimentalPageLayout.Group(theme: $0, features: $0.listedFeatures) })
        #expect(groups.flatMap(\.features) == ExperimentalFeature.allCases)
        #expect(groups.allSatisfy { group in group.features.allSatisfy { $0.theme == group.theme } })
    }

    /// The row shows when the page has a group, so a theme without a listed option is never a group.
    @Test func aThemeWithoutListedOptionIsLeftOut() {
        let themes = ExperimentalPageLayout.groups().map(\.theme)
        // Whatever is listed: a theme is a group exactly when it has a listed option, so a theme with none is never one.
        #expect(themes == ExperimentalTheme.allCases.filter { !$0.listedFeatures.isEmpty })
        #expect(ExperimentalTheme.allCases.filter { $0.listedFeatures.isEmpty }.allSatisfy { !themes.contains($0) })
        #expect(!ExperimentalPageLayout.groups().isEmpty)
        #expect(ExperimentalPageLayout.groups().allSatisfy { !$0.features.isEmpty })
    }

    /// #1014: the launch migration runs before the switches are read, so a member who had #859's option on sees the dark topic on
    /// at that launch (`SwiftHFRApp.init` creates `ExperimentalSettings` after `LegacySettingsNormalizer.run`).
    @Test func aMigratedDarkTopicChoiceIsReadAtTheSameLaunch() {
        let store = InMemorySettingsStore(["experimental.mpStorageSwitches": .bool(true)])
        #expect(!ExperimentalSettings(store: store).isOn(.mpDarkTopic)) // read before the migration: the bug the order avoids
        LegacySettingsNormalizer.run(on: store)
        #expect(ExperimentalSettings(store: store).isOn(.mpDarkTopic))
    }

    /// The move to a page keeps every key: nothing is read or written under another name.
    @Test func switchesKeepTheirStorageKey() {
        let store = InMemorySettingsStore()
        let settings = ExperimentalSettings(store: store)
        settings.set(.mpDarkTopic, isOn: true)
        #expect(store.rawValue(forKey: "experimental.mpDarkTopic") == .bool(true))
    }
}

/// #1128: one spacing between a switch's title and its description, read by every Réglages row that shows a description under
/// its control (it was 2 pt on two rows and 6 pt on another; the operator kept 6 pt).
@MainActor
struct SettingsRowSpacingTests {
    /// 6 pt: the Expérimental rows' spacing, kept by the operator (2026-11-18) over the 2 pt of the other two rows.
    @Test func theSpacingIsTheSixPointsTheOperatorKept() {
        #expect(SettingsRowSpacing.titleToDescription == 6)
    }

    @Test func everyRowWithADescriptionUnderItsControlReadsTheConstant() {
        #expect(ExperimentalFeatureRow.descriptionSpacing == SettingsRowSpacing.titleToDescription)
        #expect(MPStorageSettingsRows.descriptionSpacing == SettingsRowSpacing.titleToDescription)
    }
}
