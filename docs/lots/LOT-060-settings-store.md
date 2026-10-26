# LOT-060 — Settings catalogue & store

- **Module:** HFRStorage
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** none (lot tracked in `docs/LOTS.md`)

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79`. Audit: [E §3, §7, §8 (E-1)](../audit/E-storage-vendors.md).

| Legacy | What it gives the store |
|---|---|
| `HFRswift/Swift/AppSettingsView.swift:86-109` | key names and defaults of the `@AppStorage` preferences |
| `HFRswift/Swift/AppSettingsView.swift:155-170, 317-335` | `filter_posts_quotes` toggle (`wl_pseudo`/`pseudo`), size-key mirroring and the one-time `size_text_topics` migration |
| `HFRswift/Swift/Common.swift:51-65` | tolerant boolean parsing of `haptics` |
| `HFRswift/Swift/Common.swift:144-156` | `landscape_mode`: enabled unless the value is `none` |
| `HFRswift/Swift/Common.swift:262-318` | `auto_theme` clamp, deprecated theme keys, `theme` (1 = dark, anything else light) |
| `HFRswift/Swift/Common.swift:545-590` | colour string `{r, g, b, a}` |
| `Classes/HFRplusAppDelegate.m:84-116` | values forced at launch (`landscape_mode`, `filter_posts_*`, `display_images`, `shake_to_refresh`, noel) |
| `Classes/ObjCFavoritesLoaderWorker.m:45-46` | `vos_sujets == 1` selects `owntopic=3` |
| `HFRswift/Wrapped/ParseMessagesOperation.m:187,320,327,341-343` | `filter_posts_quotes` substring rules, `filter_posts_min_quotes <= 0` means 3 |
| `HFRswift/Wrapped/LinkItem.m:153,234`, `MessagesTableViewController.m:2923` | `embedded_videos == both`, `display_sig == yes`, `size_smileys == double` |
| `HFRswift/Swift/ReplyService.swift:1735-1809` | `rehost_use_link`, `rehost_resize_before_upload` |
| `Classes/MPStorage.m:969-978` | `mpstorage_last_rw` format and its volatile-write bug |

## Behaviour
Code in `Sources/HFRStorage/Settings/`, tests in `Tests/HFRStorageTests/Settings/`.

- **`Setting<Value>`**: legacy key name, default, and a tolerant codec. Reading never fails: a missing, mistyped or out-of-range value gives the default, or the legacy normalisation of that value.
- **`SettingKey`**: the 32 preferences of E §3.1 (state and counters of §3.2 belong to their own stores). SwiftUI `@AppStorage` can reuse `key` and `defaultValue`. `allKeys` is used by tests.
- **`SettingsStore`** (protocol, synchronous): `rawValue`, `setRawValue`, `removeValue` over `SettingRawValue` (`bool`, `int`, `double`, `string`); typed `value(for:)`, `set(_:for:)`, `reset(_:)` in an extension. Implementations: `UserDefaultsSettingsStore` (standard suite = what the legacy app wrote) and `InMemorySettingsStore`.
- **Coercions** follow `UserDefaults`: `integerForKey:` accepts booleans, doubles (truncated) and numeric strings; `stringForKey:` accepts numbers; booleans additionally accept `1/0/true/false/yes/no/on/off` as `haptics` does.
- **`LegacySettingsNormalizer.run(on:)`** (called by the app at launch): clamps an unknown `auto_theme` to `3`, removes `force_manual_theme`, `auto_theme_day_time`, `auto_theme_night_time`, migrates `size_text_topics` to the nearest `text_size_scale` once (only while the new key is absent) and then removes the legacy key, so a later reset is not undone.
- **Settings enums** come from HFRModels (`AutoThemeMode`, `ThemeVariant`, `ThemeStyle`, `TextSizeScale`, `LandscapeMode`, `ImageDisplayMode`, `EmbeddedVideosMode`, `RehostMaxDimension`). Four small types exist only for settings and live here: `FavoritesSource` (`vos_sujets`), `QuoteFilterExceptions` (`filter_posts_quotes`), `RehostLinkMode` (`rehost_use_link`), `ThemeColor` (the `{r, g, b, a}` codec).

Decisions:

1. **Synchronous store.** Views (`@AppStorage`), the HTML renderer and parsers read settings inline; an actor-isolated async API would force every call site to become async for a thread-safe dictionary. `UserDefaults` is thread-safe and the in-memory store uses `Mutex`. Mutable stores holding documents (blocklist, drafts, caches) are actors.
2. **Legacy raw shapes are kept on write**: `vos_sujets` is written as the string `"0"`/`"1"` (the legacy seed and `@AppStorage<String>` type), `display_sig` as `yes`/`no`, `size_smileys` as `double`/`default`, `recherche_categorie` as a string.
3. **No `register(defaults:)`** and no value written by a read: defaults live in `Setting`, so nothing volatile hides in the process (E §7.1). `mpstorage_last_rw` is persisted for real, as a `dd-MM-yyyy HH:mm:ss` local-time string (`Date.VerbatimFormatStyle`); the legacy `-` reads as "never".
4. **Naming**: Swift names say "blocklist" (`hideBlocklistedPosts`), the key stays `blacklist_hide_pseudo`.
5. **Not ported on purpose**: the mirroring of `size_text`, `size_text_topics`, `size_text_reply` on every change (legacy compatibility only); the forced `shake_to_refresh = NO`, `theme_noel_disabled = YES`; the `version` registration; the seed-only keys with no reader (`default_tab`, `adv_ssl`, `mpstorage_reset`, `EmptyCacheButton`, `theme_*_adjust`, `theme_*_tintcolor`, `offline_max_pages`).

## Edge cases
- `UserDefaults` booleans and integers are both `NSNumber`: the store tells them apart with `objCType` (`c`/`B` boolean), then every reader is tolerant anyway.
- `Int` conversion of non-finite or huge doubles returns nil (no trap), so the default applies.
- `landscape_mode`: any string except `none` allows rotation (legacy `rawValue != "none"`); a non-string value reads as the default.
- `theme`: any value other than `1` is light; `auto_theme`: any value other than `0` or `3` is the system mode, both in reading and (for `auto_theme`) in the store through the normaliser.
- `filter_posts_quotes`: `wl` and `pseudo` are matched as substrings, case-sensitively, as legacy; an unknown string means "no exception". Writing `[]` stores `""`.
- Colours: exactly four finite numbers between braces, separator `,` with optional spaces; written with three decimals and a `.` whatever the locale.
- `filter_posts_min_quotes <= 0` reads as 3.

## Fixtures
None: synthetic raw values in table-driven tests. A real `Library/Preferences/<id>.plist` dump is a Mac-side fixture for LOT-067 (legacy import).

## Intentional differences from legacy
- `auto_theme` missing: legacy `integerForKey:` gave `0` (manual, light) while the settings screen displayed `3`; the new default is `3` (follow the system), as the audit's table states.
- `display_images` is no longer forced to `yes` at every launch; it defaults to `yes` and is stored when set (there is no UI for it yet).
- `filter_posts_quotes` and `filter_posts_min_quotes` are defaults, not values written at launch.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
- `NSNumber` cannot tell a boolean from an integer through `as? Bool`; use `objCType` and keep every reader tolerant.
