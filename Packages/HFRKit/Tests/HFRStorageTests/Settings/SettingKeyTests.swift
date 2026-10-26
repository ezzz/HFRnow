import Foundation
import HFRModels
import Testing
@testable import HFRStorage

@Suite struct SettingKeyTests {
    @Test func keysAreUniqueAndKeepTheirLegacyNames() {
        #expect(Set(SettingKey.allKeys).count == SettingKey.allKeys.count)
        let legacy: Set = [
            "vos_sujets", "sujets_avec_cat", "favorites_auto_refresh", "compact_mode", "tabbar_minimize_on_scroll",
            "text_size_scale", "haptics", "landscape_mode", "icon", "auto_theme", "theme", "theme_style",
            "theme_day_color_action", "theme_night_color_action", "theme_day_color_love", "theme_night_color_love",
            "theme_day_color_superfavori", "theme_night_color_superfavori", "theme_night_brightness",
            "blacklist_hide_pseudo", "filter_posts_quotes", "filter_posts_min_quotes", "size_smileys",
            "embedded_videos", "display_sig", "display_images", "mpstorage_active", "mpstorage_last_rw",
            "mp_badge_enabled", "recherche_categorie", "rehost_use_link", "rehost_resize_before_upload"
        ]
        #expect(Set(SettingKey.allKeys) == legacy)
    }

    @Test func emptyStoreYieldsEveryDefault() {
        let store = InMemorySettingsStore()
        #expect(store.value(for: SettingKey.favoritesSource) == .flagsAndFavorites)
        #expect(store.value(for: SettingKey.favoritesGroupedByCategory))
        #expect(!store.value(for: SettingKey.favoritesAutoRefresh))
        #expect(!store.value(for: SettingKey.compactMode))
        #expect(store.value(for: SettingKey.tabBarMinimizesOnScroll))
        #expect(store.value(for: SettingKey.textSizeScale) == .percent100)
        #expect(store.value(for: SettingKey.haptics))
        #expect(store.value(for: SettingKey.landscapeMode) == .galerieMessage)
        #expect(store.value(for: SettingKey.appIconName) == "superblue")
        #expect(store.value(for: SettingKey.privateMessageBadge))
        #expect(store.value(for: SettingKey.autoTheme) == .system)
        #expect(store.value(for: SettingKey.manualTheme) == .light)
        #expect(store.value(for: SettingKey.themeStyle) == .modern)
        #expect(store.value(for: SettingKey.dayActionColor) == nil)
        #expect(store.value(for: SettingKey.nightBrightness) == nil)
        #expect(!store.value(for: SettingKey.hideBlocklistedPosts))
        #expect(store.value(for: SettingKey.quoteFilterExceptions) == .standard)
        #expect(store.value(for: SettingKey.quoteFilterMinimumCount) == 3)
        #expect(store.value(for: SettingKey.doubleSizeSmileys))
        #expect(store.value(for: SettingKey.embeddedVideos) == .inlinePlayer)
        #expect(!store.value(for: SettingKey.displaySignatures))
        #expect(store.value(for: SettingKey.displayImages) == .always)
        #expect(!store.value(for: SettingKey.mpStorageActive))
        #expect(store.value(for: SettingKey.mpStorageLastSync) == nil)
        #expect(store.value(for: SettingKey.searchCategory) == .forum(13))
        #expect(store.value(for: SettingKey.rehostLinkMode) == .imageWithLink)
        #expect(store.value(for: SettingKey.rehostMaxDimension) == .px1200)
    }

    @Test(arguments: [
        (SettingRawValue.bool(false), false), (.bool(true), true), (.int(0), false), (.int(1), true), (.int(5), true),
        (.string("1"), true), (.string("0"), false), (.string(" YES "), true), (.string("off"), false),
        (.string("On"), true), (.string("false"), false), (.double(0), false)
    ])
    func hapticsReadsEveryLegacyShape(raw: SettingRawValue, expected: Bool) {
        let store = InMemorySettingsStore([SettingKey.haptics.key: raw])
        #expect(store.value(for: SettingKey.haptics) == expected)
    }

    @Test func unparsableBooleanFallsBackToTheDefault() {
        let store = InMemorySettingsStore([SettingKey.haptics.key: .string("maybe")])
        #expect(store.value(for: SettingKey.haptics))
        let off = InMemorySettingsStore([SettingKey.compactMode.key: .string("maybe")])
        #expect(!off.value(for: SettingKey.compactMode))
    }

    @Test(arguments: [
        (SettingRawValue.string("0"), FavoritesSource.flagsAndFavorites), (.string("1"), .favoritesOnly),
        (.int(1), .favoritesOnly), (.int(0), .flagsAndFavorites), (.bool(true), .favoritesOnly),
        (.string("2"), .flagsAndFavorites), (.string("x"), .flagsAndFavorites), (.double(1.0), .favoritesOnly)
    ])
    func favoritesSourceCoercesStringAndInteger(raw: SettingRawValue, expected: FavoritesSource) {
        let store = InMemorySettingsStore([SettingKey.favoritesSource.key: raw])
        #expect(store.value(for: SettingKey.favoritesSource) == expected)
    }

    @Test func favoritesSourceIsWrittenAsTheLegacyString() {
        let store = InMemorySettingsStore()
        store.set(.favoritesOnly, for: SettingKey.favoritesSource)
        #expect(store.rawValue(forKey: "vos_sujets") == .string("1"))
    }

    @Test(arguments: [
        (SettingRawValue.int(0), AutoThemeMode.manual), (.int(3), .system), (.int(1), .system), (.int(2), .system),
        (.int(-4), .system), (.string("0"), .manual), (.string("junk"), .system)
    ])
    func autoThemeClampsUnknownValuesToSystem(raw: SettingRawValue, expected: AutoThemeMode) {
        let store = InMemorySettingsStore([SettingKey.autoTheme.key: raw])
        #expect(store.value(for: SettingKey.autoTheme) == expected)
    }

    @Test(arguments: [
        (SettingRawValue.int(1), ThemeVariant.dark), (.int(0), .light), (.int(7), .light), (.string("1"), .dark)
    ])
    func manualThemeIsDarkOnlyForOne(raw: SettingRawValue, expected: ThemeVariant) {
        let store = InMemorySettingsStore([SettingKey.manualTheme.key: raw])
        #expect(store.value(for: SettingKey.manualTheme) == expected)
    }

    @Test(arguments: [
        (SettingRawValue.string("none"), LandscapeMode.none), (.string("galerie_message"), .galerieMessage),
        (.string("whatever"), .galerieMessage), (.int(1), .galerieMessage)
    ])
    func landscapeModeIsOffOnlyForNone(raw: SettingRawValue, expected: LandscapeMode) {
        let store = InMemorySettingsStore([SettingKey.landscapeMode.key: raw])
        #expect(store.value(for: SettingKey.landscapeMode) == expected)
    }

    @Test(arguments: [
        (SettingRawValue.string("wl_pseudo"), QuoteFilterExceptions.standard), (.string("pseudo"), .mentionsOwnPseudo),
        (.string("wl"), .allowlistedAuthors), (.string(""), QuoteFilterExceptions()), (.string("other"), QuoteFilterExceptions())
    ])
    func quoteFilterUsesTheLegacySubstringRules(raw: SettingRawValue, expected: QuoteFilterExceptions) {
        let store = InMemorySettingsStore([SettingKey.quoteFilterExceptions.key: raw])
        #expect(store.value(for: SettingKey.quoteFilterExceptions) == expected)
    }

    @Test(arguments: [QuoteFilterExceptions.standard, .mentionsOwnPseudo, .allowlistedAuthors, QuoteFilterExceptions()])
    func quoteFilterRoundTrips(value: QuoteFilterExceptions) {
        let store = InMemorySettingsStore()
        store.set(value, for: SettingKey.quoteFilterExceptions)
        #expect(store.value(for: SettingKey.quoteFilterExceptions) == value)
    }

    @Test(arguments: [(0, 3), (-2, 3), (4, 4), (10, 10)])
    func minimumQuoteCountBelowOneReadsAsThree(stored: Int, expected: Int) {
        let store = InMemorySettingsStore([SettingKey.quoteFilterMinimumCount.key: .int(stored)])
        #expect(store.value(for: SettingKey.quoteFilterMinimumCount) == expected)
    }

    @Test func stringlyTypedFlagsFollowTheirLegacyEquality() {
        let store = InMemorySettingsStore([
            "display_sig": .string("yes"), "size_smileys": .string("default"), "embedded_videos": .string("both"),
            "display_images": .string("wifi")
        ])
        #expect(store.value(for: SettingKey.displaySignatures))
        #expect(!store.value(for: SettingKey.doubleSizeSmileys))
        #expect(store.value(for: SettingKey.embeddedVideos) == .playerAndLink)
        #expect(store.value(for: SettingKey.displayImages) == .wifiOnly)
        store.set(false, for: SettingKey.displaySignatures)
        store.set(true, for: SettingKey.doubleSizeSmileys)
        #expect(store.rawValue(forKey: "display_sig") == .string("no"))
        #expect(store.rawValue(forKey: "size_smileys") == .string("double"))
    }

    @Test func unknownEnumStringFallsBackToTheDefault() {
        let store = InMemorySettingsStore(["embedded_videos": .string("sometimes"), "display_images": .int(4)])
        #expect(store.value(for: SettingKey.embeddedVideos) == .inlinePlayer)
        #expect(store.value(for: SettingKey.displayImages) == .always)
    }

    @Test func searchCategoryAcceptsNumbersAndRejectsGarbage() {
        let store = InMemorySettingsStore(["recherche_categorie": .int(25)])
        #expect(store.value(for: SettingKey.searchCategory) == .forum(25))
        store.setRawValue(.string("prive"), forKey: "recherche_categorie")
        #expect(store.value(for: SettingKey.searchCategory) == .privateMessages)
        store.setRawValue(.string("-1"), forKey: "recherche_categorie")
        #expect(store.value(for: SettingKey.searchCategory) == .forum(13))
    }

    @Test func integerEnumsRejectValuesWithoutACase() {
        let store = InMemorySettingsStore([
            "text_size_scale": .int(115), "rehost_resize_before_upload": .int(500), "theme_style": .int(9),
            "rehost_use_link": .string("2")
        ])
        #expect(store.value(for: SettingKey.textSizeScale) == .percent100)
        #expect(store.value(for: SettingKey.rehostMaxDimension) == .px1200)
        #expect(store.value(for: SettingKey.themeStyle) == .modern)
        #expect(store.value(for: SettingKey.rehostLinkMode) == .linkOnly)
    }

    @Test func settingRoundTripsThroughTheStoreAndResetRestoresTheDefault() {
        let store = InMemorySettingsStore()
        store.set(.percent130, for: SettingKey.textSizeScale)
        #expect(store.value(for: SettingKey.textSizeScale) == .percent130)
        store.reset(SettingKey.textSizeScale)
        #expect(store.rawValue(forKey: "text_size_scale") == nil)
        #expect(store.value(for: SettingKey.textSizeScale) == .percent100)
    }

    @Test func settingNilOptionalRemovesTheKey() {
        let store = InMemorySettingsStore()
        store.set(ThemeColor(red: 1, green: 0, blue: 0.5), for: SettingKey.dayActionColor)
        #expect(store.rawValue(forKey: "theme_day_color_action") == .string("{1.000, 0.000, 0.500, 1.000}"))
        store.set(nil, for: SettingKey.dayActionColor)
        #expect(store.rawValue(forKey: "theme_day_color_action") == nil)
    }

    @Test func lastSyncDateRoundTripsAndDashMeansNever() {
        let store = InMemorySettingsStore(["mpstorage_last_rw": .string("-")])
        #expect(store.value(for: SettingKey.mpStorageLastSync) == nil)
        let date = Date(timeIntervalSince1970: 1_761_000_000)
        store.set(date, for: SettingKey.mpStorageLastSync)
        #expect(store.value(for: SettingKey.mpStorageLastSync) == date)
        let text = store.rawValue(forKey: "mpstorage_last_rw")
        guard case .string(let value)? = text else {
            Issue.record("expected a string")
            return
        }
        #expect(value.count == 19)
        #expect(value.dropFirst(2).first == "-")
    }
}
