import Foundation
import Testing
@testable import HFRStorage

@Suite struct UserDefaultsSettingsStoreTests {
    private func makeDefaults() -> (UserDefaults, String) {
        let name = "SettingsTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name) ?? .standard, name)
    }

    @Test func roundTripsEveryRawShapeWithoutConfusingBoolAndInteger() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        store.setRawValue(.bool(true), forKey: "b")
        store.setRawValue(.int(1), forKey: "i")
        store.setRawValue(.double(0.5), forKey: "d")
        store.setRawValue(.string("s"), forKey: "s")
        #expect(store.rawValue(forKey: "b") == .bool(true))
        #expect(store.rawValue(forKey: "i") == .int(1))
        #expect(store.rawValue(forKey: "d") == .double(0.5))
        #expect(store.rawValue(forKey: "s") == .string("s"))
        store.removeValue(forKey: "s")
        #expect(store.rawValue(forKey: "s") == nil)
    }

    @Test func readsValuesWrittenByLegacyCode() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("1", forKey: "vos_sujets")
        defaults.set(3, forKey: "auto_theme")
        defaults.set(true, forKey: "haptics")
        defaults.set(Data([1, 2]), forKey: "text_size_scale")
        let store = UserDefaultsSettingsStore(defaults: defaults)
        #expect(store.value(for: SettingKey.favoritesSource) == .favoritesOnly)
        #expect(store.value(for: SettingKey.autoTheme) == .system)
        #expect(store.value(for: SettingKey.haptics))
        #expect(store.value(for: SettingKey.textSizeScale) == .percent100)
    }

    @Test func neverRegistersDefaults() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = UserDefaultsSettingsStore(defaults: defaults)
        _ = store.value(for: SettingKey.haptics)
        #expect(defaults.object(forKey: "haptics") == nil)
    }
}
