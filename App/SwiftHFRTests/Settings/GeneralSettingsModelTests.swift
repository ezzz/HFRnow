import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct GeneralSettingsModelTests {
    @Test func emptyStoreShowsTheLegacyDefaults() {
        let model = GeneralSettingsModel(store: InMemorySettingsStore())
        #expect(model.startupScreen == .favorites)
        #expect(model.allowsRotation)
        #expect(!model.opensLinksInDefaultBrowser)
        #expect(model.textSizeScale == .percent100)
        #expect(!model.compactMode)
    }

    @Test func storedLegacyValuesAreShown() {
        let store = InMemorySettingsStore([
            "HFRswiftStartupScreen": .string("tab:categories"), "landscape_mode": .string("none"),
            "open_links_in_default_browser": .bool(true), "text_size_scale": .int(120), "compact_mode": .bool(true)
        ])
        let model = GeneralSettingsModel(store: store)
        #expect(model.startupScreen == .categories)
        #expect(!model.allowsRotation)
        #expect(model.opensLinksInDefaultBrowser)
        #expect(model.textSizeScale == .percent120)
        #expect(model.compactMode)
    }

    @Test func everyChangeIsWrittenUnderItsLegacyKeyAndShape() {
        let store = InMemorySettingsStore()
        let model = GeneralSettingsModel(store: store)
        model.startupScreen = .messages
        model.allowsRotation = false
        model.opensLinksInDefaultBrowser = true
        model.textSizeScale = .percent130
        model.compactMode = true
        #expect(store.rawValue(forKey: "HFRswiftStartupScreen") == .string("tab:messages"))
        #expect(store.rawValue(forKey: "landscape_mode") == .string("none"))
        #expect(store.rawValue(forKey: "open_links_in_default_browser") == .bool(true))
        #expect(store.rawValue(forKey: "text_size_scale") == .int(130))
        #expect(store.rawValue(forKey: "compact_mode") == .bool(true))
    }

    @Test func turningRotationBackOnWritesTheLegacyEnabledValue() {
        let store = InMemorySettingsStore(["landscape_mode": .string("none")])
        let model = GeneralSettingsModel(store: store)
        model.allowsRotation = true
        #expect(store.rawValue(forKey: "landscape_mode") == .string("galerie_message"))
    }

    @Test func creatingTheModelWritesNothing() {
        let store = InMemorySettingsStore()
        _ = GeneralSettingsModel(store: store)
        for key in SettingKey.allKeys { #expect(store.rawValue(forKey: key) == nil) }
    }

    @Test func rotationChangeNotifiesOnlyOnARealChange() {
        var notified = 0
        let model = GeneralSettingsModel(store: InMemorySettingsStore(), rotationChanged: { notified += 1 })
        model.allowsRotation = true
        #expect(notified == 0)
        model.allowsRotation = false
        model.allowsRotation = true
        #expect(notified == 2)
    }

    @Test func aTextSizeMigratedFromTheLegacyKeyIsShown() {
        let store = InMemorySettingsStore([SettingKey.legacyTopicTextSizeKey: .int(112)])
        _ = LegacySettingsNormalizer.run(on: store)
        #expect(GeneralSettingsModel(store: store).textSizeScale == .percent110)
    }

    @Test func textSizeTitlesFollowLegacy() {
        #expect(TextSizeScale.allCases.map(\.title) == ["Standard", "+10 %", "+20 %", "+30 %"])
    }
}
