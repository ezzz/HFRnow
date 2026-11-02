import Foundation
import HFRModels

/// The catalogue of user preferences. Every key keeps its legacy `UserDefaults` name (audit E §3.1) so an update
/// from the old app finds the user's choices untouched; SwiftUI `@AppStorage` can reuse `key` and `defaultValue`.
///
/// Out of scope: counters and UI state living in defaults (`nb_mp`, `SuperFavoritesIds`, ... E §3.2), owned by their stores.
public enum SettingKey {
    // MARK: Favorites

    /// `vos_sujets`: which list the Favorites tab shows.
    public static let favoritesSource = Setting<FavoritesSource>(
        key: "vos_sujets",
        defaultValue: .flagsAndFavorites,
        decode: { SettingCoercion.int($0).map(FavoritesSource.legacyDecode) },
        // The legacy seed and `@AppStorage` hold a string; `integerForKey:` coerces it.
        encode: { .string(String($0.rawValue)) }
    ).synced
    /// `sujets_avec_cat`: group favorites by category.
    public static let favoritesGroupedByCategory = Setting.bool("sujets_avec_cat", default: true).synced
    /// `favorites_auto_refresh`.
    public static let favoritesAutoRefresh = Setting.bool("favorites_auto_refresh", default: false).synced

    // MARK: Interface

    /// `compact_mode`.
    public static let compactMode = Setting.bool("compact_mode", default: false)
    /// `tabbar_minimize_on_scroll`.
    public static let tabBarMinimizesOnScroll = Setting.bool("tabbar_minimize_on_scroll", default: true)
    /// `text_size_scale`: replaces the three legacy size keys (see `LegacySettingsNormalizer`).
    public static let textSizeScale = Setting.integerEnum("text_size_scale", default: TextSizeScale.percent100)
    /// `text_size_percent` (LOT-119, operator decision 2026-10-28): in-app text size in percent, an offset on top of Dynamic
    /// Type. Goes below 100 for a denser display; stored values are clamped to `textSizePercentRange`. Absent, a legacy
    /// `text_size_scale` is the starting point (`textSizePercent(from:)`).
    public static let textSizePercent = Setting(
        key: "text_size_percent",
        defaultValue: 100,
        decode: { SettingCoercion.int($0).map { min(max($0, textSizePercentRange.lowerBound), textSizePercentRange.upperBound) } },
        encode: { .int($0) }
    )
    /// Bounds of `textSizePercent`, in steps of `textSizePercentStep`.
    public static let textSizePercentRange = 70...130
    /// Slider step of `textSizePercent`.
    public static let textSizePercentStep = 5
    /// The text size to show: `text_size_percent` when stored, else the legacy `text_size_scale`, else 100.
    public static func textSizePercent(from store: any SettingsStore) -> Int {
        store.rawValue(forKey: textSizePercent.key) == nil
            ? store.value(for: textSizeScale).rawValue
            : store.value(for: textSizePercent)
    }
    /// `haptics`: tolerant of numbers and strings (`AppHaptics.isEnabled`).
    public static let haptics = Setting.bool("haptics", default: true)
    /// `landscape_mode`: any stored string other than `none` allows rotation, like the legacy `rawValue != "none"` test.
    public static let landscapeMode = Setting.stringEnum(
        "landscape_mode",
        default: LandscapeMode.galerieMessage,
        fallback: { _ in .galerieMessage }
    )
    /// `icon`: alternate icon name (`superblue`, `classic`, `classic-red`, `redface`, `redface-blue`, `beta`, `blue`, `white`).
    public static let appIconName = Setting.string("icon", default: "superblue")
    /// `mp_badge_enabled`.
    public static let privateMessageBadge = Setting.bool("mp_badge_enabled", default: true)
    /// `HFRswiftStartupScreen` (`Common.swift:32-37`): an unknown value falls back to the favourites default, like
    /// `AppStartupScreen.rootTab(for:)`. Added by LOT-119, which owns the settings screen.
    public static let startupScreen = Setting.stringEnum("HFRswiftStartupScreen", default: StartupScreen.favorites).synced
    /// `open_links_in_default_browser` (`Common.swift:239-241`): follow external links in the system browser instead of
    /// the in-app one. Added by LOT-119.
    public static let opensLinksInDefaultBrowser = Setting.bool("open_links_in_default_browser", default: false).synced

    // MARK: Theme

    /// `auto_theme`: 0 manual, 3 follow the system; any other stored value is normalised to the system mode
    /// (`normalizeThemeDefaultsIfNeeded`, `Common.swift:276-283`).
    public static let autoTheme = Setting.integerEnum("auto_theme", default: AutoThemeMode.system, fallback: { _ in .system }).synced
    /// `theme`: the manual variant; legacy treats anything but 1 as light (`Common.swift:316-318`).
    public static let manualTheme = Setting.integerEnum("theme", default: ThemeVariant.light, fallback: { _ in .light }).synced
    /// `theme_style`.
    public static let themeStyle = Setting.integerEnum("theme_style", default: ThemeStyle.modern).synced
    /// `theme_day_color_action`: nil means the computed default.
    public static let dayActionColor = colorSetting("theme_day_color_action")
    /// `theme_night_color_action`.
    public static let nightActionColor = colorSetting("theme_night_color_action")
    /// `theme_day_color_love`.
    public static let dayLoveColor = colorSetting("theme_day_color_love")
    /// `theme_night_color_love`.
    public static let nightLoveColor = colorSetting("theme_night_color_love")
    /// `theme_day_color_superfavori`.
    public static let daySuperFavoriteColor = colorSetting("theme_day_color_superfavori")
    /// `theme_night_color_superfavori`.
    public static let nightSuperFavoriteColor = colorSetting("theme_night_color_superfavori")
    /// `theme_night_brightness`: nil means the computed default.
    public static let nightBrightness = Setting.optionalDouble("theme_night_brightness").synced

    // MARK: Messages

    /// `blacklist_hide_pseudo`: hide blocklisted posts entirely (wire key keeps the legacy name).
    public static let hideBlocklistedPosts = Setting.bool("blacklist_hide_pseudo", default: false).synced
    /// `filter_posts_quotes`.
    public static let quoteFilterExceptions = Setting(
        key: "filter_posts_quotes",
        defaultValue: QuoteFilterExceptions.standard,
        decode: { SettingCoercion.string($0).map(QuoteFilterExceptions.init(storedString:)) },
        encode: { .string($0.storedString) }
    ).synced
    /// `filter_posts_min_quotes`: a value <= 0 reads as 3 (`ParseMessagesOperation.m:341-343`).
    public static let quoteFilterMinimumCount = Setting.int("filter_posts_min_quotes", default: 3, isValid: { $0 > 0 }).synced
    /// `size_smileys`: `double` (default) or `default`; the legacy test is `isEqualToString:@"double"`.
    public static let doubleSizeSmileys = Setting(
        key: "size_smileys",
        defaultValue: true,
        decode: { SettingCoercion.string($0).map { $0 == "double" } },
        encode: { .string($0 ? "double" : "default") }
    )
    /// `embedded_videos`.
    public static let embeddedVideos = Setting.stringEnum("embedded_videos", default: EmbeddedVideosMode.inlinePlayer)
    /// `display_sig`: `yes`/`no`; the legacy test is `isEqualToString:@"yes"`.
    public static let displaySignatures = Setting(
        key: "display_sig",
        defaultValue: false,
        decode: { SettingCoercion.string($0).map { $0 == "yes" } },
        encode: { .string($0 ? "yes" : "no") }
    ).synced
    /// `display_images`. Legacy forced `yes` at every launch with no UI; here it is an ordinary setting whose default is
    /// `wifi` (operator decision for policy C, LOT-071 D-071-1 and LOT-083): third-party images load by themselves on Wi-Fi
    /// only. A value stored by the user or imported from legacy is kept.
    public static let displayImages = Setting.stringEnum("display_images", default: ImageDisplayMode.wifiOnly)

    // MARK: Private messages storage

    /// `mpstorage_active`: MPStorage synchronisation switch (off by default).
    public static let mpStorageActive = Setting.bool("mpstorage_active", default: false)
    /// `mpstorage_last_rw`: time of the last synchronisation; legacy `-` reads as nil. Legacy never persisted it (E §7.1).
    public static let mpStorageLastSync = Setting<Date?>(
        key: "mpstorage_last_rw",
        defaultValue: nil,
        decode: { SettingCoercion.string($0).flatMap(LastSyncDate.date(from:)) },
        encode: { $0.map { .string(LastSyncDate.string(from: $0)) } }
    )

    // MARK: Search and rehost

    /// `recherche_categorie`: last category chosen in the search form (default 13, Discussions).
    public static let searchCategory = Setting(
        key: "recherche_categorie",
        defaultValue: CategoryID.forum(13),
        decode: { SettingCoercion.string($0).flatMap { CategoryID(queryValue: $0) } },
        encode: { .string($0.queryValue) }
    )
    /// `rehost_use_link`.
    public static let rehostLinkMode = Setting.integerEnum("rehost_use_link", default: RehostLinkMode.imageWithLink).synced
    /// `rehost_resize_before_upload`.
    public static let rehostMaxDimension = Setting.integerEnum("rehost_resize_before_upload", default: RehostMaxDimension.px1200).synced

    // MARK: Legacy keys

    /// Keys the legacy app removed at launch and the new app never reads (`removeDeprecatedThemeKeysIfNeeded`).
    public static let deprecatedKeys = ["force_manual_theme", "auto_theme_day_time", "auto_theme_night_time"]
    /// Pre-`text_size_scale` topic size, read once by the migration (`AppSettingsView.swift:325-335`).
    public static let legacyTopicTextSizeKey = "size_text_topics"

    /// Every setting of the catalogue with its scope, in catalogue order.
    public static let all: [any CatalogueSetting] = [
        favoritesSource, favoritesGroupedByCategory, favoritesAutoRefresh, compactMode,
        tabBarMinimizesOnScroll, textSizeScale, textSizePercent, haptics, landscapeMode, appIconName,
        privateMessageBadge, startupScreen, opensLinksInDefaultBrowser, autoTheme, manualTheme, themeStyle,
        dayActionColor, nightActionColor, dayLoveColor, nightLoveColor, daySuperFavoriteColor,
        nightSuperFavoriteColor, nightBrightness, hideBlocklistedPosts, quoteFilterExceptions,
        quoteFilterMinimumCount, doubleSizeSmileys, embeddedVideos, displaySignatures, displayImages, mpStorageActive,
        mpStorageLastSync, searchCategory, rehostLinkMode, rehostMaxDimension
    ]

    /// Every key of the catalogue, for tests and diagnostics.
    public static let allKeys: [String] = all.map(\.key)

    /// The keys that sync through the iCloud key-value store (ADR 0013 matrix E).
    public static let syncedKeys: Set<String> = Set(all.filter { $0.scope == .synced }.map(\.key))

    /// The 7 theme keys sync unchanged (ADR 0013 §8, theme parity).
    private static func colorSetting(_ key: String) -> Setting<ThemeColor?> {
        Setting(
            key: key,
            defaultValue: nil,
            scope: .synced,
            decode: { SettingCoercion.string($0).flatMap { ThemeColor(serialized: $0) } },
            encode: { $0.map { .string($0.serialized) } }
        )
    }
}
