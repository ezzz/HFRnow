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
}
