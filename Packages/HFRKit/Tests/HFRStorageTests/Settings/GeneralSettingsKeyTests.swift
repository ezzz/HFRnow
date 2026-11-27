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

/// The key LOT-171 added: a new setting, so the default must leave the single list untouched.
@Suite struct MPListDisplayKeyTests {
    @Test func absentReadsAsSingleAndRoundTrips() {
        let store = InMemorySettingsStore()
        #expect(store.value(for: SettingKey.mpListDisplay) == .single)
        store.set(.split, for: SettingKey.mpListDisplay)
        #expect(store.rawValue(forKey: "mp_list_display") == .string("split"))
        #expect(store.value(for: SettingKey.mpListDisplay) == .split)
    }

    @Test(arguments: [SettingRawValue.string(""), .string("two"), .int(1), .bool(true)])
    func unknownValueReadsAsSingle(raw: SettingRawValue) {
        let store = InMemorySettingsStore([SettingKey.mpListDisplay.key: raw])
        #expect(store.value(for: SettingKey.mpListDisplay) == .single)
    }
}

/// The per-account key #899 added: the last Messages switch position, seeded once from the retired `mp_list_display`.
@Suite struct MPListSegmentStoreTests {
    @Test func noAccountOrAnEmptyOneReadsAsAll() {
        let store = MPListSegmentStore(settings: InMemorySettingsStore(["mp_list_display": .string("split")]))
        #expect(store.segment(for: nil) == .all)
        #expect(store.segment(for: "\u{200B}") == .all)
    }

    @Test(arguments: [("single", MPSegment.all), ("split", .oneToOne), ("two", .all)])
    func absentSeedsFromTheOldSetting(old: String, expected: MPSegment) {
        let store = MPListSegmentStore(settings: InMemorySettingsStore(["mp_list_display": .string(old)]))
        #expect(store.segment(for: "Alice") == expected)
    }

    @Test func accountsKeepDifferentChoicesUnderTheirAccountKey() {
        let settings = InMemorySettingsStore(["mp_list_display": .string("split")])
        let store = MPListSegmentStore(settings: settings)
        store.set(.group, for: "Alice")
        #expect(settings.rawValue(forKey: "mp_list_segment.alice") == .string("group"))
        #expect(store.segment(for: "ALICE") == .group)
        // Bob has stored nothing: the retired setting seeds him, not Alice's choice.
        #expect(store.segment(for: "Bob") == .oneToOne)
        store.set(.all, for: "Bob")
        #expect(store.segment(for: "Bob") == .all)
        #expect(store.segment(for: "Alice") == .group)
    }

    @Test(arguments: [SettingRawValue.string(""), .string("everything"), .int(1), .bool(true)])
    func anUnknownStoredValueReadsAsAll(raw: SettingRawValue) {
        let store = MPListSegmentStore(settings: InMemorySettingsStore(
            ["mp_list_display": .string("split"), "mp_list_segment.alice": raw]
        ))
        #expect(store.segment(for: "Alice") == .all)
    }
}

/// The key LOT-086 added: legacy's raw values. The default is `forum` since #1016; only an absent key takes it.
@Suite struct ReplyButtonBehaviorKeyTests {
    @Test func absentReadsAsForumAndRoundTripsLegacyValues() {
        let store = InMemorySettingsStore()
        #expect(store.value(for: SettingKey.replyButtonBehavior) == .forum)
        for (raw, behavior) in [("forum", ReplyButtonBehavior.forum), ("hidden", .hidden), ("quick", .quick)] {
            store.set(behavior, for: SettingKey.replyButtonBehavior)
            #expect(store.rawValue(forKey: "reply_button_behavior") == .string(raw))
            #expect(store.value(for: SettingKey.replyButtonBehavior) == behavior)
        }
    }

    @Test func importedLegacyValueIsRead() {
        let store = InMemorySettingsStore()
        store.setRawValue(.string("forum"), forKey: "reply_button_behavior")
        #expect(store.value(for: SettingKey.replyButtonBehavior) == .forum)
        store.setRawValue(.string("nonsense"), forKey: "reply_button_behavior")
        #expect(store.value(for: SettingKey.replyButtonBehavior) == .forum)
    }

    /// #1016: a member who chose another value keeps it; a stored `quick` is not "never set".
    @Test(arguments: [("quick", ReplyButtonBehavior.quick), ("hidden", .hidden), ("forum", .forum)])
    func aStoredValueIsKeptWhateverTheDefault(raw: String, expected: ReplyButtonBehavior) {
        let store = InMemorySettingsStore(["reply_button_behavior": .string(raw)])
        #expect(store.value(for: SettingKey.replyButtonBehavior) == expected)
    }

    /// The normalizer run at launch neither writes nor drops the key, so an absent one stays absent (and reads `forum`).
    @Test func theLaunchNormalizerLeavesTheKeyAlone() {
        let absent = InMemorySettingsStore()
        LegacySettingsNormalizer.run(on: absent)
        #expect(absent.rawValue(forKey: "reply_button_behavior") == nil)
        #expect(absent.value(for: SettingKey.replyButtonBehavior) == .forum)
        let quick = InMemorySettingsStore(["reply_button_behavior": .string("quick")])
        LegacySettingsNormalizer.run(on: quick)
        #expect(quick.value(for: SettingKey.replyButtonBehavior) == .quick)
    }
}
