import HFRModels
import Testing
@testable import HFRStorage

/// The two keys LOT-119 added for the settings screen (`Common.swift:32-37, 239-241` on legacy `master`).
@Suite struct GeneralSettingsKeyTests {
    @Test func startupScreenDefaultsToFavoritesAndReadsTheLegacyTabValues() {
        #expect(InMemorySettingsStore().value(for: SettingKey.startupScreen) == .favorites)
        let expected: [(String, StartupScreen)] = [
            ("tab:categories", .categories), ("tab:favorites", .favorites), ("tab:messages", .messages)
        ]
        for (raw, screen) in expected {
            let store = InMemorySettingsStore(["HFRswiftStartupScreen": .string(raw)])
            #expect(store.value(for: SettingKey.startupScreen) == screen)
        }
    }

    @Test(arguments: [SettingRawValue.string(""), .string("tab:more"), .string("categories"), .int(2), .bool(true)])
    func unknownStartupValueReadsAsFavorites(raw: SettingRawValue) {
        let store = InMemorySettingsStore([SettingKey.startupScreen.key: raw])
        #expect(store.value(for: SettingKey.startupScreen) == .favorites)
    }

    @Test func startupScreenIsWrittenAsTheLegacyString() {
        let store = InMemorySettingsStore()
        store.set(.messages, for: SettingKey.startupScreen)
        #expect(store.rawValue(forKey: "HFRswiftStartupScreen") == .string("tab:messages"))
    }

    @Test func openingLinksInTheSystemBrowserIsOffByDefaultAndTolerant() {
        #expect(!InMemorySettingsStore().value(for: SettingKey.opensLinksInDefaultBrowser))
        let store = InMemorySettingsStore()
        store.set(true, for: SettingKey.opensLinksInDefaultBrowser)
        #expect(store.rawValue(forKey: "open_links_in_default_browser") == .bool(true))
        #expect(store.value(for: SettingKey.opensLinksInDefaultBrowser))
        let legacy = InMemorySettingsStore(["open_links_in_default_browser": .int(1)])
        #expect(legacy.value(for: SettingKey.opensLinksInDefaultBrowser))
    }

    @Test func textSizePercentDefaultsClampsAndFallsBackToTheLegacyScale() {
        #expect(SettingKey.textSizePercent(from: InMemorySettingsStore()) == 100)
        let legacy = InMemorySettingsStore(["text_size_scale": .int(120)])
        #expect(SettingKey.textSizePercent(from: legacy) == 120)
        let stored = InMemorySettingsStore(["text_size_scale": .int(120), "text_size_percent": .int(85)])
        #expect(SettingKey.textSizePercent(from: stored) == 85)
        let low = InMemorySettingsStore(["text_size_percent": .int(10)])
        #expect(SettingKey.textSizePercent(from: low) == 70)
        let high = InMemorySettingsStore(["text_size_percent": .string("999")])
        #expect(SettingKey.textSizePercent(from: high) == 130)
    }
}
