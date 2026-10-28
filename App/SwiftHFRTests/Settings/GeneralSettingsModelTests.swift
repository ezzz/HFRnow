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
        #expect(model.textSizePercent == 100)
        #expect(!model.compactMode)
    }

    @Test func storedLegacyValuesAreShown() {
        let store = InMemorySettingsStore([
            "HFRswiftStartupScreen": .string("tab:categories"), "landscape_mode": .string("none"),
            "open_links_in_default_browser": .bool(true), "text_size_percent": .int(120), "compact_mode": .bool(true)
        ])
        let model = GeneralSettingsModel(store: store)
        #expect(model.startupScreen == .categories)
        #expect(!model.allowsRotation)
        #expect(model.opensLinksInDefaultBrowser)
        #expect(model.textSizePercent == 120)
        #expect(model.compactMode)
    }

    @Test func everyChangeIsWrittenUnderItsLegacyKeyAndShape() {
        let store = InMemorySettingsStore()
        let model = GeneralSettingsModel(store: store)
        model.startupScreen = .messages
        model.allowsRotation = false
        model.opensLinksInDefaultBrowser = true
        model.textSizePercent = 85
        model.compactMode = true
        #expect(store.rawValue(forKey: "HFRswiftStartupScreen") == .string("tab:messages"))
        #expect(store.rawValue(forKey: "landscape_mode") == .string("none"))
        #expect(store.rawValue(forKey: "open_links_in_default_browser") == .bool(true))
        #expect(store.rawValue(forKey: "text_size_percent") == .int(85))
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
        #expect(GeneralSettingsModel(store: store).textSizePercent == 110)
    }

    @Test func textSizeGoesBelowTheDefaultAndStaysInRange() {
        let store = InMemorySettingsStore()
        let model = GeneralSettingsModel(store: store)
        model.textSizePercent = 70
        #expect(store.rawValue(forKey: "text_size_percent") == .int(70))
        model.textSizePercent = 10
        #expect(model.textSizePercent == 70)
        model.textSizePercent = 500
        #expect(model.textSizePercent == 130)
        #expect(store.rawValue(forKey: "text_size_percent") == .int(130))
    }
}
