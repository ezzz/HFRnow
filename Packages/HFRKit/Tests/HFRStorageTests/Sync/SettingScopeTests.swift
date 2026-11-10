import Testing
@testable import HFRStorage

/// `Setting.scope` against the ADR 0013 matrix (appendix E), key by key (LOT-172).
@Suite struct SettingScopeTests {
    /// The matrix, for every key of the catalogue.
    static let matrix: [String: SettingScope] = [
        "vos_sujets": .synced, "sujets_avec_cat": .synced, "favorites_auto_refresh": .synced,
        "HFRswiftStartupScreen": .synced, "open_links_in_default_browser": .synced,
        "topic_page_swipe_navigation": .synced, "mp_list_display": .synced, "reply_button_behavior": .synced,
        "auto_theme": .synced, "theme": .synced, "theme_style": .synced,
        "theme_day_color_action": .synced, "theme_night_color_action": .synced,
        "theme_day_color_love": .synced, "theme_night_color_love": .synced,
        "theme_day_color_superfavori": .synced, "theme_night_color_superfavori": .synced,
        "theme_night_brightness": .synced,
        "blacklist_hide_pseudo": .synced, "filter_posts_quotes": .synced, "filter_posts_min_quotes": .synced,
        "display_sig": .synced, "rehost_use_link": .synced, "rehost_resize_before_upload": .synced,
        "compact_mode": .device, "tabbar_minimize_on_scroll": .device, "text_size_scale": .device,
        "text_size_percent": .device, "haptics": .device, "landscape_mode": .device, "icon": .device,
        "theme_dark_style": .device, "mp_badge_enabled": .device, "display_images": .device, "recherche_categorie": .device,
        "FavoritesShowCollapsedSections": .device, "HFRswiftGlobalTopicListFlag": .device,
        // Dropped or replaced: never synced. `size_smileys` has no reader (LOT-119), `embedded_videos` was removed from
        // legacy by `d645f52`, `mpstorage_active` becomes the per-account record of §7, `mpstorage_last_rw` is this
        // device's last sync.
        "size_smileys": .device, "embedded_videos": .device, "mpstorage_active": .device, "mpstorage_last_rw": .device
    ]

    @Test func everyCatalogueKeyHasTheMatrixScope() {
        #expect(Set(SettingKey.allKeys) == Set(Self.matrix.keys))
        for setting in SettingKey.all {
            #expect(setting.scope == Self.matrix[setting.key], "\(setting.key)")
        }
        #expect(SettingKey.syncedKeys == Set(Self.matrix.filter { $0.value == .synced }.keys))
    }

    @Test func theSevenThemeKeysSyncUnchanged() {
        let theme = [
            "theme_day_color_action", "theme_night_color_action", "theme_day_color_love", "theme_night_color_love",
            "theme_day_color_superfavori", "theme_night_color_superfavori", "theme_night_brightness"
        ]
        #expect(Set(theme).isSubset(of: SettingKey.syncedKeys))
    }

    /// ADR 0013 §1 rule 2: no cookie, token or draft ever enters iCloud KVS.
    @Test func noSyncedKeyHoldsASecretOrADraft() {
        let forbidden = ["md_user", "md_passs", "md_id", "md_data", "hash_check", "composerDraftText", "brouillon"]
        #expect(SettingKey.syncedKeys.isDisjoint(with: forbidden))
        for key in SettingKey.syncedKeys {
            let lowered = key.lowercased()
            #expect(!["cookie", "token", "hash", "draft", "password", "md_"].contains { lowered.contains($0) }, "\(key)")
        }
    }

    @Test func syncedKeepsTheCodecAndTheDefault() {
        let setting = Setting.bool("example", default: true)
        #expect(setting.scope == .device)
        let synced = setting.synced
        #expect(synced.scope == .synced)
        #expect(synced.key == "example")
        #expect(synced.value(from: nil))
        #expect(synced.rawValue(for: false) == .bool(false))
    }
}
