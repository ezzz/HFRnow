import Testing
@testable import HFRStorage

@Suite struct LegacySettingsNormalizerTests {
    @Test func clampsUnknownAutoThemeToSystemInTheStore() {
        let store = InMemorySettingsStore(["auto_theme": .int(2)])
        #expect(LegacySettingsNormalizer.run(on: store))
        #expect(store.rawValue(forKey: "auto_theme") == .int(3))
    }

    @Test(arguments: [0, 3])
    func keepsValidAutoTheme(value: Int) {
        let store = InMemorySettingsStore(["auto_theme": .int(value)])
        #expect(!LegacySettingsNormalizer.run(on: store))
        #expect(store.rawValue(forKey: "auto_theme") == .int(value))
    }

    @Test func purgesDeprecatedKeysOnly() {
        let store = InMemorySettingsStore([
            "force_manual_theme": .bool(true), "auto_theme_day_time": .string("7:00"), "auto_theme_night_time": .string("21:00"),
            "theme": .int(1)
        ])
        #expect(LegacySettingsNormalizer.run(on: store))
        for key in SettingKey.deprecatedKeys { #expect(store.rawValue(forKey: key) == nil) }
        #expect(store.rawValue(forKey: "theme") == .int(1))
    }

    @Test(arguments: [
        (100, 100), (110, 110), (115, 110), (118, 120), (105, 100), (90, 100), (400, 130), (-5, 100),
        (Int.max, 130), (Int.min, 100)
    ])
    func migratesTopicSizeToTheNearestScaleOnce(legacy: Int, expected: Int) {
        let store = InMemorySettingsStore(["size_text_topics": .int(legacy)])
        #expect(LegacySettingsNormalizer.run(on: store))
        #expect(store.rawValue(forKey: "text_size_scale") == .int(expected))
        #expect(store.rawValue(forKey: "size_text_topics") == nil)
        store.setRawValue(.int(130), forKey: "text_size_scale")
        #expect(!LegacySettingsNormalizer.run(on: store))
        #expect(store.rawValue(forKey: "text_size_scale") == .int(130))
    }

    @Test func resettingTheScaleIsNotUndoneByTheNextLaunch() {
        let store = InMemorySettingsStore(["size_text_topics": .int(120)])
        LegacySettingsNormalizer.run(on: store)
        store.reset(SettingKey.textSizeScale)
        #expect(!LegacySettingsNormalizer.run(on: store))
        #expect(store.rawValue(forKey: "text_size_scale") == nil)
    }

    @Test func doesNotInventValuesOnAnEmptyStore() {
        let store = InMemorySettingsStore()
        #expect(!LegacySettingsNormalizer.run(on: store))
        for key in SettingKey.allKeys { #expect(store.rawValue(forKey: key) == nil) }
    }

    @Test func doesNotForceDisplayImagesLikeLegacy() {
        let store = InMemorySettingsStore(["display_images": .string("no")])
        LegacySettingsNormalizer.run(on: store)
        #expect(store.value(for: SettingKey.displayImages) == .never)
    }
}
