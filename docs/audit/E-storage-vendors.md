# Audit E — Persistence, settings, vendors and third-party code

Legacy reference: `/home/user/HFRnow` @ `2440d79` (read-only). Auditor: LOT-000 / area E. Language of the legacy code is quoted as-is (French strings are not translated unless needed).

Conventions: `file:line` paths are relative to the legacy repo root. `pbxproj` = `SuperHFRplus.xcodeproj/project.pbxproj`. "unverified" = could not be confirmed by reading code/config (no Mac, nothing was built or run).
No secret value is reproduced in this document (see [Security notes](#5-security-notes)).

---

## 1. Scope

### 1.1 What "compiled into HFRswift" means here

`HFRswift` (`pbxproj:15B0AA842E2C27DD0092C0FD`, `pbxproj:4280-4301`) is the SwiftUI target. Its membership is:

| Build phase | Content | Evidence |
|---|---|---|
| Sources (explicit) | 45 `.m` files from `Classes/`, `SuperHFRplus/Helpers/`, `SuperHFRplus/Vendor/`, `HFRswift/Wrapped/` | `pbxproj:5710-5763` |
| Sources (synchronized folder) | every `.swift` / `.m` under `HFRswift/Swift/` (incl. the `SDWebImage.h/.m` shim) | `pbxproj:2671`, `pbxproj:4291-4293` |
| Frameworks | `libiconv.tbd`, `libicucore.tbd`, `GiphyUISDK.xcframework`, `SimpleKeychain.xcframework`, system frameworks (SafariServices, WebKit, CoreData, CoreText, ImageIO, MessageUI, MobileCoreServices, SystemConfiguration, CFNetwork, UIKit, Foundation, CoreGraphics, QuartzCore, AssetsLibrary, WidgetKit) | `pbxproj:2682-2707` |
| Embed Frameworks | `GiphyUISDK.xcframework`, `SimpleKeychain.xcframework` | `pbxproj:1583-1593` |
| Resources | assets, HTML/CSS/JS templates, `commonsmile.plist`; **not** `InAppSettings.bundle` (only referenced in the legacy Resources phase, `pbxproj:5296`) | `pbxproj:4377-…`, `pbxproj:1265` |
| Not present | `SDWebImage.framework`, `InAppSettingsKit.xcframework` (legacy only: `pbxproj:728`, `pbxproj:884`, `pbxproj:901`, `pbxproj:887`) | — |
| Swift Package deps | **none** in the whole project (no `XCRemoteSwiftPackageReference` / `XCSwiftPackageProductDependency` in `pbxproj`, no `Podfile`, no `Package.swift` at the root) | grep on `pbxproj` |

Identities (used in the migration analysis):

| Target | Bundle id | Marketing version | Team | Entitlements | Evidence |
|---|---|---|---|---|---|
| HFRswift | `hfrplus.red.super` | 4.0 | `QMG83DG7YP` (device SDK only) | associated-domains `webcredentials:forum.hardware.fr`; **no** keychain-access-groups, **no** application-groups, **no** iCloud | `pbxproj:6100,6097,6060`; `HFRswift/HFRswift.entitlements:5-8` |
| SuperHFRplus (legacy) | `hfrplus-legacy.red.super` (product `SuperHFRplusSwift.app`) | 3.2 | `QMG83DG7YP` | same domain + empty `keychain-access-groups` | `pbxproj:6351,6346,6352`; `SuperHFRplus.entitlements:5-9` |

Which of the two bundle ids was the one shipped on the App Store is **unverified** (see [Open questions](#9-open-questions)).

### 1.2 Files audited

Starting list: `Classes/MPStorage.m`, `OfflineStorage.m`, `BlackList.m`, `SmileyCache.m`, `k.m`, `ThemeManager.m`, `MultisManager.m`, `HFRswift/Swift/AccountsStore.swift`, `AppSettingsView.swift`, plus every reference followed from them.

- `Classes/Constants.m` **does not exist**; only `Classes/Constants.h` (file-name and Multis-key `#define`s, `Classes/Constants.h:87-96,115-124`).
- `k.m` holds no persistence: it only returns the forum base URL (`Classes/k.m:37-40`). `ThemeManager.m` has no keys of its own beyond `theme_noel_disabled` (`Classes/ThemeManager.m:213`); theme keys are read/written through the Swift `AppThemeResolver` / `ThemeUserColorStore` (`HFRswift/Swift/Common.swift:264-330,395-540`).
- `AccountsStore.swift` stores nothing itself: it is an `ObservableObject` facade over `AccountSessionService` -> `ObjCLegacyAccountsManager` -> `MultisManager` -> Keychain (`HFRswift/Swift/AccountsStore.swift:29-82`, `HFRswift/Swift/Common.swift:1077-1180`).
- Legacy-only (not compiled into HFRswift) and therefore out of scope except where noted: `RehostImage*`, `SmileyViewController` (writes `smileysSearch.plist`), `ForumsTableViewController` (writes `forumsCache.plist`, `forumsMeta.plist`), `BlackListTableViewController`, `Extensions/` (Today widgets; no target builds them, `pbxproj:1595-1603` has an empty "Embed App Extensions" phase), `HFRswift/Wrapped/MessagesTableViewController.m` (present in the `HFRswift/Wrapped` group but **not** in the HFRswift Sources phase; only in the legacy one, `pbxproj:5808`).

---

## 2. Storage inventory

Legend for "Used by HFRswift": **yes** = reachable code compiled in the HFRswift target; **compiled, effectively unused** = code is compiled but no HFRswift UI path reaches it; **legacy-only** = only the old target.

No App Group, no iCloud / `NSUbiquitousKeyValueStore`, no CloudKit, no `UIDocument`, no `UserDefaults(suiteName:)` in app code (grep over the whole repo; the only `suiteName` is in a unit test, `HFRswiftTests/MPListViewModelTests.swift:90`). Everything lives in the app's own sandbox container.

### 2.1 Keychain

| Key / path | Type, format | Owner | Holds | Sensitive | Used by HFRswift |
|---|---|---|---|---|---|
| service = `Bundle.main.bundleIdentifier` (`Carthage/Checkouts/SimpleKeychain/SimpleKeychain/A0SimpleKeychain.m:32`), account/key = `HFR_COMPTES_KEY` (`Classes/Constants.h:115`), no access group (`A0SimpleKeychain.m:33`), accessibility `AfterFirstUnlock` (`A0SimpleKeychain.m:45`), not "ThisDeviceOnly", not synchronizable (unverified: `kSecAttrSynchronizable` not set in the sources read) | generic-password item whose data = `NSKeyedArchiver.archivedDataWithRootObject` (insecure-coding) of an `NSArray<NSMutableDictionary>` (`Classes/MultisManager.m:81,100,133,224,239,275`); read with the deprecated `unarchiveObjectWithData:` (`MultisManager.m:45,51`) | `Classes/MultisManager.m` (all writes rewrite the **whole** array) | one dict per account: `PSEUDO` (= value of cookie `md_user`, the account id), `PSEUDO_DISPLAY`, `COOKIES` (array of `NSHTTPCookie`, i.e. the session), `HASH` (the forum `hash_check` token needed to post), `AVATAR` (raw image `NSData`), `MAIN` (bool) (`Classes/Constants.h:116-121`, `MultisManager.m:49-86`) | **Yes**: session cookies + posting hash = account takeover. No password is stored (see 5.1) | yes |

### 2.2 `UserDefaults` (standard suite) — see section 3 for the per-key detail

Plist at `Library/Preferences/<bundle id>.plist`. Roughly 60 keys, all plaintext, all in the standard domain. Sensitive-ish ones: `dicMPStorage_postid` (pseudos of the user's accounts as dictionary keys), `composerDraftText` (unsent post/private-message text), `smileySearchHistory_v1`.

### 2.3 Files in `Documents/` (sandbox, **backed up**, not exposed: HFRswift `Info.plist` has no `UIFileSharingEnabled`/`LSSupportsOpeningDocumentsInPlace`, unverified by absence of grep hit in `HFRswift/Info.plist`)

| Path | Format | Owner (file:line) | Holds | Sensitive | HFRswift |
|---|---|---|---|---|---|
| `blackListDico.plist` | XML plist via `-[NSMutableDictionary writeToFile:atomically:]` (`Classes/BlackList.m:165-170`). Shape: `{ <pseudo of the account (display name)> : [ {word:String, alias:String="", mode:Int(0=kTerminator)} ] }` (`BlackList.m:43,96,103`; `Classes/Constants.h:32-35`) | `Classes/BlackList.m` (`save` :163, `load` :173) | per-account blacklist (pseudos of ignored users) | personal data (social graph); also leaks the account pseudos as dict keys | **yes** (via `ObjCProfileFilterListManager`, `HFRswift/Swift/Common.swift:890-1010`, and `ParseMessagesOperation.m:187`, `LinkItem.m`) |
| `whiteList.plist` | XML plist array of the same `{word, alias, mode}` dicts. **Global**, not per account (`BlackList.m:49-54,170,197-202`) | `BlackList.m` | "love list" / whitelist | personal data | yes |
| `blackList.plist` (v0, legacy of legacy) | plist array; read once and deleted (`BlackList.m:187-192`) | `BlackList.m:180` | pre-multi-account blacklist | personal | yes (migration path only; contains a bug, see 7) |
| `smiley_favorites_cache2` (no extension) | binary plist from `NSKeyedArchiver`: `NSMutableDictionary<String, SmileyFavorite>`; `SmileyFavorite` = `{sCode, sRawUrl, dateAdded}` (`Classes/SmileyCache.m:18,26-35,353-362,389-439`) | `SmileyCache.m` | the user's app-local favourite smileys (`arrFavoritesSmileysApp`) | no | yes (`ReplySmileyCacheBridge`, `HFRswift/Swift/ReplySmileyCatalog.swift:36-110`) |
| `forumsCache.plist` | `NSKeyedArchiver` of `[Forum]` (`Classes/ForumsTableViewController.m:116-119`, `Classes/Forum.m:130-151`) | written **only** by legacy `ForumsTableViewController`; **read** by HFRswift with `NSKeyedUnarchiver.unarchiveObject(with:)` (`HFRswift/Swift/ForumSearchView.swift:452-466`) | category list for the search screen | no | read-only in HFRswift: a fresh install never has it, so the picker falls back to `13 Discussions` (`ForumSearchView.swift:441-446`) |
| `forumsMeta.plist` | plist (`ForumsTableViewController.m:892,1195-1276`) | legacy-only | forum ordering/visibility metadata | no | legacy-only |
| `offlineTopicsDico.plist`, `offlineImageCacheDico.plist` | `NSKeyedArchiver` data (`Classes/OfflineStorage.m:88-143`) | `OfflineStorage.m` (loaded in `init`, :28-37, triggered by `OfflineStorage.shared()` at `HFRswift/Swift/Common.swift:1964`) | dictionaries of topics saved for offline reading (`Topic` is `NSCoding`, `Classes/Topic.m:101-154`) | no | compiled, effectively unused (no HFRswift UI creates offline topics; only `cacheURL()` / `createHtmlFileInCacheForTopic:` are used) |
| `cache/<topicID>/…` and `cache/<IMAGE_CACHE_DIRECTORY>/…` | topic HTML pages + images (`OfflineStorage.m:146-330`) | legacy offline feature | offline copies | no | legacy-only in practice |
| `rehostImages.plist` | plist (`Classes/RehostImageViewController.m:43,163,295`) | legacy | upload history of the image rehosting feature | personal (image URLs) | legacy-only. HFRswift **does not read it**; it uses a new file (next row) |
| `rehostImagesSwiftUI.json` | `JSONEncoder` of `[RehostUploadedImage]`, atomic write (`HFRswift/Swift/ReplyService.swift:1894-1921`) | `RehostUploadHistoryStore` | upload history | personal | yes |
| `smileysSearch.plist`, `lastSmileysSearch.plist` | plist (`Classes/SmileyViewController.m:109,966`) | legacy; `LAST_SMILEYS_FILE` is `#define`d but never used (grep) | smiley search history | no | legacy-only (HFRswift uses `smileySearchHistory_v1` in defaults instead) |

### 2.4 Files in `Library/Caches/` (system may purge; **not** backed up)

| Path | Format | Owner | Holds | HFRswift |
|---|---|---|---|---|
| `cache/avatars/` | image files; pruned at 25 days (`Classes/HFRplusAppDelegate.m:539-560`; created/read at `HFRswift/Wrapped/ParseMessagesOperation.m:124-140`, `HFRswift/Swift/MPListView.swift:555-560`) | ParseMessagesOperation / MPListView | avatar cache | yes |
| `cache/topic-<UUID>.htm` | HTML written then displayed by `WKWebView` (`HFRswift/Swift/Common.swift:1962-1976`); `OfflineStorage.diskCachePath` = `Caches/cache` (`OfflineStorage.m:521-531`) | `OfflineStorageTopicPageRenderer` | rendered topic page | yes. **No cleanup of these files found** (unverified: `periodicMaintenance` might run, `BACKGROUND_MAINTENANCE` macro value not checked) |
| `cache/` copies of bundle CSS/JS | `OfflineStorage copyAllRequiredResourcesFromBundleToCache` (`OfflineStorage.m:439-497`, invoked at `HFRplusAppDelegate.m:81`) | OfflineStorage | CSS/JS so the HTML file can reference them | yes |
| `ImageCache/`, `SmileCache/` | — | only *deleted* by "Clear caches" (`HFRswift/Swift/AppSettingsView.swift:264-278`); no code in the HFRswift target writes them (grep) — stale from the SDWebImage era (unverified) | nothing | dead |
| `tmp/hfrswift-preview/…` | SwiftUI-preview-only helper (`HFRswift/Swift/MessagesView.swift:6432-6439`) | previews | — | previews only |

### 2.5 System-managed persistence the new app must account for

| Store | Where | Note |
|---|---|---|
| `HTTPCookieStorage.shared` | `Library/Cookies/<bundle id>.binarycookies` (system) | Holds the *active* session. `MultisManager.setCookiesForMain` wipes it and re-injects the main account's cookies (`Classes/MultisManager.m:107-123`), `forceCookies` does the same (`:200-212`). `LoginService` writes response cookies into it (`HFRswift/Swift/LoginService.swift:81-84`) and then harvests those whose domain contains `hardware.fr` (`:115-127`). `AccountSessionService.makeReplySessionContext` re-injects them and preserves the `quotes*` cookies (`HFRswift/Swift/AccountSessionService.swift:77-115`). |
| Task identifier | `BGTaskScheduler` `com.hfrplus.refresh_mp` (`HFRswift/Info.plist`, `HFRswift/Swift/MPBackgroundService.swift:15`) | Not data, but the identifier must be re-declared in the new app. |
| Notification authorization | system | Re-requested at launch (`HFRswiftApp.swift:30`). |

### 2.6 Remote persistence ("MPStorage"): data that lives on the forum server

`MPStorage` (`Classes/MPStorage.m`) uses a **private message** as a JSON database. This is the only cross-device persistence of the app.

- Locating it: scan the user's PM list (`forum1.php?config=hfr.inc&cat=prive&page=N…`, `MPStorage.m:692-736`) for a topic titled `a2bcc09b796b8c6fab77058ff8446c34` (or `[non lu] …`) (`MPStorage.m:23,713`). Created by POSTing to `bddpost.php` with `dest=MultiMP` (`:24,738-767,780-833`). Updated by POSTing to `bdd.php` (`:781-783`).
- Payload (`MPStorage.m:740`; entry shapes at `:259,344,1360-1366` and `Common.swift:1360-1366`):
  ```
  {"data":[{"version":"0.1",
            "blacklist":{"list":[{"createDate":ms,"username":s}],"sourceName":"iOS","lastUpdate":ms},
            "mpFlags":  {"list":[{"post":n,"p":s,"href":s,"page":n,"uri":s}],…},
            "bookmarks":{"list":[{"createDate":ms,"post":s,"author":s,"numreponse":n,"cat":s,"label":s}],…},
            "sourceName":"iOS","lastUpdate":ms}],
   "sourceName":"iOS","lastUpdate":ms}
  ```
- It is read back by scraping the PM HTML: `messagetable` -> second `td` -> `<p>` text, `U+00A0` removed, `NSJSONSerialization` (`MPStorage.m:871-886`), and the PM *reply number* is parsed from the `para…` div id (`:876-878`) for later edits.
- Local cache of the PM's post id, per pseudo and per alias (lowercased, trimmed, ZWSP-stripped): `dicMPStorage_postid` in defaults (`MPStorage.m:625-688`).
- Gated by the boolean `mpstorage_active` (off by default, `InAppSettings.bundle/Root.inApp.plist`; auto-disabled on any parse error `MPStorage.m:855,863,890`). When off, **bookmarks and blacklist sync do not exist**.
- Semantics that matter for a port: whole-document read-modify-write with no version check (`lastUpdate` is written but never compared); the "Asynchronous" save does a **synchronous** POST (`MPStorage.m:932-940`); on a successful remote load the local blacklist of the active account is **replaced** (`MPStorage.m:208-215`); the success test is `containsString:@"succès"` on the response (`:911,964`); save is the only conflict "strategy" (last writer wins).

Other server-side state (not stored by the app, but re-fetched): favorites / flags (`forum1f.php?owntopic=1|3`, `Classes/ObjCFavoritesLoaderWorker.m:44-49`), MP list, profile.

---

## 3. Settings inventory

All are in `UserDefaults.standard`. "Seed" = default registered from `InAppSettings.bundle/Root.inApp.plist` in the **legacy** target only. HFRswift does not ship that bundle, so `registerDefaultsFromSettingsBundle` returns early (`Classes/HFRplusAppDelegate.m:395-402`; it also references an `ActionsMessages.plist` that does not exist in the bundle, `:411-419`). In HFRswift the effective default is the `@AppStorage` default or the ObjC `nil` behaviour.

### 3.1 User preferences (shown in `AppSettingsView`)

| Key | Type (as stored) | Default (HFRswift / seed) | Where (file:line) | Meaning |
|---|---|---|---|---|
| `vos_sujets` | String `"0"`/`"1"` (IASK seed is a string; ObjC reads `integerForKey`, which coerces) | `"0"` / `'0'` | `AppSettingsView.swift:86`, `Favorites.swift:402`, `Classes/ObjCFavoritesLoaderWorker.m:46` | Favorites tab: flags+favorites (`owntopic=1`) vs favorites only (`3`) |
| `sujets_avec_cat` | Bool | true / true | `AppSettingsView.swift:87`, `Favorites.swift:403` | favorites grouped by category |
| `favorites_auto_refresh` | Bool | false / — (new) | `AppSettingsView.swift:88`, `Favorites.swift:404` | |
| `compact_mode` | Bool | false | `Common.swift:205`, `AppSettingsView.swift:89` | |
| `tabbar_minimize_on_scroll` | Bool | true / true | `Common.swift:209`, `AppSettingsView.swift:90` | |
| `text_size_scale` | Int 100/110/120/130 | 100 / — (new) | `Common.swift:213-240`, `AppSettingsView.swift:91` | Replaces the three legacy size keys below; migrated from `size_text_topics` once (`AppSettingsView.swift:325-335`) |
| `size_text_topics`, `size_text`, `size_text_reply` | Int / String / Int | 110 / `default` / 15 (seed) | mirrored on every change (`AppSettingsView.swift:317-323`) | legacy compatibility only |
| `haptics` | Bool (parser tolerates NSNumber/String, `Common.swift:51-65`) | true / true | `AppSettingsView.swift:92` | |
| `landscape_mode` | String `galerie_message` / `none` | `galerie_message` | `Common.swift:144-156`, `HFRplusAppDelegate.m:95-98`, `AppSettingsView.swift:93` | rotation allowed |
| `icon` | String (`superblue`, `classic`, `classic-red`, `redface`, `redface-blue`, `beta`, `blue`, `white`) | `superblue` | `AppSettingsView.swift:31-84,94,213-222` | alternate icon name map to `Icon-*` (`Info.plist` `CFBundleAlternateIcons`) |
| `auto_theme` | Int: 3 = follow iOS, 0 = manual (any other value is normalised to 3) | 3 / 3 | `Common.swift:264-318`, `AppSettingsView.swift:96` | |
| `theme` | Int 0 light / 1 dark | 0 / 0 | `Common.swift:269,305-307` | manual theme |
| `theme_style` | Int 0 classic / 1 modern | 1 / 1 | `AppSettingsView.swift:98`, `MessagesView.swift:2655`, `Classes/ObjCTopicHTMLRenderer.m:83,87` | message rendering style |
| `theme_day_color_action`, `theme_night_color_action`, `…_love`, `…_superfavori` | String `"{r, g, b, a}"` (`Common.swift:545-590`) | computed defaults (`Common.swift:420-485`) | `Common.swift:395-540`, `AppSettingsView.swift:291-315` | user-tinted colours; the new UI writes day/night action tint from a single hue slider |
| `theme_night_brightness` | Double | computed | `Common.swift:518-540` | |
| `blacklist_hide_pseudo` | Bool | false / false | `AppSettingsView.swift:100`, `HFRswift/Wrapped/LinkItem.m:81,290` | hide blacklisted posts entirely |
| `filter_posts_quotes` | String; contains `wl` and/or `pseudo`/`ps…` (modes parsed with `containsString`) | `wl_pseudo` (forced if nil, `HFRplusAppDelegate.m:108-111`) | `AppSettingsView.swift:101,165-170`, `HFRswift/Wrapped/ParseMessagesOperation.m:187,320,327` | filter posts that merely quote a blacklisted user |
| `filter_posts_min_quotes` | Int | 3 (forced if nil, `HFRplusAppDelegate.m:112-114`) | `AppSettingsView.swift:102`, `ParseMessagesOperation.m:341` | |
| `size_smileys` | String `default`/`double` | `double` | `AppSettingsView.swift:103` — **no reader found in compiled code** (unverified: may be consumed by CSS, not by key) | smiley size |
| `embedded_videos` | String `no`/`yes`/`both` | `yes` | `AppSettingsView.swift:104`, `LinkItem.m:153`, `ParseMessagesOperation.m:238` | |
| `display_sig` | String `yes`/`no` | `no` | `AppSettingsView.swift:105`, `ObjCTopicHTMLRenderer.m:10`, `LinkItem.m:234` | |
| `display_images` | String (`yes`/`no`/`wifi`) | **forced `yes` at every launch** (`HFRplusAppDelegate.m:115-116`); no UI in HFRswift | `LinkItem.m:161-193` (wifi mode uses `Reachability`) | image display policy; effectively constant |
| `mpstorage_active` | Bool | false | `AppSettingsView.swift:107`, `BookmarksPlusView.swift:30`, `MPListView.swift:150,409`, `MessagesView.swift:2924`, `Classes/BlackList.m:39,57`, `ObjCMessageActionsBuilder.m:18` | MPStorage sync switch |
| `mpstorage_last_rw` | String date `dd-MM-yyyy HH:mm:ss` | `-` | `AppSettingsView.swift:108`, `BookmarksPlusView.swift:113`, written at `MPStorage.m:969-978` | **written with `registerDefaults:`, which is not persistent** (see 7) |
| `mp_badge_enabled` | Bool | true | `AppSettingsView.swift:109`, `MainWindow.swift:1129` | |
| `recherche_categorie` | String forum id | `"13"` | `ForumSearchView.swift:105,111`, `Classes/ObjCForumSearchWorker.m:28` | last search category |

### 3.2 State that is not a preference (but lives in defaults)

| Key | Type | Where | Meaning |
|---|---|---|---|
| `dicMPStorage_postid` | Dictionary<String(pseudo alias), String(post id)> | `MPStorage.m:84,670-688` | cache of the MPStorage PM id |
| `nb_mp`, `nb_mp_failure` | Int | `HFRswift/Swift/MPBackgroundService.swift:40,73-97`, `MPListView.swift:234`, `MainWindow.swift:1127`, `HFRplusAppDelegate.m:218-256,482,702` | unread-MP badge value, consecutive failures |
| `nb_aq`, `last_check_aq` | Int, Date | `AQPlusView.swift:30-42,313`, `MainWindow.swift:1128` | "AQ" feed counter and last check |
| `HFRswiftOpenMessagesFromNotificationPending` | Bool | `Common.swift:31-42`, `HFRplusAppDelegate.m:192` | one-shot flag set by the notification tap, consumed by SwiftUI |
| `SuperFavoritesIds` | [Int] | `Favorites.swift:114-136` | topic ids flagged "super favourite" (local only) |
| `CollapsedFavoriteSectionIDs`, `FavoritesShowCollapsedSections` | [String], Bool | `Favorites.swift:138-154,406` | UI |
| `arrayCategoriesVisibleOrder`, `arrayCategoriesHiddenOrder` | [String] | `Classes/ObjCFavoritesLoaderWorker.m:33-34,157-159` | category ordering in favorites |
| `HFRswiftGlobalTopicListFlag` | Int | `MainWindow.swift:268` | UI filter |
| `composerDraftText` | String | `MessagesView.swift:2668,3845,4547`, `AnswerView.swift:55,264,711`, `ComposerDraftPersistence` `AnswerView.swift:30` | **single global** draft of the reply composer (not per topic). New-topic draft is `@State` only (`MainWindow.swift:277`) so it is lost on kill |
| `smileySearchHistory_v1` | Data (JSON `[SmileySearchHistoryEntry]`, max 50) | `SmileySearchService.swift:85-125` | search history |
| `rehost_use_link`, `rehost_resize_before_upload` | Int | `ReplyService.swift:1790-1809` | image-upload preferences |
| `AnswerView.smileys.basic.expanded`, `…forumFavorites.expanded`, `…appFavorites.expanded`, `…search.allKeywords`, `MessageSmileySheetCompactImage` | Bool | `AnswerView.swift:1061-1064`, `MessagesView.swift:5120` | UI toggles |
| `offline_max_pages` | Int | `Classes/OfflineStorage.m:163` | legacy offline feature (no HFRswift UI) |

### 3.3 Legacy / forced / dead keys

| Key | Status |
|---|---|
| `force_manual_theme`, `auto_theme_day_time`, `auto_theme_night_time` | deprecated, removed on launch (`Common.swift:273-302,308`) |
| `theme_noel_disabled` (forced `YES`, `HFRplusAppDelegate.m:100`), `theme_noel_period`, `noel_first_time_2022` (`:640-652`) | seasonal theme, disabled; still read by `ThemeColors.m` (many sites) and `Common.swift:470,485` |
| `shake_to_refresh` | forced `NO` (`HFRplusAppDelegate.m:99`), no reader |
| `version` | `registerDefaults` only (`HFRplusAppDelegate.m:86-91`); never persisted |
| `default_tab`, `adv_ssl`, `mpstorage_reset`, `EmptyCacheButton`, `theme_day_adjust`, `theme_night_adjust`, `theme_*_tintcolor` | seed-only (legacy `InAppSettings.bundle`: `Root.inApp.plist`, `Advanced.plist`, `ThemeSettings.plist`); **no reader in HFRswift-compiled code** |

---

## 4. Data migration

### 4.1 Where the data is and who can read it

- There is no App Group, no keychain access group (HFRswift has none; legacy has an empty array), no iCloud. A second app can read the old data **only if it is the same app** (same bundle id signed by the same team, delivered as an update) or via an explicit export from the old app.
- HFRswift (`hfrplus.red.super`, version 4.0) and legacy (`hfrplus-legacy.red.super`, 3.2) already have *different* containers. Whether HFRswift users could carry data from the old app is therefore itself uncertain; HFRswift reads the **same key names and same file names** as legacy (e.g. `landscape_mode`, `blackListDico.plist`, Keychain `HFR_COMPTES_KEY`), which suggests it was shipped as the in-place successor of the previous App Store app (unverified).
- The new SwiftHFR app has no bundle id yet (`App/README.md`: app target not created; ADR pending). **The whole migration story depends on that decision** (section 9, Q1).

### 4.2 What users lose if nothing is migrated

| Data | Where | Lost if new app has a different container? | Recoverable otherwise? |
|---|---|---|---|
| Accounts (cookies, hash, avatar) | Keychain | **Yes** (service = bundle id, default access group = team.bundle id) | Re-login with pseudo+password (`LoginService`); passwords are not stored, so the user must remember them. Painful for multi-account users |
| Blacklist (per account) | `Documents/blackListDico.plist` | Yes locally | Restored from the server **only if `mpstorage_active` was on** (`MPStorage.m:202-226`); otherwise lost |
| Whitelist ("love list") | `Documents/whiteList.plist` (global) | Yes | **No** server copy |
| Bookmarks | server (MPStorage) | no (server-side) | only exist if MPStorage was active; re-synced after re-login + `initOrResetMP` |
| MP flags / read positions | server (MPStorage) | no | idem |
| Favourites / flags (topics) | server | no | refetched from the forum |
| Super-favourites | `SuperFavoritesIds` | Yes | **No** |
| Favourites order/collapsed sections | defaults | Yes | UI-only, cheap to lose |
| App favourite smileys | `Documents/smiley_favorites_cache2` | Yes | **No** (forum-side favourite smileys are refetched, `ReplyService.swift:251`) |
| Rehost upload history | `rehostImagesSwiftUI.json` | Yes | **No** (URLs may still be in old posts) |
| Smiley search history | defaults | Yes | cheap |
| Draft (`composerDraftText`) | defaults | Yes | transient |
| Settings (theme, text size, icon, filters, haptics…) | defaults | Yes | users reconfigure; ~25 meaningful keys |
| Offline topics / images | Documents | Yes | feature unused in HFRswift; ignore |
| Caches (avatars, topic HTML) | Caches | n/a | rebuilt |

### 4.3 Is migration from the old container possible?

| Scenario | Defaults | Documents files | Keychain | Verdict |
|---|---|---|---|---|
| A. New app ships under the **same bundle id and team** as the installed app (update) | readable (same plist) | readable | readable (same service/group) | **Full migration possible**, in-process, on first launch |
| B. New app with another bundle id, same team | not readable | not readable | not readable (access group `team.bundleid`; no shared group declared) | Needs the old app to be updated first with an *export* (share sheet JSON/zip) or with a shared keychain group/App Group — only feasible if the legacy line still ships updates |
| C. Different team / fresh listing | — | — | — | Same as B, plus no keychain sharing at all. Only manual re-setup + MPStorage re-sync |

Technical notes that apply to scenario A (and to a test fixture set):
- Keychain item decoding needs `NSKeyedUnarchiver` with (provisional list, to validate with the synthetic legacy archive of LOT-004) the ObjC classes `NSArray`, `NSMutableDictionary`, `NSHTTPCookie`, `NSData`, `NSNumber`, `NSString` allowed. `NSHTTPCookie` archives with `requiringSecureCoding: false` in the legacy writer; in the new code use `unarchivedObject(ofClasses:from:)` with exactly these classes.
- `smiley_favorites_cache2` and `forumsCache.plist` / `offlineTopicsDico.plist` are archived with **app-specific class names** (`SmileyFavorite`, `Forum`, `Topic`); decoding in Swift needs `NSKeyedUnarchiver.setClass(_:forClassName:)` to a shim `NSObject & NSCoding` class (keys: `sCode`,`sRawUrl`,`dateAdded` — `SmileyCache.m:26-35`; `Forum`: `aTitle`,`aURL`,`aID`,`subCats` — `Forum.m:130-138`).
- Plists are plain `PropertyListDecoder`/`PropertyListSerialization` territory (blacklist, whitelist).
- Defaults values use mixed types for the same logical key (e.g. `vos_sujets` string vs int) — import must coerce.

### 4.4 Recommendation

1. Decide the bundle id first (Q1). If A is possible, build a one-shot, idempotent, versioned **import step** (lot E-7) that reads the old artefacts without deleting them, writes into the new stores, and records `migration.legacyImport.version` in the new settings.
2. If only B/C are possible: ship a **legacy export** (not in this repo) and a new-app import; and in any case implement an **MPStorage-based restore** so that a re-login restores blacklist + bookmarks.
3. Never migrate: offline topics, `ImageCache`/`SmileCache`, forced/seasonal keys, `nb_*` counters, `version`.

---

## 5. Security notes

1. **No password is persisted.** The password lives in a `@State` of `AddAccountView` and in the `LoginService.login` argument (`HFRswift/Swift/AddAccountView.swift:15,90`, `LoginService.swift:48-65`). Good; keep it that way. (`webcredentials:forum.hardware.fr` associated domain enables iOS autofill, `HFRswift.entitlements:5-8`.)
2. **Session cookies and `hash_check` are in the Keychain, but serialised with `NSKeyedArchiver` insecure coding** and read with the deprecated `unarchiveObjectWithData:` (`MultisManager.m:45,51`). Keychain items are sandboxed so exploitation is unlikely, but the new code must use `NSSecureCoding`/`Codable` and a versioned envelope.
3. **Accessibility `AfterFirstUnlock` (not `ThisDeviceOnly`)** (`A0SimpleKeychain.m:45,231`): the session tokens are included in encrypted device backups and restored on a new device. Decide deliberately (see Q6).
4. **Session cookies are also in `HTTPCookieStorage.shared`** (Library/Cookies), outside the Keychain, and are re-created/wiped on every account switch (`MultisManager.m:107-123`). Acceptable (system data-protection class), but it is a second source of truth: `updateAllAccounts` refreshes the Keychain copy from `request.responseCookies` (`:242-293`).
5. **Plaintext in defaults / Documents (both included in backups):** account pseudos as dictionary keys (`dicMPStorage_postid`, `blackListDico.plist`), the unsent draft, the blacklist/whitelist, rehost history. Low sensitivity individually; together they are a social profile.
6. **Hard-coded third-party credentials in the HFRswift target** (values deliberately not copied here; `AGENTS.md §3.4` forbids secrets in the new repo):
   - Giphy SDK API key literal: `HFRswift/Swift/HFRswiftApp.swift:20` (legacy: `API_KEY_GIPHY` used at `Classes/AddMessageViewController.m:154`; where it is defined: unverified).
   - Image-host (img3, Chevereto) upload key literal, embedded in the upload URL: `HFRswift/Swift/ReplyService.swift:1962-1970` ("Keep in sync with legacy `API_KEY_CHEVERETO_IMG3`").
   - `Classes/Constants.h:124` has a placeholder `CHEVERETO_KEY` (unused).
   Both literals are in a public repository history. Build-time injection (ADR 0007) keeps them out of the repository but **not** out of the shipped app, where they remain extractable: rotation by each key's owner and provider-side restrictions are still required, or the features are dropped (Q7).
7. **MPStorage stores bookmarks, blacklist and read positions as clear JSON in the user's own private-message box**, under a constant, discoverable subject and recipient `MultiMP` (`MPStorage.m:23-24`). Anyone with account access sees it; it also adds a PM to the user's mailbox. Not encrypted, no integrity check. A failed or concurrent write can corrupt it (see 7); the code auto-disables the feature on parse error.
8. `UserDefaults.synchronize()` and `registerDefaults:` used as a write are deprecated/incorrect (`MPStorage.m:975-977`, `Common.swift:763`).
9. The `Carthage/Checkouts/*.xcarchive` directories (built SimpleKeychain / InAppSettingsKit archives, 4 tracked files) and 492 tracked files under `Carthage/` mean third-party binaries are in the repo. Irrelevant to the new repo, noted for provenance.

---

## 6. Vendor inventory & replacements

### 6.1 Dependency managers

- `Cartfile` (2 lines): `github "futuretap/InAppSettingsKit" "3.6"`, `github "auth0/SimpleKeychain" "0.12.5"`; a commented-out Giphy binary spec. `Cartfile.resolved` is identical (tags only, no commit pins). `update_carthage.sh`: `carthage update --platform iOS --use-xcframeworks`.
- `Carthage/Build/` is **not committed**; `pbxproj:1926-1927` reference `Carthage/Build/{InAppSettingsKit,SimpleKeychain}.xcframework`, so a clean checkout does not build until Carthage is run.
- `Carthage/Checkouts/` also holds `PINOperation` (Apache-2.0) and `SnapKit` (MIT). They are **not in Cartfile and not referenced by `pbxproj`** — stale leftovers (grep).
- No SwiftPM, no CocoaPods.

### 6.2 Table

Link column: H = HFRswift, L = legacy `SuperHFRplus` only. "Sites" = usage in code compiled into HFRswift.

| Vendor | Version | License | Targets | Usage sites in HFRswift (file:line) | Used for | Replacement in new app | Removed by (see 8) |
|---|---|---|---|---|---|---|---|
| **ASIHTTPRequest** (`SuperHFRplus/Vendor/ASIHTTPRequest/`: ASIHTTPRequest, ASIFormDataRequest, ASIDataCompressor/Decompressor, ASIInputStream, ASIAuthenticationDialog compiled in H; ASIDownloadCache + ASINetworkQueue L only) | v1.8.1-8 2011-06-05 (`ASIHTTPRequest.m:29`) | BSD-style per upstream; **no LICENSE file in repo** (unverified) | H + L | `Classes/FilterPostsQuotes.m` 9,10,13,90,115,218,261; `HFRplusAppDelegate.m` 37,227; `MPStorage.m` 11,12,157,170,183,191,195,232,273,315,361,407,423,435,441,452,695,741,769,772,780,785,840,912,939,942,952,957; `MultisManager.m` 15,282,290; `ObjCFavoritesLoaderWorker.m` 8,50,51,62,75; `ObjCForumTopicsLoaderWorker.m` 3,158,178; `ObjCForumsLoaderWorker.m` 3,10,19,20,23,26,33; `ObjCTopicListLoaderWorkerBase.m` 3,37,38,47,50,53; `ObjCTopicPageWorker.m` 3,46,87,91,93; `ObjCTopicSearchWorker.m` 3,25,36,38,57; `OfflineStorage.m` 9,208,210,309; `SmileyCache.m` 10; `HFRswift/Wrapped/ParseMessagesOperation.m` 18,121,457,458; `SuperHFRplus/Helpers/ASIHTTPRequest+Tools.m` 2,9,12. Swift only matches the error domain string `"ASIHTTPRequestErrorDomain"` (code 4 = cancelled): `MPListView.swift:220`, `MainWindow.swift:110` | all HTTP (GET/POST/forms/cookies/gzip/timeouts) of the ObjC layer | `URLSession` (async/await) in `HFRNetwork`; `URLRequest` form encoding; per-request cookie injection (`HTTPCookie`) instead of `setRequestCookies:`/`setUseCookiePersistence:NO`; cancellation = `Task` cancel | Network lots (area B/C, not E). Storage-side callers (MPStorage, MultisManager refresh) are rewritten in E-3 / E-6 |
| **HTMLParser / HTMLNode** (Ben Reeves; libxml2 wrapper; `SuperHFRplus/Vendor/HTMLParser/`) | not versioned (2010 headers) | upstream MIT-style (unverified; no LICENSE in repo) | H + L | `Favorite.m` 11,31,33,49,56,62,65,70,76,106,110,111,152,164,165; `FilterPostsQuotes.m` 11,130,282; `HFRplusAppDelegate.m` 36,237-239; `MPStorage.m` 13,702-711,758-760,876-880; `ObjCFavoritesLoaderWorker.m` 13,14,84,85,97,105,108,119; `ObjCForumsParser.m` 6,15,16,36,41,48,61,100; `ObjCTopicListParser.m` 3,62,63,85,118,120,134,140,172,175,232,243,270,275,299,304,309,312,328,331,337,338,340,378,379,391,406,407,453; `ObjCTopicPageWorker.m` 5,105,148-170; `OfflineStorage.m` 229-237; `HFRswift/Wrapped/ParseMessagesOperation.m` 13,80,107,111,136,140,145,149,176,177,192,199,200,220,261-263,334,371-389,398,491,498,501,522,537. HFRswift Swift code has its own pure-Swift parsers (`PollHTMLParser`, `UserProfileHTMLParser`) and does not use the vendor class | HTML scraping of every forum page | SwiftSoup in `HFRParsing` ([ADR 0002](../adr/0002-swiftsoup-html-parser.md)) | Parsing lots; for MPStorage page scraping: E-3 (JSON payload) + a Parsing lot for the PM page |
| **RegexKitLite** 4.0 (`RegexKitLite.h:65-66`) | 4.0 | BSD (header `RegexKitLite.h`) | H + L; needs `libicucore` (H: `pbxproj:2682-2707`; L: `-licucore`, `pbxproj:6347`) | `Favorite.m` 13,188; `FilterPostsQuotes.m` 12; `HFRplusAppDelegate.m` 21,243; `ObjCFavoritesLoaderWorker.m` 15,101; `ObjCForumsParser.m` 7,521; `ObjCTopicListParser.m` 4,91,99,126; `Topic.m` 10,80; `HFRswift/Wrapped/LinkItem.m` 9,86,93,99,140,145,157,173,178,184,189,202,207,215,220,230; `ParseMessagesOperation.m` 12,233,235,268,277,337,351,401,410; `SuperHFRplus/Helpers/RangeOfCharacters.m` 9,237,261 | regex replace/extract on post HTML (images, videos, quotes, links) and on topic titles | Swift Regex (`Regex`, `replacing(_:with:)`) | Parsing lots (LinkItem/message-content transforms) |
| **Reachability** (Apple sample, 2016) | 2016 sample | Apple sample-code licence (`Reachability.h:2-3`) | H + L (needs `SystemConfiguration`) | `HFRplusAppDelegate.m` 68,73,74,120,121; `HFRswift/Wrapped/LinkItem.m` 193 (the `display_images == "wifi"` branch). Effectively constant because `display_images` is forced to `yes` (see 3.1) | "images only on Wi-Fi" | `NWPathMonitor` (`Network` framework) at app level; or drop the option | Network lot / app-level settings lot (E-1) |
| **SimpleKeychain** (Auth0, `A0SimpleKeychain`) | 0.12.5 (`Cartfile`, podspec) | MIT | H + L (embedded, `pbxproj:1583-1593`) | `Classes/MultisManager.m` 14,44,50,81,100,133,224,239,275 (the only Objective-C user; no Swift user) | account store in Keychain | `Security` framework (`SecItemAdd/CopyMatching/Update/Delete`) behind a `CredentialStore` protocol; no third-party | **E-6** |
| **GiphyUISDK** (binary xcframework in `Frameworks/`) | 2.1.7 (`strings` of the binary: `PROJECT:GiphyUISDK-2.1.7`); Info.plist has no version | Giphy SDK terms (proprietary binary; unverified) | H + L (embedded) | `HFRswift/Swift/HFRswiftApp.swift` 9,20; `HFRswift/Swift/AnswerView.swift` 4,103,223,224,227,530,533,2286-2339 (`GiphyViewController`, `GPHTheme`, `GiphyDelegate`) | GIF picker in the composer, inserts `[img]url[/img]` | **Not allowed as a dependency** (only SwiftSoup is). Options: Giphy REST API v1 via `URLSession` + own SwiftUI grid, or drop the feature. Needs an ADR and a key-management decision (see 5.6) | **E-10** (decision) + a composer lot |
| **SDWebImage** framework 5.20.0 (`Frameworks/SDWebImage.framework`) | 5.20.0 (`Info.plist`) | MIT (upstream) | **L only** | n/a. In H the name is satisfied by an in-repo **shim** `HFRswift/Swift/SDWebImage.h/.m` (~200 lines, `NSURLSession` based): `SmileyCache.m` 14 (`#import`), 123,125,186,267,301 (`sd_imageWithGIFData:`, shim `SDWebImage.m:167`). Swift calls the selector `sd_animatedGIFWithData:` via runtime (`AnswerView.swift:1750-1751`, `MessagesView.swift:5588,5922`), which the shim does **not** provide (fallback behaviour unverified) | animated GIF decoding, async image loading | `ImageIO` (`CGImageSource`) for animated GIF frames, `AsyncImage`/`URLSession` + `URLCache` for loading (UIKit/ImageIO live in the App layer, not in `HFRKit`) | E-8 (cache/images) |
| **InAppSettingsKit** 3.6 | 3.6 (`Cartfile`, podspec) | BSD-style with credit request (`Carthage/Checkouts/InAppSettingsKit/LICENSE`) | **L only** (`pbxproj:884,887`); `InAppSettings.bundle` legacy Resources only | none in H (`HFRswift/Swift/AppSettingsView.swift` is its native replacement) | legacy settings UI + plist-driven defaults | SwiftUI `Form` (already done); defaults table lives in code | **E-1** (port the `Root.inApp.plist` defaults) |
| **MBProgressHUD** 0.8 | 0.8 (`MBProgressHUD.h`) | MIT (header) | L only | none | HUD | SwiftUI overlay / `ProgressView` | not needed |
| **MKStoreManager** (Mugunth Kumar) | 2010 | "permission to do anything … retain the URL" (header) | L only (`PayViewController`) | none | StoreKit v1 tip/purchase | StoreKit 2 if a purchase ever returns | not needed |
| **NSData+Base64** (Matt Gallagher, 2009) | 2009 | permissive (header) | L only | none | base64 | `Data.base64EncodedString()` | not needed |
| **DACircularProgress** | 2012 | MIT upstream (unverified) | L only | none | progress ring | SwiftUI | not needed |
| **MWPhotoBrowser** (Michael Waterfall) | 2010 headers | MIT upstream (unverified) | L only (+ `MWPhotoBrowser.bundle`) | none | image viewer | SwiftUI/QuickLook viewer | not needed (image-viewer lot, app side) |
| **PSTCollectionView** (Steinberger) | 2012-13 | MIT upstream (unverified) | L only | none | UICollectionView backport | native | not needed |
| **SVPullToRefresh** (Sam Vermette) | 2012 | MIT upstream (unverified) | L only | none | pull to refresh/infinite scroll | `.refreshable`, `onAppear` paging | not needed |
| `SDWebImage.toremove/`, `WebP.toremove/` | — | — | **neither** (0 references in `pbxproj`) | none | dead source trees | delete | not needed |
| **libiconv** (`libiconv.2.tbd`, `Frameworks/`) | system | system | H + L | `SuperHFRplus/Helpers/ASIHTTPRequest+Tools.m` 10,21-35 (UTF-8 sanitiser that drops invalid bytes). Swift lines containing "iconv" are unrelated identifiers | sanitise response bytes before parsing | `String(decoding: data, as: UTF8.self)` (replacement chars) or `String(validating:)`; for ISO-8859-1 pages use `String.Encoding`, see `LoginService.decodeHTML` | Network/Parsing lots |
| **libicucore** | system | system | H + L | RegexKitLite only | — | Swift Regex | with RegexKitLite |
| **Frameworks linked but with no HFRswift use found** | system | — | H | `WidgetKit`, `AssetsLibrary` (deprecated), `CoreData`, `MessageUI`, `MobileCoreServices` — no import found in the compiled sources (unverified for each) | — | drop | not needed |

Not found compiled into HFRswift (so *not* a concern): CocoaLumberjack, AFNetworking, Firebase/Crashlytics, Sentry (grep).

### 6.3 Removal plan (order)

1. Land `HFRModels` + `HFRStorage` stores (E-1…E-6) — they remove **SimpleKeychain** and **InAppSettingsKit** from the picture, and give the Network/Parsing lots something to talk to.
2. Parsing lots remove **HTMLParser** and **RegexKitLite** (+ `libicucore`, `RangeOfCharacters`).
3. Network lots remove **ASIHTTPRequest** (+ `libiconv`, `ASIHTTPRequest+Tools`, **Reachability**).
4. App-layer lots remove **SDWebImage shim** (E-8) and **Giphy** (E-10).
5. Delete: all L-only vendor directories, the two `.toremove` trees, stale `Carthage/Checkouts/{PINOperation,SnapKit}`. These are simply not ported.

End state: SwiftSoup is the only third-party package, as `AGENTS.md §3.3` requires.

---

## 7. Quirks & dead code

Storage and settings:
1. `updateLastSucessAcessDate` persists `mpstorage_last_rw` with `registerDefaults:` (`MPStorage.m:969-978`). Registered defaults are volatile, so the "last access" shown in Settings resets to `-` after relaunch.
2. `BlackList` can overwrite data with an empty dictionary: `-init` calls `load`, which returns immediately if there is no current pseudo (`BlackList.m:173-175`); any later `save` (e.g. `addToWhiteList`, `BlackList.m:49-54`) writes the empty in-memory `dicBlackList` over `blackListDico.plist`. Order dependence (first access before first login) is **unverified at runtime**.
3. Migration branch of `BlackList.load` writes the *dictionary* to the old `blackList.plist` path and then deletes that file instead of writing `blackListDico.plist` (`BlackList.m:187-192`).
4. Blacklist is keyed by `getCurrentPseudo` for reads (`:93`) but by `getMainCompte[PSEUDO_DISPLAY]` for `setBlackListForActiveCompte` (`:102`); equal today only because "current" == "main" (`MultisManager.m:179-188`).
5. `findIndexFor:` normalises with ZWSP removal + `lowercaseString` (`BlackList.m:133-135`), whereas the server-side username in MPStorage is stored raw (`MPStorage.m:259`): case/ZWSP rules must be carried over.
6. `mpstorage_active` is also a **gate of the blacklist write path** (`BlackList.m:39,57`): turning it on changes the semantics of "add to blacklist" from local to sync-first, and a remote failure aborts the local add.
7. Defaults of the same key differ across layers (IASK seed vs `@AppStorage`, string vs int; `display_images` forced; `filter_posts_*` forced if nil). HFRswift ships no `InAppSettings.bundle`, so ObjC readers see `nil` until a user touches the setting (`HFRplusAppDelegate.m:395-402`).
8. `forumsCache.plist` is read but never written by HFRswift (2.3); "Clear caches" deletes folders nobody writes (2.4); `ImageCache`/`SmileCache` names date back to SDWebImage.
9. `Documents/cache/...` (legacy offline) and `Caches/cache/...` both use a folder called `cache` (`OfflineStorage.m:146-150` vs `:521-531`) — different parents, easy to confuse.
10. HFRswift renders every topic page by writing `Caches/cache/topic-<UUID>.htm` and never removing it (`Common.swift:1962-1976`); `Topic` offline naming is `topic-<page>.htm` (`OfflineStorage.m:500-512`).
11. `MultisManager.getComtpes` (typo, public API used through `NSSelectorFromString`, `Common.swift:1096-1104`). The HFRswift bridges call ObjC singletons by *selector string* via `LegacyLoaderRuntime` (`Common.swift:855-875`) — any rename in the ObjC layer silently disables storage.
12. `MPStorage` mixes sync and async (`saveMPStorageAsynchronous` does a sync POST first, `:932-940`), swallows exceptions with `@try`, and shows UI from model code (alert presenter `HFRSwiftAlertPresenter`).
13. Draft: one global string for all topics (`MessagesView.swift:2668`).
14. `HFRswift/Wrapped/MessagesTableViewController.m` sits in the HFRswift folder but is only compiled by the legacy target (`pbxproj:5808` is inside the legacy Sources phase), while Swift reads KVC keys off such a controller (`Common.swift:1562-1578,1811-1820`). Cross-area: the actual provider of that controller at runtime is **unverified**.
15. Shim/real mismatch: `sd_animatedGIFWithData:` (Swift) vs `sd_imageWithGIFData:` (shim).
16. Dead directories/targets: `SDWebImage.toremove/`, `WebP.toremove/`, `Extensions/` (widgets, no target), `Carthage/Checkouts/{SnapKit,PINOperation}`, `Constants.h:124` placeholder key, `LAST_SMILEYS_FILE` constant, `kTTURL` etc. in `Constants.h`.
17. Seasonal "noel" theme code paths are permanently disabled but still branch at many call sites (`ThemeColors.m:158-1036`).

---

## 8. Proposed lots

IDs are provisional (`E-n`); LOT-000 will assign final numbers. All HFRStorage lots follow the module rules: `HFRStorage` depends only on `HFRModels`; no UIKit/SwiftUI; Linux-buildable; protocols only at the persistence boundary (`ARCHITECTURE.md`). Anything needing the Security framework / Keychain is verified on Mac/device.

Key design decision common to E-1…E-7: **persist through one `StorageBackend` protocol** (in-memory for tests, file/`UserDefaults`/Keychain for the app). Keys and defaults for settings live in `HFRStorage` as constants so SwiftUI `@AppStorage` in the app can reuse the very same strings.

| Lot | Name | Module | Scope | Difficulty | Depends on | Fixtures / tests |
|---|---|---|---|---|---|---|
| **E-1** | Settings catalogue & store | HFRStorage (+ HFRModels enums) | `SettingKey` constants + typed defaults for the ~30 real preferences of 3.1 (names kept identical to legacy so migration is a no-op); `SettingsStore` protocol + `UserDefaults` and in-memory implementations; normalisation rules already in legacy (`auto_theme` clamp, deprecated keys purge, `landscape_mode` values, tolerant Bool parsing for `haptics`, string/int coercion for `vos_sujets`); colour string `"{r, g, b, a}"` codec; no `registerDefaults` side effects. Replaces InAppSettingsKit + `Root.inApp.plist` defaults. | easy | HFRModels | Table-driven tests: every key x default x legacy raw value (string/int/bool/NSNumber). Fixture = a dump of a real `Library/Preferences/<id>.plist` (anonymised) |
| **E-2** | Blacklist / whitelist store | HFRStorage | `PseudoNormalizer` (ZWSP + case rules from `BlackList.m:133-135`), per-account blacklist, global whitelist, JSON file store (atomic), `LegacyBlacklistImporter` for `blackListDico.plist`, `whiteList.plist` and v0 `blackList.plist`; guard against "load skipped then save overwrites" (7.2). Server sync is *not* here. | easy-medium | HFRModels | Fixtures: the three legacy plists (anonymised), empty, corrupted, Unicode/ZWSP pseudos. Tests: add/remove/idempotence, per-account isolation, importer round-trip, never-overwrite-with-empty |
| **E-3** | MPStorage document codec & merge | HFRModels (types) + HFRStorage (logic) | Pure value types for the `0.1` JSON schema (2.6), `Codable` with tolerant decoding (numbers as string/number: `post`, `numreponse`), mutation functions (add/remove blacklist entry, add/remove bookmark, upsert/remove MP flag), timestamp bookkeeping, **conflict-aware merge** using `lastUpdate`/`createDate` (improves legacy last-writer-wins; document the difference), `MPStorageIndex` cache of the PM post id (replaces `dicMPStorage_postid`). The HTTP calls belong to HFRNetwork, the PM page scraping to HFRParsing; the app orchestrates. | medium | HFRModels; consumers in Network/Parsing lots | Fixtures: real MPStorage JSON docs (empty, with 100+ bookmarks, nbsp-polluted, malformed, unknown future `version`). Differential tests against `MPStorage.m` mutation outputs |
| **E-4** | Drafts store | HFRStorage | `DraftStore` keyed by context (new topic / reply to topic+page / PM / edit), text + cursor/attachments metadata optional, TTL cleanup, atomic file store. Migrates the legacy `composerDraftText` (global) to a "legacy" draft. Fixes the volatile new-topic draft. | easy | — | Tests with in-memory + temp-dir backend; fixtures: none (synthetic) |
| **E-5** | Local favourites & small stores | HFRStorage | `SuperFavoritesStore` (`SuperFavoritesIds`), `FavoritesLayoutStore` (visible/hidden category order, collapsed sections), `AppSmileyFavoritesStore` (replaces `smiley_favorites_cache2`; legacy decoder via `NSKeyedUnarchiver` class mapping in the importer only), `SmileySearchHistoryStore` (JSON, max 50), `RehostHistoryStore` (JSON; importer for `rehostImages.plist` is optional). | medium | HFRModels | Fixtures: a real `smiley_favorites_cache2` (binary, generated from the legacy app on a Mac), `rehostImagesSwiftUI.json`, defaults dump |
| **E-6** | Account & credential store (Keychain) | HFRStorage (+ HFRModels `Account`, `StoredCookie`) | `CredentialStore` protocol; `KeychainCredentialStore` on `Security` (service/account naming, accessibility class chosen per Q6, versioned `Codable` envelope; cookie persistence as plain properties, rebuilt into `HTTPCookie` by HFRNetwork, because HFRStorage must not import it); main account, `hash_check`, avatar blob; `LegacyKeychainImporter` that reads the `A0SimpleKeychain` item (service = old bundle id, key `HFR_COMPTES_KEY`) with an explicit class allow-list; in-memory implementation for tests. Cookie jar sync to `HTTPCookieStorage` stays in HFRNetwork. | difficult | HFRModels; Network session lot for cookie injection | Fixtures: an `NSKeyedArchiver` blob of 1-3 accounts with cookies (generated by legacy code on a Mac, **anonymised**: fake cookie values), corrupted blob, empty array. Device tests for real Keychain. Review by security-minded reviewer; no secrets in fixtures (`AGENTS.md §3.4-3.5`) |
| **E-7** | Legacy data import orchestrator | HFRStorage (+ App target glue) | Idempotent `LegacyImport` pipeline: detect old artefacts, run E-1/E-2/E-5/E-6 importers, never delete the source, report per-item result, remember `importedVersion`. Only valid for scenario A of 4.3; otherwise provides the manual export/import format. | medium-difficult | E-1, E-2, E-5, E-6; decision Q1 | Fixture "old container" folder (Documents + Preferences plist + synthetic keychain blob). Mac/device smoke test of an actual update path |
| **E-8** | Cache storage & image decoding | HFRStorage (file cache API) + App (ImageIO) | `CacheDirectory` helper (avatars with 25-day pruning as legacy `HFRplusAppDelegate.m:539`, topic HTML temp files with cleanup, bundle resource copy decision), size/eviction policy; animated-GIF decoding with `ImageIO` in the App layer; removes the SDWebImage shim and the stale "ImageCache/SmileCache" purge. Offline-reading feature: **explicitly out of scope unless the maintainer wants it** (Q5). | easy-medium | — | Tests: eviction by age/size on a temp dir; GIF decoding fixtures (animated GIF, static, corrupt) |
| **E-9** | Persistence parity checklist (docs only) | docs | One document tying 2-3 to the final stores: for each legacy key/file, new location, migrated Y/N, test id. Closes the loop for reviewers. | easy | E-1..E-8 | — |
| **E-10** | Third-party keys & Giphy decision (ADR) | docs/ADR + App config | ADR on how API keys are injected (xcconfig + CI secret, never committed), on rotating the two keys currently hard-coded (5.6), and on GIF search: Giphy REST via `URLSession` vs drop. | easy (decision) / medium (Giphy REST client in HFRNetwork) | maintainer approval | — |

### Vendor removal map (summary)

| Vendor | Eliminated by |
|---|---|
| SimpleKeychain | **E-6** |
| InAppSettingsKit | **E-1** (and `AppSettingsView` already native) |
| SDWebImage (shim + framework) | **E-8** |
| Giphy SDK | **E-10** + composer lot |
| ASIHTTPRequest, libiconv, Reachability | HFRNetwork lots (area B/C) |
| HTMLParser, RegexKitLite, libicucore | HFRParsing lots (area A/D) |
| MBProgressHUD, MKStoreManager, NSData+Base64, DACircularProgress, MWPhotoBrowser, PSTCollectionView, SVPullToRefresh, `*.toremove`, `Extensions/`, stale Carthage checkouts | not ported (legacy-only) |

### Fixture rule reminder

Real keychain blobs, cookies, `hash_check`, pseudos and blacklists are personal data/secrets. Generate fixtures from synthetic accounts (fake cookie values, invented pseudos) or anonymise before commit ([FIXTURES](../FIXTURES.md)). The legacy "oracle" for storage is the *file format*, not the user data.

---

## 9. Open questions

1. **Bundle id and team of the new app.** Same as the currently shipped app (`hfrplus.red.super`?) or new? Decides scenario A/B/C of 4.3 and whether E-7 exists at all. Also: which id is on the App Store today — unverified (`pbxproj:6100` vs `:6351`).
2. Is the legacy line (`hfrplus-legacy.red.super`) still published/updatable (needed for an export or shared keychain group)?
3. Should the new app keep **MPStorage** at all (PM-as-database, schema `0.1`), or replace it by local-only storage? Other HFR clients may read the same PM (the schema carries `sourceName`; unverified) — compatibility constraints need the maintainer's input.
4. Blacklist authority: server (MPStorage, only when enabled) or local? Today the server list **replaces** the local one on load (`MPStorage.m:208-215`). Keep?
5. Is **offline topic reading** a requirement? In HFRswift it is effectively unused; dropping it removes `OfflineStorage`, `Topic`/`Forum` `NSCoding`, and Documents/cache.
6. Keychain accessibility for the new account store: `AfterFirstUnlock` (as legacy, moves with backups) or `ThisDeviceOnly`? Sync via iCloud Keychain desired?
7. The two hard-coded keys (Giphy, img3/Chevereto): rotate? Who owns them? They are in the public history of the legacy repo.
8. `size_smileys` has no reader in HFRswift-compiled code: keep as a setting? (unverified: may be applied via CSS elsewhere).
9. `display_images` (`wifi` mode) is forced to `yes`; keep the option, and therefore `NWPathMonitor`?
10. `vos_sujets` stored as String in HFRswift vs Int in IASK seed: which canonical type for E-1? (Proposal: Int in the new store, coerce on import.)
11. Is `periodicMaintenance`/`BACKGROUND_MAINTENANCE` active in HFRswift (avatar pruning, `Caches/cache` cleanup)? Macro value not inspected.
12. `libxml2` header/link settings for `HTMLParser.m` do not appear in the HFRswift build configurations (`HEADER_SEARCH_PATHS` for libxml2 is only in the legacy config, `pbxproj:6331,6396`); unverified how HFRswift resolves them (module map?). Irrelevant for the port, relevant if someone tries to build the oracle.
