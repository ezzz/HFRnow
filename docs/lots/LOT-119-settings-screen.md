# LOT-119 — Settings screen and general settings

- **Module:** App (`App/SwiftHFR/Settings/`); three keys added to HFRStorage and one enum to HFRModels
- **Difficulty / model:** medium (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#210](https://github.com/ezzz/HFRnow/issues/210)
- **Depends on:** LOT-060 (settings store), LOT-066 (caches, used by LOT-120), LOT-080 (target); conventions of LOT-081/082/083

## Legacy sources
Read-only, `origin/master` of ezzz/HFRnow (line numbers are those of `master`; LOT-060 cites the older `2440d79`).

| Legacy | Used for |
|---|---|
| `HFRswift/Swift/AppSettingsView.swift:86-114` | every `@AppStorage` key and default of the screen |
| `HFRswift/Swift/AppSettingsView.swift:134-138, 376-418` | "Général": rows, options and labels |
| `HFRswift/Swift/Common.swift:32-53` | `AppStartupScreen`: key `HFRswiftStartupScreen`, values `tab:categories`, `tab:favorites` (default), `tab:messages`; an empty or unknown value is favourites |
| `HFRswift/Swift/Common.swift:167-225` | `AppScreenRotation` (`landscape_mode`, `galerie_message` / `none`) and `HFRSwiftOrientationPolicy`: iPad always `.all`, iPhone `.allButUpsideDown`, or `.portrait` when locked or while the composer is open |
| `HFRswift/Swift/Common.swift:227-241` | keys `compact_mode`, `tabbar_minimize_on_scroll`, `topic_page_swipe_navigation`, `open_links_in_default_browser` |
| `HFRswift/Swift/Common.swift:265-294` | `AppTextSizeScale` (100 / 110 / 120 / 130, labels Standard, +10%, +20%, +30%) |
| `Classes/HFRplusAppDelegate.m:764-777` | `open_links_in_default_browser`: system browser, otherwise `SFSafariViewController` |
| `HFRswift/Swift/MainWindow.swift:1357-1363` | the start tab is read once at launch |
| `HFRswift/Swift/PlusTab.swift` | the legacy "Plus" tab that hosted the settings entry |

## Behaviour
Réglages is an entry of the LOT-170 root navigation: the first row of the Plus tab on the iPhone and the "Réglages" row of the iPad sidebar, both showing `SettingsView` in a `NavigationStack`.

- **`SettingsView`** (shell): a `Form` whose sections are owned by lots (table below). This lot builds "Général" and the entry row "Icône" (a row of "Général", as the legacy picker) and a "Thème" section holding the "Thème" entry row, which lead to a "Ce réglage arrive dans une prochaine version." page (`SettingsDestination`): LOT-121 and LOT-123 replace those pages, no theme and no icon code lives here.
- **`GeneralSettingsModel`** (`@Observable @MainActor`, tests in `App/SwiftHFRTests/Settings/`): reads each value from a `SettingsStore` at creation and writes it back, under its legacy key and raw shape, on every change. Creating it writes nothing.
- **"Général" rows:** "Écran de démarrage" (Tab Catégories / Tab Favoris / Tab Messages, as legacy), "Mode compact" (`compact_mode`, compact rows), "Réduire la tab bar au scroll" (`tabbar_minimize_on_scroll`, applied by the LOT-170 root tab bar (#296)), "Taille du texte" (a slider, 70 % to 130 % in steps of 5, default 100 %; operator decision 2026-10-28), "Rotation d’écran", "Navigateur par défaut" (off = in-app browser), then "Icône" (entry row). Section order and labels are the legacy ones ("Général", then "Thème"); the operator asked to keep the legacy Réglages structure (2026-10-28).
- **Applied now:** rotation (`OrientationPolicy` through an app delegate adaptor, re-applied when the switch changes: iPhone only, an iPad always rotates) and the start screen (the tab selected at launch, which is the sidebar destination on a regular width: Catégories, Favoris or Messages). Compact mode applies to the settings form's spacing (legacy applied it to the form and the favourites list).
- **Text size** is stored in the new key `text_size_percent` (below 100 gives the denser display wanted; stored values are clamped to 70-130). It is an in-app offset on top of Dynamic Type, never a replacement. Absent, the legacy `text_size_scale` (100-130) is the starting value. Applying it across the screens is LOT-169 (#295) (follow-up note in `GeneralSettingsModel`); LOT-106 must read `SettingKey.textSizePercent(from:)`.
- **Stored for their owner lot:** compact mode on lists (LOT-124/125), default browser (LOT-137 link handling reads `SettingKey.opensLinksInDefaultBrowser`).
- **`LegacySettingsNormalizer.run`** is now called once at launch (LOT-060 expected the app to; nothing did): the text size shown after an update from legacy is the migrated one.
- **Storage additions:** `SettingKey.startupScreen` (`HFRswiftStartupScreen`, enum `StartupScreen` in HFRModels, unknown value reads as favourites), `SettingKey.opensLinksInDefaultBrowser` and `SettingKey.textSizePercent`. LOT-060's catalogue left them out because they are not in `registerDefaults` nor in LOT-060's list of 32.

### Every legacy setting of `AppSettingsView.swift`, with its owner

| Legacy section / setting (key) | Owner | Here | Keep / merge / drop, why |
|---|---|---|---|
| Général: Écran de démarrage (`HFRswiftStartupScreen`) | LOT-119 (LOT-144 adds the Home value) | built | Keep: the launch tab is a real preference; the Home value is added by LOT-144. |
| Général: Favoris `vos_sujets`, Favoris triés par catégories `sujets_avec_cat`, Actualisation automatique `favorites_auto_refresh` | LOT-124 | not built | Keep: favourites behaviour the users rely on; LOT-124 rebuilds the rows. |
| Général: Mode compact (`compact_mode`) | LOT-119 | built | Keep: operator decision A, applied app-wide by LOT-169 (#295); stored here. |
| Général: Réduire la tab bar au scroll (`tabbar_minimize_on_scroll`) | LOT-119 stores, LOT-170 (#296) applies | built | Keep: operator decision; LOT-119 stores it, the LOT-170 root tab bar reads it. |
| Général: Taille du texte (`text_size_scale`, now slider `text_size_percent`) | LOT-119 entry, LOT-169 (#295) applies it | built | Merge: the 4-step picker and the old `text_size_scale` become one 70-130 % slider (CHANGELOG-LEGACY #24); `text_size_scale` is only the migration source. |
| Général: Retours haptiques (`haptics`), Icône (`icon`) | LOT-123 | not built (Icône: entry row) | Keep: LOT-123 rebuilds both; the Icône picker keeps its place in "Général" (entry row here). |
| Général: Rotation d’écran (`landscape_mode`) | LOT-119 | built | Keep: needed on iPhone; applied now (`OrientationPolicy`). |
| Général: Navigateur par défaut (`open_links_in_default_browser`) | LOT-119 stores, LOT-137 applies | built | Keep: users choose between system and in-app browser; LOT-137 applies it. |
| Thème: Changement de thème (`auto_theme`), Luminosité du thème (`theme`), Teinte d'accent (`theme_day_color_action`, `theme_night_color_action`), Luminosité du thème sombre (`theme_night_brightness`) | LOT-121 | not built (entry row) | Keep: the four rows live in the "Thème" section (entry row here), LOT-121 builds them. |
| Sujets: Style des messages (`theme_style`) | LOT-121 | not built | Keep: LOT-121 rebuilds the message style choice. |
| Sujets: Masquer les pseudos blacklistés (`blacklist_hide_pseudo`), Liste noire, Liste blanche | LOT-118 | not built | Keep: blacklist features stay; LOT-118 owns the lists and the toggle. |
| Sujets: Swipe changement de page (`topic_page_swipe_navigation`), Afficher les signatures (`display_sig`), Taille des smileys (`size_smileys`, commented out in legacy) | LOT-106 | not built | Keep: LOT-106 owns the reader; the smiley size is dropped (commented out in legacy, no effect). |
| Sujets: Bouton + (`reply_button_behavior`) | LOT-084 | not built | Keep: LOT-084 owns the reply button. |
| Filtrer les posts: Minimum de citations (`filter_posts_min_quotes`), Inclure les pseudos whitelistés (`filter_posts_quotes`) | LOT-114 | not built | Keep: LOT-114 owns the post filter. |
| Notifications MP: Badge messages non lus (`mp_badge_enabled`) | LOT-140 | not built | Keep: LOT-140 owns the unread badge. |
| Stockage MP: Activer (`mpstorage_active`), Dernier accès (`mpstorage_last_rw`), Resynchroniser | LOT-130 | not built | Keep: LOT-130 owns MP storage; the sync-location ADR may move where it lives, not the setting. |
| Maintenance: Caches de l’app, Pages HTML, Ouvrir les réglages système | LOT-120 (reads LOT-066) | not built | Keep: cache sizes and the system-settings shortcut; LOT-120 reads LOT-066. |
| À propos: Version | LOT-120 | not built | Keep: version display, LOT-120. |

### Keys missing from LOT-060 (storage audit, legacy `master` @21173e7)

| Key | Legacy | Status |
|---|---|---|
| `HFRswiftStartupScreen` | `Common.swift:32-37`, read `MainWindow.swift:1357-1360` | ported here; legacy values (`tab:categories`, `tab:favorites`, `tab:messages`) are read as is, so there is nothing to migrate; unknown or empty = favourites |
| `open_links_in_default_browser` | `Common.swift:239-241`, `AppSettingsView.swift:95, 402-409`, `HFRplusAppDelegate.m:771` | ported here (key and row); read as is; LOT-137 applies it |
| `topic_page_swipe_navigation` (default true) | `Common.swift:235-237`, `AppSettingsView.swift:94, 479` | follow-up for LOT-106 (reader swipe pages): add the key to `SettingKey` there |
| `reply_button_behavior` (`quick` default, `forum`, `hidden`) | `Common.swift:243-263`, `AppSettingsView.swift:106, 481-485` | follow-up for LOT-084 (reply composer): add the key and enum there |

Where settings live (MPStorage, iCloud or device) is decided by a pending ADR: until then every key here is in the device store (`HFRStorage`, `UserDefaults`), nothing is synced.

Settings with no UI in legacy's screen but in `SettingKey` (`embedded_videos`, `display_images`, `rehost_*`, `recherche_categorie`) belong to LOT-107/108, LOT-102 and LOT-115.

## Edge cases
- A stored start screen that is not one of the three legacy values reads as favourites (legacy `rootTab(for:)`), as does an empty string.
- A rotation value other than `none` (any string) allows rotation; a non-string value reads as the default (LOT-060).
- `didSet` runs on a real change only, so setting a switch to the value it has writes nothing and does not re-apply the orientation.
- The private-messages start screen has no screen to open before LOT-126: it opens the forum list, not a guessed destination.

## Fixtures
None: no HFR page is read. Tests drive the models over `InMemorySettingsStore` with legacy raw values: `GeneralSettingsModelTests`, `OrientationPolicyTests`, `StartupScreenTests` (App), `GeneralSettingsKeyTests` (HFRStorage). No HFR fact is added, so `HFR-PROTOCOL.md` is unchanged. **Pending capture:** none. A real legacy `Library/Preferences/<id>.plist` (LOT-067) would confirm `HFRswiftStartupScreen` values written by the shipped app.

## Intentional differences from legacy
- **Tab bar:** LOT-170 ([#296](https://github.com/ezzz/HFRnow/issues/296)) restored the legacy bar Catégories / Favoris / Messages / Plus (operator decision 2026-10-28) and applies the legacy tab-bar row (`tabbar_minimize_on_scroll`). The Phase 4 backlog item "tab-bar settings UI" is covered by that row.
- **Start screen** keeps the legacy tab names and values: "Tab Catégories", "Tab Favoris" and "Tab Messages" select the matching root tab (the Messages tab shows a placeholder until LOT-126).
- **Settings reach the app through the root navigation** (LOT-170, #296): the Réglages row of the Plus tab and of the iPad sidebar, as legacy, not a sheet.
- **Text size** is a 70-130 % slider instead of the 100 / 110 / 120 / 130 picker (CHANGELOG-LEGACY #24).
- Settings no longer re-apply theme or re-sync three size keys on every screen appearance (LOT-060 decision 5).

## Learnings
- A `@MainActor` default argument (`UIDevice.current`) on a static function makes the whole function main-actor isolated: split the pure part from the one that reads the device.
