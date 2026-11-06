# Audit B — List parsing and data models

- Legacy reference: `/home/user/HFRnow` at commit `2440d79` (read-only). All `file:line` below are relative to that repository unless prefixed `new:`.
- Area: HTML parsing of forum lists / topic lists / favorites / MP list / search results / polls, plus the data models they fill.
- Boundaries (not audited in depth): networking and cookies (agent "network"), message-page parsing (`ParseMessagesOperation`, `ObjCTopicPageWorker`, renderers: agent "messages"), reply posting, storage (`MPStorage`, `OfflineStorage`, `BlackList`, UserDefaults: agent "storage").
- "unverified" = deduced from code only, no HTML sample was available in the repo. Every selector below should be confirmed by a captured fixture (see "Fixtures to capture").

## 1. Scope

### 1.1 Target membership

Method: `SuperHFRplus.xcodeproj/project.pbxproj` has three `PBXSourcesBuildPhase` (lines 5704, 5711, 5763). Phase 5711 belongs to the new target **HFRswift** (target `15B0AA842E2C27DD0092C0FD`, `Sources` = `15B0AA812E2C27DD0092C0FD`, pbxproj:5710); phase 5763 belongs to the old **SuperHFRplus** target (`CA7C70B9185EF50E00B348BA`). All Swift files of `HFRswift/Swift/` are compiled into HFRswift through a `PBXFileSystemSynchronizedRootGroup` (pbxproj:2671, 4292-4294) with no exception set (`grep ExceptionSet` returns nothing), so every `.swift` in that folder is in HFRswift.

`APP_SWIFT=1` is defined through `GCC_PREPROCESSOR_DEFINITIONS` (pbxproj:5967, 6014, 6072, 6153), which disables the legacy UIKit code paths in `FilterPostsQuotes.m` (`#if !APP_SWIFT`).

| File | Lines | HFRswift | SuperHFRplus | Role |
|---|---:|:-:|:-:|---|
| `Classes/ObjCForumsParser.m` (+.h) | 535 | yes (pbxproj:5728) | no | Home page → `[Forum]` |
| `Classes/ObjCTopicListParser.m` (+.h) | 472 | yes (5717) | no (but `BaseTopicsViewController.m:370`, in SuperHFRplus, calls it: legacy target probably does not link, unverified) | Topic list / MP list / search results page → `ObjCTopicListParsingResult` |
| `Classes/ObjCTopicListLoaderWorkerBase.m` | 76 | yes | no | Base class holding the parsing result as properties, builds the request |
| `Classes/ObjCForumTopicsLoaderWorker.m` | 195 | yes | no | Derives list URLs per flag, runs the parser |
| `Classes/ObjCMPTopicsLoaderWorker.m` | 21 | yes | no | MP list = forum topic list on `cat=prive` |
| `Classes/ObjCForumsLoaderWorker.m` | 56 | yes | no | Fetch + `ObjCForumsParser` |
| `Classes/ObjCFavoritesLoaderWorker.m` | 197 | yes (5747) | no | Fetch + parse of the favorites page (parsing is inline here, lines 79-168) |
| `Classes/ObjCForumSearchWorker.m` | 344 | yes | no | Global search: POST, meta-refresh redirect, then topic list parser |
| `Classes/ObjCTopicSearchWorker.m` | 69 | yes | no | In-topic search POST, reads `Location` header only (network, no HTML) |
| `Classes/Forum.m` / `.h` | 182 / 29 | yes | yes | Model + hard-coded id/icon tables |
| `Classes/Topic.m` / `.h` | 160 / 93 | yes | yes | Model |
| `Classes/Favorite.m` / `.h` | 224 / 26 | yes | yes | Model + parsing of a favorites category and of its topic rows |
| `Classes/Bookmark.m` / `.h` | 21 / 34 | yes | yes | Model, filled from MPStorage JSON (storage lot) |
| `Classes/Catcounter.m` / `.h` | 14 / 24 | **no (legacy-only)** | yes (pbxproj:5804) | Dead model, only imported by legacy `FavoritesTableViewController.m:20` |
| `Classes/FilterPostsQuotes.m` (+.h) | 386 | yes | yes | Crawler that loads topic pages and runs `ParseMessagesOperation` with `filterPostsQuotes:YES`; no list parsing (see 3.9) |
| `SuperHFRplus/Vendor/HTMLParser/HTMLParser.m`, `HTMLNode.m` | 116 / 478 | yes | yes | libxml2 wrapper |
| `SuperHFRplus/Vendor/RegexKitLite/RegexKitLite.m` | 2636 | yes | yes | Regex category (ICU) |
| `SuperHFRplus/Helpers/RangeOfCharacters.m` | 381 | yes (5748) | yes (5866) | String helpers used by parsers (`decodeSpanUrlFromString2`, `wordAfterString:`, `stringByRemovingAnchor`, `filterTU`) |
| `SuperHFRplus/Helpers/ASIHTTPRequest+Tools.m` | 51 | yes | yes | `safeResponseData` (iconv UTF-8 sanitiser) |
| `HFRswift/Swift/Favorites.swift` | 1286 | yes | n/a | SwiftUI favorites screen + view model; almost no parsing, see 3.5 |
| `HFRswift/Swift/FavoritePostFilterService.swift` | 319 | yes | n/a | Bridge to `FilterPostsQuotes` + `ObjCFilteredPostsRendererWorker` through `NSClassFromString`; no parsing of lists |
| `HFRswift/Swift/PollData.swift` | 391 | yes | n/a | Pure-Swift poll models + regex parser + vote POST |
| `HFRswift/Swift/Common.swift` | 3215 | yes | n/a | Contains the Swift bridges to the ObjC loaders (lines 1398-1612), `Identifiable` retro-fits (13-23), `TopicListFlag` (1510-1515); rest is UI |
| `HFRswift/Swift/ForumSearchService.swift` | 305 | yes | n/a | `ForumSearchPageInfo` (129-~200) and search params, bridge to `ObjCForumSearchWorker` |
| `HFRswift/Swift/MPBackgroundService.swift` | ~170 | yes | n/a | Own regex for the MP counter (115-139) |
| `HFRswift/Swift/MPListView.swift` | 687 | yes | n/a | `MPTopicReadState` (12-36): `[non lu]` title prefix |

Legacy-only in my area: `Catcounter.*`, `BaseTopicsViewController.m` and the UIKit table-view controllers that consume the models (not read).

### 1.2 Entry points and callers (HFRswift path)

| Page | Parser entry | Called by | Swift side |
|---|---|---|---|
| Home (forum list) | `-[ObjCForumsParser parseForumsFromData:]` (`ObjCForumsParser.m:11`) | `ObjCForumsLoaderWorker.m:28` | `ObjCForumsLoader` `Common.swift:1480-1508` via `NSClassFromString` + `unsafeBitCast` of the IMP |
| Forum topic list (all/flags/favorites tabs) | `-[ObjCTopicListParser parseData:currentURL:]` (`ObjCTopicListParser.m:59`) | `ObjCForumTopicsLoaderWorker.m:163` | `ObjCForumTopicsLoader` `Common.swift:1535-1612`, reads the worker's KVC properties for pagination (`pageInfo(from:)`, 1569-1581) |
| MP list | same parser | `ObjCMPTopicsLoaderWorker` inherits `ObjCForumTopicsLoaderWorker` (`.h`), forces URL `/forum1.php?config=hfr.inc&cat=prive&page=1` (`ObjCMPTopicsLoaderWorker.m:9-10`) | `ObjCMPTopicsLoader` `Common.swift:1444-1474` |
| Global search results | same parser | `ObjCForumSearchWorker.m:249` | `ForumSearchService.swift:255-305` |
| Favorites (`forum1f.php`) | `-[ObjCFavoritesLoaderWorker parseFavoritesFromData:]` (`:79`) → `-[Favorite parseNode:]` / `-[Favorite addTopicWithNode:]` (`Favorite.m:31, 49`) | `fetchContentComplete:` (`ObjCFavoritesLoaderWorker.m:62`) | `ObjCFavoritesLoader` `Common.swift:1408-1437`, `FavoritesViewModel` `Favorites.swift:209-291` |
| Poll | `PollHTMLParser.parse(from:)` (`PollData.swift:107`) | `Common.swift:1818` (poll HTML extracted by `ObjCTopicPageWorker.m:160-162`, message-page lot) | `PollView.swift` |

## 2. Data models

### 2.1 Legacy inventory

All models are mutable `NSObject` classes bridged to Swift through the bridging header (ObjC `int` becomes `Int32`, e.g. `Favorites.swift:1192-1193`). The Swift `Identifiable` conformance is by object identity (`Common.swift:13-23`): there is **no stable identity** (no `==`, no `id` derived from content), which is why `Favorites.swift:502-519` re-invents a section id.

#### Forum (`Classes/Forum.h`, `Forum.m`)

| Field | Type | Source / rule |
|---|---|---|
| `aTitle` | String | `<b>` text of the category cell (`ObjCForumsParser.m:62`), or sub-category link text (`:104`), or `cHeader` link text for favorites (`Favorite.m:39`) |
| `aURL` | String (relative path, rewritten `liste_sujet-1.htm` form for the home page; `forum1.php?...&cat=N...` for favorites) | `a.cCatTopic@href` (`ObjCForumsParser.m:67`) |
| `aID` | String | **Only set by the favorites parser** (`Favorite.m:37,43`, from `cat=`). Never set by the home page parser: forums from the home page have `aID == ""`. |
| `subCats` | NSMutableArray<Forum> | Home page sub-categories (`.Tableau` links) + hard-coded additions; first element is a copy of the parent ("all") (`ObjCForumsParser.m:88-96`) |
| derived `getHFRID` | Int | Lookup of `aURL` in a 22-row hard-coded table (`Forum.m:34-61`), 0 if unknown. Sub-forums always give 0. |
| derived `getImage` / `getImageFromID:` | asset name | Second hard-coded table URL → id (`Forum.m:63-91`) and id → asset (`:99-128`, default `ShieldFilled-40`). UI concern, not for HFRModels. |
| derived `URLforType:` | relative URL | `kCatTemplateURL` = `/forum1.php?config=hfr.inc&cat=$1&page=1&subcat=$2&owntopic=$3` (`Constants.h:65`); `$2` always empty; owntopic: kFav=3, kFlag=1, kRed=2, kALL=0 (`Forum.m:157-179`). Callers in HFRswift: none found (`grep URLforType` in `HFRswift` is empty); the worker rebuilds URLs itself. |
| NSCoding | `aTitle,aURL,aID,subCats` | Persisted in `forumsCache.plist` through `NSKeyedArchiver`; read from Swift in `ForumSearchView.swift:455-465` (storage lot) |

Hard-coded id table (`Forum.m:34-58`; same table duplicated at `:63-87`): Hardware 1, HardwarePeripheriques 16, OrdinateursPortables 15, gsmgpspda 23, OverclockingCoolingModding 2, electroniquedomotiquediy 30, apple 25, VideoSon 3, Photonumerique 14, JeuxVideo 5, WindowsSoftware 4, reseauxpersosoho 22, systemereseauxpro 21, OSAlternatifs 11, Programmation 10, Graphisme 12, AchatsVentes 6, EmploiEtudes 8, Setietprojetsdistribues 9, Discussions 13, Blabla-Divers-back-to-life 24, ia 32 (also with the absolute URL `https://forum.hardware.fr/hfr/ia/liste_sujet-1.htm`). The URL pattern is always `/hfr/<Slug>/liste_sujet-1.htm`.

#### Topic (`Classes/Topic.h`, `Topic.m`)

| Field | Type | Filled by | Notes |
|---|---|---|---|
| `_aTitle` / `aTitle` | String | list parser, favorites | `setATitle:` runs `filterTU` (`Topic.m:90-94`): replaces "topic unique", "T.U.", "topik unique", "toupik ounik", "topique unique", "topic unik", "topik unik", "topic officiel", "TOPIKUNIK" (case-insensitive) with "TU" (`RangeOfCharacters.m:330-343`). A display rewrite hidden in a setter. |
| `aURL` | String | list parser: title link (`ObjCTopicListParser.m:323`); favorites: flag link, else last-post link (`Favorite.m:163-178`) | **Different meaning between the two parsers** |
| `aURLOfFirstPage` | String | favorites only: title link (`Favorite.m:101-102`) | empty for list parser |
| `aURLOfFlag` | String | list parser (`:342-343`, "" if none); not set by favorites | link in the flag cell = "go to last read position" |
| `aTypeOfFlag` | String "red" / "blue" / "yellow" / "" | list parser (`:347-355`) | derived from the flag image file name |
| `aURLOfLastPost` | String | `sujetCase9` first child href (`:417`, `Favorite.m:115`) | |
| `aURLOfLastPage` | String | `sujetCase4 a@href` else `aURL` (`:453-464`) | |
| `aDateOfLastPost` | String, display only | computed relative label (see 3.3.5) | UI formatting inside the parser; depends on the current time |
| `dDateOfLastPost` | Date? | `dd-MM-yyyy à HH:mm`, Europe/Paris (`:421-425`) | `Topic.init` assigns `[NSDate alloc]` (uninitialised object, `Topic.m:59`) |
| `aAuthorOfLastPost` | String | `<b>` in `sujetCase9` first child (`:409-415`) | |
| `aAuthorOrInter` | String | `sujetCase6` first `a`, else first `span`, else "" (`:391-403`) | author of the topic for forums, interlocutor(s) for MP |
| `aRepCount` | Int | `sujetCase7` text → intValue (`:328-329`) | replies count |
| `maxTopicPage` | Int | `sujetCase4 a` text → intValue, else 1 (`:453-464`) | page count |
| `curTopicPage` | Int | page number extracted from `aURLOfFlag` (list) or from `aURL` (favorites) (`:357-367`, `Favorite.m:181-199`) | 0 when no flag (list parser) |
| `isViewed` | Bool | `sujetCase1 img@alt == "On"` means **not** viewed (`:374-388`); favorites: set YES only when there is no flag link (`Favorite.m:167-173`), never set otherwise | different semantics |
| `isViewedFromForumAtLoad` | Bool | list parser only | snapshot of `isViewed` at load; used by 5 Swift call sites |
| `isLocallyViewedInApp` | Bool | UI (Swift sets it in `Favorites.swift:841-848`, `MPListView.swift:31`) | not a parsing output; session state |
| `isPoll` | Bool | poll image presence (`:331-334`, `Favorite.m:68-73`) | two different image URLs, see 4 |
| `isSticky` | Bool | row class contains `ligne_sticky` (`:281-284`) | |
| `isClosed` | Bool | `img[alt=closed]` inside `sujetCase3` (`:285-288`) | |
| `isSuperFavorite` | Bool | UI; persisted in UserDefaults `SuperFavoritesIds` (`Favorites.swift:112-136`, keyed by `postID`) | not parsed |
| `hasNewMessageInTopic` | Bool | never written in my files | probably dead (unverified, not grepped across the whole repo) |
| `postID`, `catID` | Int | **favorites only**: hidden inputs `name~"topic"` and `name~"valuecat"` (`Favorite.m:61-66`) | the list parser never sets them; Swift re-derives them from URLs (`MainWindow.swift:~470-500`) |
| `sLastSearchPostURL`, `sLastSearchPostContent` | String | search results: 2nd `a` of `sujetCase3`, `.s1` text (`:297-319`) | |
| `isTopicLoadedInCache`, `curTopicPageLoaded`, `minTopicPageLoaded`, `maxTopicPageLoaded` | | Offline cache state, set by message-page code | not parsing; storage/messages lots |
| `getURLforPage:` | String | replaces the value after `page=` with N and strips the `#anchor` (`Topic.m:73-84`) | crashes if no `page=` (4.x) |

Identity: no explicit rule. The only stable identifier is `postID` (topic id, `post=` query parameter of `forum2.php`) together with `catID`; for list-parser topics it must be parsed from `aURL` (`forum2.php?config=hfr.inc&cat=13&post=1234&page=1...`, example in `Favorites.swift:1187`, `Bookmark.h` header comment).

NSCoding (`Topic.m:101-157`): persists 20 fields but not `isPoll`, `isSticky`, `isClosed`, `isSuperFavorite`, `sLastSearch*`; `isViewed*` reset to NO on decode. `encodeWithCoder` calls `NSLog(@"encodeWithCoder", self)` (format string without `%@`, `:102`).

#### Favorite (`Classes/Favorite.h/.m`)

| Field | Type | Notes |
|---|---|---|
| `forum` | Forum? | `aURL`, `aID`, `aTitle` of the `cHeader` link |
| `topics` | NSMutableArray<Topic> | |
| `order` | NSNumber? | Position, not parsed: assigned by the loader from UserDefaults arrays `arrayCategoriesVisibleOrder` / `arrayCategoriesHiddenOrder` (`ObjCFavoritesLoaderWorker.m:112-146`). `init` does `[[NSNumber alloc] init]` (`Favorite.m:26`), an invalid NSNumber. |

A `Favorite` is a **category section** of the favorites page, not a single favorite topic. Swift section id fallback chain: `forum-id`, `forum-url`, `forum-title`, `favorite-order`, `favorite-first-post` (`Favorites.swift:502-519`).

#### Bookmark (`Classes/Bookmark.h/.m`)
`sPost` (topic id, String), `sCat`, `sNumResponse` (post id, String), `sLabel`, `sAuthorPost`, `dateBookmarkCreation` (Date, ms epoch in JSON), `getUrl` = `/forum2.php?config=hfr.inc&cat=%@&post=%@&numreponse=%@#t%@` (`Bookmark.m:17-19`). Filled from MPStorage JSON `data[0].bookmarks.list[]` with keys `numreponse, post, cat, author, label, createDate` (`MPStorage.m:330-344, 598-607`, `Bookmark.h` header comment). No HTML parsing: model only for this area; persistence belongs to the storage lot. Types are all `NSString` even for numeric ids.

#### Catcounter (`Classes/Catcounter.h/.m`)
`name`, `id` (NSNumber), `length`, `lengthB4`. Legacy-only, unused (imported at `FavoritesTableViewController.m:20`, no other references in the repo). Do not port.

#### Parsing results (not models, but they carry list state)

`ObjCTopicListParsingResult` (`ObjCTopicListParser.h:5-24`): `topics`, `statusInfo` (dictionary `{status: kMaintenance|kNoResults|kNoAuth, message}`; enum at `Constants.h:23-30`), `needToUpdateMP`, `sNewMPNumber`, `currentUrl`, `currentCat`, `forumNewTopicUrl`, `forumBaseURL`, `forumFavorisURL`, `forumFlag1URL`, `forumFlag0URL`, `pageNumber`, `firstPageNumber`, `lastPageNumber`, `firstPageUrl`, `lastPageUrl`, `nextPageUrl`, `previousPageUrl`. Defaults: pages 1/1/1, strings "" (`ObjCTopicListParser.m:42-53`).

Poll (`PollData.swift:12-36`): `PollOption {id: Int (1-based), text, fieldName}`, `PollResult {id, label, percentage: Double, voteCount: Int}`, `PollData {question, footer, maxChoices, options, results, hiddenFields: [String:String]}`; `id` of `PollData` is the question text (not unique). Pure Swift already.

Swift-side pagination model `ForumSearchPageInfo` (`ForumSearchService.swift:129-~200`): `currentURL, nextPageURL, previousPageURL, firstPageURL, lastPageURL, categoryID, pageNumber, firstPageNumber, lastPageNumber, resultCount`, built from an untyped `NSDictionary` (`init(raw:)`). It is the closest existing thing to a typed page model.

### 2.2 Proposed Swift value types for `HFRModels`

All `Sendable`, `Hashable`, `Codable` where persisted. Strings for URLs stay `String` (relative, as HFR serves them) or `URL` resolved against the base URL by the caller; decision to take in the first lot (open question 1).

```swift
public struct ForumCategory: Sendable, Hashable, Identifiable, Codable {
    public var id: String             // stable identity: the forum path
    public var categoryID: Int?       // HFR cat id; nil when not derivable
    public var title: String
    public var path: String           // "/hfr/Hardware/liste_sujet-1.htm" or forum1.php?... form
    public var subforums: [ForumLink] // empty if none
}
public struct ForumLink: Sendable, Hashable, Codable { public var title: String; public var path: String }

public enum TopicFlag: String, Sendable, Codable { case red, blue, yellow }   // flag0.gif, flag1.gif, favoris.gif
public enum TopicListFilter: Int, Sendable { case all = 0, flagged = 1, read = 2, favorites = 3 } // owntopic query value

public struct TopicID: Sendable, Hashable, Codable { public var category: Int; public var topic: Int }

public struct LastPost: Sendable, Hashable, Codable {
    public var author: String; public var path: String
    public var date: Date?           // Europe/Paris
}

public struct TopicSummary: Sendable, Hashable, Identifiable, Codable {
    public var id: String            // stable identity: the topic path
    public var topicID: TopicID?     // nil if not parseable from URLs
    public var title: String         // raw title; the "TU" rewrite is a presentation transform
    public var path: String          // title link
    public var firstPagePath: String?
    public var repliesCount: Int
    public var pageCount: Int        // >= 1
    public var lastPagePath: String
    public var lastPost: LastPost?
    public var starterOrInterlocutors: String
    public var flag: TopicFlag?
    public var flagPath: String?     // resume position
    public var currentPage: Int?     // from the flag URL
    public var hasUnreadReplies: Bool? // sujetCase1 "On"; nil for favorites
    public var isSticky: Bool; public var isClosed: Bool; public var isPoll: Bool
    public var searchHit: SearchHit? // snippet + matching post URL
}
public struct SearchHit: Sendable, Hashable, Codable { public var postPath: String; public var snippet: String }

public struct PageNavigation: Sendable, Hashable, Codable {
    public var current: Int; public var first: Int; public var last: Int
    public var firstPath, lastPath, nextPath, previousPath: String?
}
public struct TopicListTabs: Sendable, Hashable, Codable { public var all, favorites, flagBlue, flagRed: String? }

public struct TopicListPage: Sendable, Hashable, Codable {
    public var topics: [TopicSummary]
    public var navigation: PageNavigation
    public var tabs: TopicListTabs
    public var categoryID: String?
    public var newTopicPath: String?
    public var unreadPrivateMessages: Int?
}
public enum ListPageFailure: Error, Sendable, Equatable { case maintenance(String), notAuthenticated(String), malformed(String) }
// "no results" is a value (empty topics), not an error, but keep a flag if the UI needs the message.

public struct ForumListPage: Sendable, Hashable { public var forums: [ForumCategory]; public var isLoggedIn: Bool; public var unreadPrivateMessages: Int?; public var hashCheck: String? }

public struct FavoriteSection: Sendable, Hashable, Identifiable, Codable {
    public var id: String            // "cat:<id>", or "path:<forum path>" when categoryID is nil - stable, replaces Favorites.swift:502-519
    public var forum: ForumLink; public var categoryID: Int?
    public var topics: [TopicSummary]    // postID/catID always present here
}
public struct Bookmark: Sendable, Hashable, Codable, Identifiable {
    public var topicID: Int; public var categoryID: Int; public var postID: Int
    public var author: String; public var label: String; public var createdAt: Date
}
// Poll: reuse PollOption / PollResult / PollData (PollData.swift:12-36), drop the String-keyed id, add Poll.Kind { votable, results }.
```

Derived or UI-state fields to leave out of `HFRModels`: relative date label (`aDateOfLastPost`), `isLocallyViewedInApp`, `isSuperFavorite`, `order`/hidden categories, cache state (`isTopicLoadedInCache`, `*PageLoaded`), icon asset names (`getImage`). Session token (`hash_check`) is a network/session concern, returned separately (open question 4).

## 3. Parsing rules per page type

General facts for all pages:
- Backend: `HTMLParser initWithData:` = `htmlReadDoc` (libxml2) forcing `UTF-8` and `XML_PARSE_NOERROR|NOWARNING` (`HTMLParser.m:63-88`). Input pointer is `[data bytes]` used as a C string (relies on NUL termination, unverified). Only the home page goes through `safeResponseData` (iconv UTF-8→UTF-8 discarding invalid sequences, `ASIHTTPRequest+Tools.m:14-38`, used at `ObjCForumsLoaderWorker.m:28`); topic list and favorites use raw `responseData` (`ObjCForumTopicsLoaderWorker.m:163`, `ObjCFavoritesLoaderWorker.m:64`), the search worker decodes with `NSUTF8StringEncoding` only for the redirect page and passes raw data to the parser (`ObjCForumSearchWorker.m:46,249`).
- HTML entities: libxml2 decodes them in `allContents` (`xmlNodeGetContent`, `HTMLNode.m:377-397`) and in attribute values. `contents` (`HTMLNode.m:327-335`) returns **only the first child text node**, which silently drops text after an inline tag.
- Selectors: `findChildWithAttribute:matchingName:allowPartial:` does depth-first, document-order search on one attribute; `allowPartial:NO` = whole-attribute string equality (so `class="sujet ligne_booleen"` is NOT matched by `matchingName:@"sujet"`); `YES` = `strstr` substring, case-sensitive (`HTMLNode.m:232-278`). No multi-class token logic. In SwiftSoup this must be reproduced explicitly (`[class=x]` exact vs `[class*=x]`). `findChildOfClass:@"none"` = exact class `none`.
- Whitespace-only text nodes are kept by libxml2, so `firstChild` / `children[i]` positions depend on the exact serialisation (3.3.3, 3.3.5): fragile, needs fixtures.

### 3.1 Home page: forum / category list (`ObjCForumsParser.m`)

Request: `GET <ForumURL>` (`ObjCForumsLoaderWorker.m:20`).

1. Maintenance: `body.firstChild.tagName == "p"` → posts `kStatusChangedNotification {kMaintenance, trimmed p content}` and returns `[]` (`:20-31`). Side effect inside a parser.
2. Login: `input[name=hash_check]` with non-empty `value` → `isLogged = true` and `HFRplusAppDelegate.hash_check = value` (`:36-43`). `hash_check` is the CSRF-like token used by every POST (also read in `ObjCFavoritesLoaderWorker.m:105-106`, `ObjCForumSearchWorker.m:159`).
3. Rows: all nodes with `class` containing `cat` (partial, case-sensitive), keeping only `tr` (`:18, 48-52`). Per row: `td` list, **td[1]** is the category cell (`:54-61`, raises if fewer than 2 `td`).
4. Title: first `<b>` in td[1], `allContents` trimmed (`:62`).
5. URL: first descendant with class containing `cCatTopic`, `href` (`:67`). Special fix: `/hfr/AchatsVentes/Hardware/liste_sujet-1.htm` → `/hfr/AchatsVentes/liste_sujet-1.htm` (`:69-71`).
6. "Apple" censorship: when not logged in and title == "Apple", the row is skipped completely (`:77-80`). Same category is visible when logged in (id 25 `apple` in `Forum.m`).
7. Sub-categories: descendants of td[1] with class exactly `Tableau` (`:84`). If any: sub list starts with a copy of the parent (same title/URL, acts as "all", `:88-96`), then for each link: title = `allContents` trimmed, URL = `href`, plus **hard-coded injections** (see table) (`:100-509`).
8. Private messages: if `aForumURL` contains `cat=prive` the row is not added to `forums`; instead the digits in the `cCatTopic` node text are extracted with `stringByReplacingOccurrencesOfRegex:@"[^.0-9]+([0-9]{1,})[^.0-9]+" withString:@"$1"` and passed to `updateMPBadgeWithString:` which writes UserDefaults `nb_mp` and the tab badge (`:516-525`; `HFRplusAppDelegate.m:700-712`). The regex is a replace-all, so it only works for strings like "Vous avez 2 nouveaux messages" (unverified wording).
9. Output order = document order. `aID` is never set.

Hard-coded sub-forum injections (not present in the fetched HTML; unverified why, probably the home page lists only part of the sub-forums). Trigger = sub-forum URL found in a `.Tableau` link; `Added` = (title, URL). "before" means appended before the trigger sub-forum itself, "after" after it (`:111-156` vs `:158`, `:160-503`):

| Trigger (all `/liste_sujet-1.htm`) | Position | Added |
|---|---|---|
| `/hfr/Programmation/API-Win32/` | before | Divers `/hfr/Programmation/Divers-6/`, ADA `/hfr/Programmation/ADA/`, Algo `/hfr/Programmation/Algo/` |
| `/hfr/Programmation/API-Win32/` | after | ASM `/hfr/Programmation/ASM/`, ASP `/hfr/Programmation/ASP/`, Biblio Links `/hfr/Programmation/BiblioLinks/`, C `/hfr/Programmation/C/` |
| `/hfr/Hardware/minipc/` | after | Bench `/hfr/Hardware/Benchs/` |
| `/hfr/OverclockingCoolingModding/Mod-elec/` | after | Divers `/hfr/OverclockingCoolingModding/Divers-8/` |
| `/hfr/Photonumerique/Galerie-Perso/` | after | Divers `/hfr/Photonumerique/Divers-7/` |
| `/hfr/WindowsSoftware/Windows-nt-2k-xp/` | after | Win 9x/Me `/hfr/WindowsSoftware/Win-9x-me/` |
| `/hfr/Programmation/C-2/` | after | C#/.NET managed `/hfr/Programmation/CNET-managed/` |
| `/hfr/Programmation/Delphi-Pascal/` | after | Flash/ActionScript `/hfr/Programmation/Flash-ActionScript/` |
| `/hfr/Programmation/Java/` | after | Langages fonctionnels `/hfr/Programmation/Langages-fonctionnels/`, PDA `/hfr/Programmation/PDA/`, Perl `/hfr/Programmation/Perl/` |
| `/hfr/Programmation/PHP/` | after | Python `/hfr/Programmation/Python/`, Ruby/Rails `/hfr/Programmation/Ruby/` |
| `/hfr/Programmation/SGBD-SQL/` | after | Shell/Batch `/hfr/Programmation/Shell-Batch/` |
| `/hfr/Programmation/VB-VBA-VBS/` | after | XML/XSL `/hfr/Programmation/XML-XSL/` |
| `/hfr/Graphisme/Arts-traditionnels/` | after | Concours `/hfr/Graphisme/Concours-2/`, Ressources `/hfr/Graphisme/Ressources/`, Divers `/hfr/Graphisme/Divers-5/` |
| `/hfr/AchatsVentes/Softs-livres/` | after | Divers `/hfr/AchatsVentes/Divers-4/` |
| `/hfr/AchatsVentes/Feedback/` | after | Règles et coutumes `/hfr/AchatsVentes/Regles-coutumes/` |

Pattern: each injected entry looks like the "last" alphabetical sub-forum following the trigger on the live site (the trigger's real neighbour), so the home page probably truncates the list; unverified, requires a fixture of the real home page and a manual check of the live site. This table must be data (static dictionary in HFRParsing or better a remote-less fallback), with a dedupe rule (not present in legacy: if the site starts to serve them, they would be duplicated).

Edge cases handled: maintenance; not logged (Apple hidden); MP row routed to badge. Not handled: rows with a missing `cCatTopic` (nil → `initWithString:nil` raises, `:67, :108`), missing `<b>`.

### 3.2 Sub-category pages
There is no dedicated sub-category parser. A sub-forum is a `Forum` with title + `liste_sujet-1.htm` URL and is browsed with the normal topic list parser (3.3). In HFRswift the user can switch between the parent and its `subCats` (`MainWindow.swift:311-318, 595-600`, parent first in `availableForums`; the parent copy already in `subCats` is therefore duplicated in the picker, unverified). Flag tabs for sub-forums fall back to the unfiltered URL (see 3.3.1).

### 3.3 Topic list (`ObjCTopicListParser.m`) — also used for MP list and search results

#### 3.3.1 Request URLs (worker, not parser)
- Derived by `ObjCForumTopicsLoaderWorker.m:91-156`: if `forum.aURL` contains `forum1.php` and `cat=`, rewrite query items `owntopic` (0 all, 3 favorites, 1 flag1/"tracked", 2 flag0/"read") and force `page=1` (`:36-82`); else if `getHFRID` > 0 (or numeric `aID`) build `/forum1.php?config=hfr.inc&cat=<id>&page=1&subcat=&owntopic=<n>` (`:84-89, 116-120`); else all four URLs equal the forum URL (`:121-126`). Hence **flag tabs only work for top-level forums known in the id table**; sub-forums (no id) and unknown categories silently show the unfiltered list.
- `flagIndex` mapping (`:128-141`) and Swift enum `TopicListFlag` (`Common.swift:1510-1515`): 0 all, 1 favorites (owntopic 3), 2 tracked (owntopic 1, blue flag1.gif), 3 read (owntopic 2, red flag0.gif). Naming of 2/3 is a guess (unverified).
- A caller-supplied `pageURL` replaces `currentUrl` (`:143-146`), usually a `next/prev/first/last` URL from the previous result.

#### 3.3.2 Status detection (`:67-81`, `:254-261`)
- `body` has no `id` attribute → error page: if `body.firstChild` is `<p>` → `kMaintenance` with its text; else → `kNoAuth` with the text of `.hop` (exact class `hop`). Returned in `statusInfo`; the list is empty. Consumed by legacy `BaseTopicsViewController.m:376`; **ignored by the HFRswift worker** (`ObjCForumTopicsLoaderWorker.m:163-175` passes only topics): a login wall or maintenance page looks like an empty list. A typed error is a clear improvement.
- Zero rows (`class` containing `sujet ligne_booleen` finds nothing) → `kNoResults`, message "Aucun message" (`:254-261`); navigation fields are parsed before this check, so they stay valid.

#### 3.3.3 Header / navigation fields (before the rows)
| Field | Rule |
|---|---|
| unread MP | `findChildOfClass:@"none"` (exact class `none`) → its `td` descendants; exactly 3 `td` → text of td[1] → same digit regex as 3.1 (`:84-92`) |
| `pageNumber` | `currentURL` regex `.*page=([^&]+).*` capture 1 (greedy: last `page=`), else last run of digits in the URL (`rangeOfCharactersFromSet:NSBackwardsSearch`, `RangeOfCharacters.m:21-72`), 0 → 1 (`:94-114`). Crashes if the URL contains no digit (`NSNotFound` range). Parsed from the **requested URL, not the page HTML**. |
| `currentCat` | `div.cadreonglet` (exact class) → `#onglet9`@href → regex `.*&cat=([^&]+).*` (`:116-131`) |
| `forumNewTopicUrl` | `#md_btn_new_topic`@href (`:134-135`) |
| tabs | within the first `.cadreonglet`: `#onglet1`@href → `forumBaseURL`; `#onglet2` → `forumFavorisURL`; `#onglet3` → `forumFlag1URL`; `#onglet4` → `forumFlag0URL` (`:139-168`). Overwrites the worker-derived URLs through `applyTopicListParsingResult:` (`ObjCTopicListLoaderWorkerBase.m:56-74`) — which means that when present, the page-provided tab URLs win over the derived ones, and when absent the property becomes nil. |
| pagination links | node with class containing `fondForum1PagesHaut` → child `.left` (exact) → `children` array: element **[2]** = first page entry (`contents` → `firstPageNumber`; `<span class=...cryptlink...>` → URL decoded from class, else `a@href`), **last element** = last page entry (same logic) (`:172-223`). If `pageNumber == first/last` the current URL is used. Raises when fewer than 3 children. |
| next / previous | `.pagepresuiv` (partial) nodes inside the same container; requires exactly 2; [0] → next, [1] → previous; each: descendant with class containing `md_cryptlink`, URL = `className` decoded by `decodeSpanUrlFromString2`; missing → "" (`:225-251`) |
| crypt link decoding | the class attribute is `md_cryptlink` (12 chars) + hex-ish payload; decoder drops the first 12 chars and reads pairs over the alphabet `"0A12B34C56D78E9F"` (index = nibble) building a byte per pair (`RangeOfCharacters.m:116-138`). A near-duplicate `decodeSpanUrlFromString` drops 20 chars (`:92-114`) and is used elsewhere (messages lot). HFR obfuscates navigation links to hinder scraping. |

#### 3.3.4 Rows
Rows = all nodes whose `class` contains `sujet ligne_booleen` (partial) (`:254`). Per row, cells identified by class:

| Cell (class, exact unless noted) | Field(s) |
|---|---|
| row class contains `ligne_sticky` | `isSticky` (`:281-284`) |
| `sujetCase1` (partial) → first `img` | `alt == "On"` ⇒ topic has unread replies ⇒ `isViewed = NO`; anything else ⇒ viewed (`:374-388`) |
| `sujetCase3` | title cell. `allContents` trimmed ⇒ title (`:320-321`); first `a`@href ⇒ `aURL` (`:323`); `img[alt=closed]` ⇒ `isClosed` (`:285`); second `a` ⇒ `sLastSearchPostURL`; descendant `.cCatTopic` (exact) ⇒ clean title **when** a `.s1` descendant exists (search results), whose text is `sLastSearchPostContent` (`:297-321`) |
| descendant `img[src="https://forum-images.hardware.fr/themes_static/images/defaut/sondage.gif"]` (exact) anywhere in the row | `isPoll` (`:331-334`) |
| `sujetCase4` → `a` | `aURLOfLastPage` = href; `maxTopicPage` = link text int; no link ⇒ page count 1 and last page URL = `aURL` (`:453-464`) |
| `sujetCase5` → `a` | flag link: `aURLOfFlag` = href; `img.src` contains `flag0.gif` ⇒ "red", `flag1.gif` ⇒ "blue", `favoris.gif` ⇒ "yellow"; `curTopicPage` = `HFRTopicPageNumberFromURLString(flagURL)` (query item `page`, then regex `(?:\?\|&)page=(\d+)`, then `_(\d+)\.htm`, `:9-38`). No link ⇒ flag fields "" and `curTopicPage` 0 (`:337-372`) |
| `sujetCase6` (partial) | first `a` text, else first `span` text, else "" ⇒ `aAuthorOrInter` (`:391-403`) |
| `sujetCase7` | replies count `contents` → int (`:328-329`) |
| `sujetCase9` (partial) → **firstChild** (an `a`) | href ⇒ `aURLOfLastPost`; its first `<b>` text ⇒ last author; its own text ⇒ date string `dd-MM-yyyy à HH:mm` (`:405-450`) |

Not extracted by the list parser: `postID`, `catID`, `aURLOfFirstPage`.

#### 3.3.5 Date handling (`:421-450`, duplicated at `Favorite.m:119-149`)
Parse `dd-MM-yyyy à HH:mm` in `Europe/Paris` (the favorites copy also sets locale `fr_FR`). Then a display label is built **in the parser**: future date ⇒ time only (`substringFromIndex:13`); < 1 min ⇒ "il y a 1 min"; < 60 min ⇒ "il y a N min"; < 24 h ⇒ "il y a N h"; else `dd/MM/yy` by substring offsets. If the date string does not parse, `dDateOfLastPost` is nil and `timeIntervalSinceDate:nil` is undefined (unverified behaviour). For the port: parse to `Date` only, move labels to the UI layer (SwiftUI `Text(date, style: .relative)` or a `FormatStyle`).

#### 3.3.6 MP list specifics
Same page template as a forum list with `cat=prive` (`ObjCMPTopicsLoaderWorker.m:9-10`); no pagination handling (page=1 only, nav fields reset to nil/1, `:11-16`). Unread MP: HFR prefixes the title with `[non lu]`; Swift uses `title.lowercased().hasPrefix("[non lu]")` OR `!isViewed` (`MPListView.swift:12-22`). Several interlocutors: `aAuthorOrInter` contains "multiples" (`MPListView.swift:172`) — which comes from the `span` branch (`:397-400`). Poll/sticky/closed icons presumably do not occur. Unverified: exact MP row markup.

#### 3.3.7 Global search results
Not a distinct page parser: `ObjCForumSearchWorker` (1) POSTs `search.php?config=hardwarefr.inc` with an urlencoded body (keys in fixed order: `hash_check, cat, search, resSearch=200, orderSearch=0, titre, searchtype, pseud, daterange[, jour, mois, annee]`, `:148-199`) using a cookie-less ephemeral session (`:125-134`); (2) extracts the redirect from `<meta http-equiv=refresh content="N;url=...">` with a case-insensitive regex and replaces `&amp;` by `&` (`:304-320`); (3) POSTs **the same body** to that URL (`:223`) and (4) feeds the HTML to `ObjCTopicListParser` (`:249`), so result rows are the same `sujet ligne_booleen` rows with `.s1` snippet (3.3.4). The regex and the "no meta ⇒ error -2" rule are pure parsing and belong to HFRParsing; the form encoding and session handling belong to HFRNetwork. Result paging is the normal pagination block. Content filter: search terms containing jailbreak/cydia/pengu/apple jb are replaced by a base64 string that decodes to the sentence "I Don't Want to Live on This Planet Anymore" (`:149-156`). This is an App Review workaround, strange for a client; do not port blindly (open question 7).

### 3.4 Favorites / flags page (`forum1f.php`)

Request: `GET <ForumURL>/forum1f.php?owntopic=<1|3>` where 3 if UserDefaults `vos_sujets == 1` else 1 (`ObjCFavoritesLoaderWorker.m:45-48`). Parse (`:79-168`):

1. `body` without `id` ⇒ throws `FavoritesLoadError` with the `<p>` text or the `.hop` text (default "Authentification requise") (`:87-95`), caught and turned into an `NSError` code 2 (`:67-71`).
2. MP counter (same `none`/3-td/regex rule) ⇒ badge (`:97-103`); `hash_check` value stored in the app delegate (`:105-106`, no emptiness check).
3. Table: `class="main"` (exact) → all `tr` descendants (`:108-109`), iterated in order:
   - class contains `fondForum1fCat` ⇒ new category: `Favorite.parseNode:` — `a.cHeader` (exact): `href` ⇒ forum URL, `wordAfterString:@"cat="` ⇒ `aID`, `contents` ⇒ title (`Favorite.m:31-47`);
   - class contains `ligne_booleen` ⇒ topic row ⇒ `addTopicWithNode:` appended to the current category (`:148-150`; crashes with nil `currentFavorite` if a topic row precedes any category row).
4. Topic row (`Favorite.m:49-210`): `catID` ← `input[name~valuecat]@value`, `postID` ← `input[name~topic]@value` (partial name match: `topic` also matches names such as `topic1`, `topic0`; the first one in document order wins, unverified); poll flag via image `https://forum-images.hardware.fr/themes_static/images_forum/1/sondage.gif` (**differs from list parser**); sticky/closed as in 3.3.4; title = `allContents` of `sujetCase3` trimmed; `aURLOfFirstPage` = first `a` in `sujetCase3`; replies `sujetCase7`; last post cell `sujetCase9` first child: author `<b>` (**non-optional**: `initWithString:nil` raises if absent, `:112`), href, date/relative label; `sujetCase4 a` ⇒ last page URL and page count (else page count 1); `sujetCase5 a` flag: `aURL` = flag href (resume position) else `aURL` = last post href and `isViewed = YES` (`:163-178`); `curTopicPage` from `aURL` with the same regex fallbacks as 3.3.3 (crash if no digit). No flag-colour parsing, no `sujetCase1` read state, no `sujetCase6` author.
5. Ordering / hidden categories (UserDefaults, storage boundary): if both order arrays are empty the first-seen order is saved (`:112, 128-131`); otherwise a known category keeps its index (and is removed from the hidden list), an unknown one is appended to visible (`:132-146`); categories whose id is not in the visible list are placed in `hiddenCategories`, which is **never returned**. Only visible categories are returned, sorted by `order` (`:161-167`). `arrayTopics` (all topics sorted by `dDateOfLastPost` desc, `:164-165`) is computed but not returned; the Swift side re-implements that sort in `FavoritesTopicListOrdering.flattenedTopics` (`Favorites.swift:157-166`). In HFRswift, no Swift code writes the hidden list (`grep arrayCategoriesHiddenOrder` finds only legacy `FavoritesTableViewController.m`), so the hidden branch is dead for the new app unless legacy preferences are migrated.
6. Empty page ⇒ `[]`.

Swift side of the favorites model: `FavoritesViewModel` keeps `[Favorite]` (`Favorites.swift:209-291`); `unreadCount = max - cur` (`:982-986`); label `⚑ cur / max` (`:988-997`).

### 3.5 Swift-side parsing in my files
- `Favorites.swift`: none. Local state only (`SuperFavoritesIds` UserDefaults, collapsed section ids `CollapsedFavoriteSectionIDs`, `:112-155`). The only network code is the "remove favorite flag" POST to `modo/manageaction.php` (`:43-94`, `action_reaction=message_forum_delflags`, fields `topic0=<postID>`, `valuecat0=<catID>`, `valueforum0=hardwarefr`, `hash_check`): network lot.
- `FavoritePostFilterService.swift`: bridge only; the "message actions" dictionary decode (`:100-123, 241-302`) belongs to the messages lot.
- `Common.swift:1398-1612`: bridges described above; `pageInfo(from:)` reads KVC keys `currentUrl,nextPageUrl,previousPageUrl,firstPageUrl,lastPageUrl,pageNumber,firstPageNumber,lastPageNumber`; `absoluteForumURL(from:)` resolves `forumNewTopicUrl` against `k.forumURL()` (`:1596-1607`).
- `MPBackgroundService.swift:115-139`: a second implementation of the MP counter regex (`class=["']cCatTopic red["'][^>]*>(.*?)<` then first integer) on the home page — a third variant of the same rule (`cCatTopic red` here vs `cat=prive` in 3.1). All three should converge on one `PrivateMessageBadgeParser`.
- `MPListView.swift:185-205`: topic id from `post=` in a URL (URLComponents, then regex fallback) — candidate for a shared `HFRURL.topicID(from:)` helper.

### 3.6 Poll (`PollData.swift`)
Input: raw outer HTML of `<div class="sondage">` extracted by `ObjCTopicPageWorker.m:160-162` (message-page lot). Rules, all `NSRegularExpression` with `dotMatchesLineSeparators`, i.e. HTML-by-regex:
- Question: `<(b|div) ... class="s2" ...>(.*?)(</b>|</div>)`, tags stripped, `&nbsp;`→space (`:148-160, 372-384`).
- Footer: `<div class="sondageFooter...">`, `<br>`→newline (`:164-181`).
- Max choices: text between `</b>` and `<ol type="1"` containing ` N ` (e.g. "Vous pouvez sélectionner 2 réponses") ⇒ N, else 1 (`:185-206`).
- Mode: any `<input` ⇒ voting mode; options regex `<li>..<input name="X">..<label>text</label>..</li>` ⇒ `fieldName`, text; id = index+1 (`:210-227`). Hidden fields: every `<input type="hidden" name value>` ⇒ `hiddenFields` (`:231-249`). Otherwise results mode (below). If voting mode has no options it falls through to results (`:115-141`).
- Results: `sondageLeft` blocks (nesting-aware `<div>` counter, `:272-327`) each holding two `sondageTop` divs: percentage (first decimal number, e.g. "16.7&nbsp;%") and vote count ("&nbsp;5 votes"); labels from `div.sondageRight`; paired by index, truncated to the shorter list (`:253-269, 343-355`). Decimal comma not handled (`\d+(\.\d+)?`, `:330`): a French locale rendering "16,7" would give 16.
- Vote POST: `https://forum.hardware.fr/user/vote.php?config=hfr.inc`, params = hidden fields + (`field=index` when maxChoices == 1, else `field=1`); response success unless `<div class="hop">` containing `<a` or `<input` (`:45-99`). Network lot, parse of the answer is trivial.
- The `swiftPollIsNewVote` flag is `poll.findChildTag("input") != nil` (`ObjCTopicPageWorker.m:161`).

### 3.7 Bookmarks
No HTML. See 2.1. Boundary with storage lot (JSON in MP storage topic).

### 3.8 Not found / not applicable
- "sub-categories" page, "drapeaux" page other than 3.4: `kFlag`/`kRed` list URLs (3.3.1) reuse the topic list parser; there is no separate "drapeaux" parser.
- `ObjCTopicSearchWorker`: no HTML parsing (reads `Location` header of `transsearch.php`, `ObjCTopicSearchWorker.m:9-66`), the search form inputs are scraped by `ObjCTopicPageWorker.searchInputDataFromBody:` (`:163-175`, messages lot).

### 3.9 `FilterPostsQuotes.m`
Does not parse lists. `fetchFilteredPostsForTopic:startPage:progress:completion:` (`:202-312`) loops `topic.curTopicPage ... topic.maxTopicPage`, downloading each page through `[topic getURLforPage:n]` with cookies disabled (`:261-265`), parsing it with `ParseMessagesOperation parseData:... filterPostsQuotes:YES startAfterThisPostId:` (messages lot), stops after 40 posts (`arrData.count >= 40`) or at the last page, and returns `(items, startPage, endPage, finished)`. It depends on the list models only for `Topic.curTopicPage`, `maxTopicPage`, `aURL` (`#t<postid>` anchor ⇒ start after that post, about `:238-245`; line numbers in this section are approximate, derived from a relative listing) and `getURLforPage:`. The legacy-only UIKit part is under `#if !APP_SWIFT`. Cancellation: `cancelSwiftFiltering` (`:314`). Redesign target: HFRNetwork (page loop) + HFRParsing (message filter) + HFRModels (`PostFilter`). Out of this area; noted for the dependency graph only.

## 4. Quirks, workarounds, dead code and visible bugs

Bugs and crash risks (legacy; each one needs a decision "reproduce / fix / typed error"):
1. `ObjCForumsParser.m:61` `objectAtIndex:1` on a possibly short `td` array; `:67`, `:108`, `ObjCTopicListParser.m:323,342,345,417`, `Favorite.m:101,112,115` use `[[NSString alloc] initWithString:nil]`/non-nil assumptions and raise on missing nodes. One malformed row kills the whole parse (no `@try` in the forum/topic list path; favorites has one at `ObjCFavoritesLoaderWorker.m:63-72`).
2. `ObjCTopicListParser.m:181,189,195` `children[2]` and `.lastObject` positional access; crashes with fewer than 3 children and depends on whitespace nodes.
3. `ObjCTopicListParser.m:102-103` and `Favorite.m:191-192`: `rangeOfCharactersFromSet` returns `NSNotFound` when the URL has no digit, then `substringWithRange` raises.
4. `Topic.m:73-84` `getURLforPage:` crashes (invalid range) if `aURL` has no `page=`; the regex `.*page=([^&]+).*` captures greedily up to the next `&` or end, including a trailing `#anchor` that is then stripped by `stringByRemovingAnchor` (`RangeOfCharacters.m:253-274`, which cuts at the last `#`, `matchedRange.location - 1`).
5. `wordAfterString:` (`RangeOfCharacters.m:276-304`) only works when the `&` closing the value lies within 4 characters after `cat=` (search window = `len("cat=")+4`), so category ids of 4+ digits or a `cat=` at the end of the URL raise. Current ids are ≤ 2 digits.
6. `Favorite.m:26` `[[NSNumber alloc] init]`; `Topic.m:59` `[NSDate alloc]` without init.
7. `Topic.m:102` `NSLog(@"encodeWithCoder", self)` format mismatch.
8. Logging noise: `[TopicPageTrace]` logs with titles and URLs at every row (`ObjCTopicListParser.m:104,108,113,360`), `NSLog` of page numbers (`:182-189`), `login = %d` printed before it is assigned (`ObjCForumsParser.m:39,46`).
9. Poll image URL inconsistent between list parser (`.../themes_static/images/defaut/sondage.gif`, `ObjCTopicListParser.m:331`) and favorites (`.../themes_static/images_forum/1/sondage.gif`, `Favorite.m:70`; the comment above the line shows the other URL). At least one is probably stale (unverified): poll icons may be missing in one of the lists.
10. `ObjCTopicListParser.m:146-168` the `if (!result.forumFavorisURL)` guards are always true (fresh object); empty `else {}` branches.
11. `applyTopicListParsingResult:` replaces worker-derived tab URLs with the parsed ones even when they are nil (`ObjCTopicListLoaderWorkerBase.m:62-65`), so a page without `.cadreonglet` loses the flag URLs.
12. `ObjCForumTopicsLoaderWorker.m:158-176`: `statusInfo` dropped; MP list hides auth errors.
13. Home page and favorites parsers perform side effects (NSNotification, `HFRplusAppDelegate.hash_check`, tab badge, `NSUserDefaults nb_mp`, order arrays) inside the parse; unacceptable in a pure `HFRParsing` function.
14. Encoding: forced `UTF-8` and bytes-as-C-string (`HTMLParser.m:76-79`); only the home page goes through the iconv sanitiser. If HFR ever sends ISO-8859-1 (historic behaviour, unverified), the other pages would be garbled/empty. Capture the real `Content-Type` and `<meta charset>` in fixtures.

Dead code / vestiges:
- `Catcounter` (legacy-only, unused).
- `aTopicAffix`/`aTopicSuffix` machinery forced to "" (`ObjCTopicListParser.m:277-294`, `Favorite.m:77-95` including an iOS < 7 check), emoji prefixes removed.
- `ObjCTopicListParser.m:297-300`: `HTMLNode* NodetemporaryNumPagesArray[1];` is a no-op declaration.
- `ObjCTopicListParser.m:263-267`: `nowTopic`/`dateFormat` partially unused (`dateFormat` never used), `countViewed` computed but unused (`:267, 386`).
- `Favorite.m:51-54` computes `theDate` unused.
- `Forum.m` duplicates the URL→id table twice (`getHFRID`, `getImage`); `URLforType:` unused from HFRswift.
- `ObjCFavoritesLoaderWorker.m`: `arrayTopics`, `arrayNewData`, hidden categories computed and not returned (`:164-165`, `hiddenCategories`).
- `ObjCFavoritesLoaderWorker.m:112` / `Favorite.order` ordering logic only meaningful with legacy hidden-category UI.
- `FilterPostsQuotes.m` UIKit branches under `#if !APP_SWIFT`.
- `Favorites.swift` `TopicModel` (`:199-206`) appears unused (not grepped across all files, unverified).

Workarounds with business meaning to preserve or consciously drop:
- Sub-forum injection table (3.1), AchatsVentes/Hardware URL rewrite, Apple hidden when logged out, "TU" title normalisation (`filterTU`), jailbreak search substitution, `ia` forum id 32 with absolute URL, `[non lu]` MP prefix, hash_check harvesting.

Swift/ObjC bridging fragilities (relevant because the new code must not copy them): `NSClassFromString` + `unsafeBitCast(IMP)` calls (`Common.swift:855-873, 1408-1612`), KVC string keys, `Int32` fields, `NSMutableArray` casts, models as reference types mutated by the UI (`Favorites.swift:280-289`, `removeTopic` mutates `favorite.topics` in place).

## 5. Proposed lots (HFRModels and HFRParsing)

IDs are provisional (to be assigned in `docs/LOTS.md`). Difficulty scale: trivial / easy / medium / difficult. Fixture names refer to section 6. "Legacy sources" fill the lot spec template.

| Lot | Module | Scope | Difficulty | Depends on | Fixtures |
|---|---|---|---|---|---|
| **B1 list-models** | HFRModels | Types of 2.2: `ForumCategory/ForumLink`, `TopicSummary`, `TopicFlag`, `TopicListFilter`, `TopicID`, `LastPost`, `SearchHit`, `PageNavigation`, `TopicListTabs`, `TopicListPage`, `ForumListPage`, `FavoriteSection`, `Bookmark`, `ListPageFailure`; move `PollOption/PollResult/PollData` here. All `Sendable`; `Hashable`/`Codable` as declared per type in §2.2 (exceptions: `TopicFlag` is `String, Sendable, Codable`; `TopicListFilter` is `Int, Sendable`; `ListPageFailure` is `Error, Sendable, Equatable`); Linux-buildable; unit tests on equality/Codable round trip. Decide URL representation. | easy | none (blocks everything else) | none |
| **B2 forum-catalog** | HFRModels | Static knowledge: `ForumCategory.id` from path (22-row table, `Forum.m:34-58`), `ia` absolute-URL alias, builder `topicListPath(categoryID:filter:page:)` mirroring `kCatTemplateURL` (`Constants.h:65`). Icons stay in the app. (URL building could instead live in HFRNetwork endpoints; decide with the network auditor.) | trivial | B1 | none (table check against the home page fixture) |
| **B3 parsing-core** | HFRParsing | Shared kit on SwiftSoup behind the HTML backend protocol: selector helpers that reproduce exact vs substring class matching; `HFRDate` parser (`dd-MM-yyyy à HH:mm`, Europe/Paris, via `Date(_:strategy:)`/`ParseStrategy`, not `DateFormatter`); URL helpers (`page=`, `cat=`, `post=` extraction, `#t` anchor removal, replace page); crypt-link decoder (`decodeSpanUrlFromString2` and the 20-char variant); "first integer" extraction (MP badge, 3 legacy variants); typed `ParsingError`. | medium | B1 | `crypt-links` samples from topic-list; unit tables from legacy examples |
| **B4 forum-list-parser** | HFRParsing | `ForumListParser.parse(html:) -> Result<ForumListPage, ListPageFailure>`: 3.1 minus side effects (maintenance → error, login flag, `hash_check` returned as data, MP count returned), Apple hiding, `AchatsVentes/Hardware` rewrite, sub-forum parent copy, injection table as data with dedupe, `cat=prive` exclusion. | medium | B1, B3 (B2 optional for id) | `home-loggedout`, `home-loggedin-mp`, `home-maintenance` |
| **B5 topic-list-parser** | HFRParsing | `TopicListParser.parse(html:requestedURL:) -> TopicListPage`: 3.3.2-3.3.5 (status detection with typed errors, tabs, pagination incl. crypt links, `fondForum1PagesHaut/.left` indexing replaced by explicit link classification, rows, flags, sticky/closed/poll, search snippet columns, unread state, last post, page counts). Key risk: positional child access and whitespace nodes; fixtures decide the real structure. Unified poll icon rule. No relative-date labels. | difficult | B1, B3 | `topiclist-*` (all), `search-results`, `error-*` |
| **B6 mp-list-parser** | HFRParsing | Thin configuration on B5 for `cat=prive`: unread (`[non lu]` prefix + `sujetCase1`), multi-interlocutor flag, MP unread count (home page and list header) as one `PrivateMessageBadgeParser` replacing the 3 legacy variants (`ObjCForumsParser.m:516-525`, `ObjCTopicListParser.m:84-92`, `MPBackgroundService.swift:115-139`). | easy | B5 | `mplist-*`, `home-loggedin-mp` |
| **B7 favorites-parser** | HFRParsing | `FavoritesParser.parse(html:) -> Result<[FavoriteSection], ListPageFailure>`: 3.4 (category rows `fondForum1fCat`/`cHeader`, topic rows, `postID/catID` from hidden inputs, flag URL as resume position, `curTopicPage`), typed auth/maintenance errors. Section ordering/hidden categories are NOT parsed: leave to HFRStorage + app. Reuse the row parser of B5 where the markup is identical (confirm with fixtures; if the two row shapes diverge keep two row parsers). | medium | B1, B3, B5 (row reuse) | `favorites-*` |
| **B8 search-redirect-parser** | HFRParsing | `SearchRedirect.parse(html:) -> Result<String, ListPageFailure>` (meta refresh, `&amp;`) with the "no result page" error; the results page itself is B5. Form body building goes to HFRNetwork (note `FormEncoding` rules at `ObjCForumSearchWorker.m:179-199`). | trivial | B1 | `search-redirect`, `search-no-redirect` |
| **B9 poll-parser** | HFRParsing | Port `PollHTMLParser` (`PollData.swift:104-368`) from regex to SwiftSoup on the `div.sondage` fragment or the full message page; handle decimal comma; keep voting-vs-results mode; vote answer parser (`.hop`). Vote POST goes to HFRClient (LOT-054, ADR 0008). Coordinate with the messages auditor who owns the extraction of the poll div. | medium | B1 | `poll-vote`, `poll-vote-multi`, `poll-results`, `poll-vote-response-ok/error` |
| **B10 legacy-oracle-harness** | tooling (Phase 2) | Not a module lot: capture harness that runs `ObjCForumsParser`, `ObjCTopicListParser` and `ObjCFavoritesLoaderWorker.parseFavoritesFromData:` on the saved HTML and dumps JSON oracle files (shape = B1 types, with the legacy quirks listed in section 4 documented per fixture). | medium | the fixtures | all |

Suggested order: B1 → (B2, B3) → B4, B8 in parallel → B5 → B6, B7 → B9. B5 is the critical path and should be assigned to the strongest model with an explicit review round.

Decisions per lot to record under "Intentional differences from legacy": no side effects; typed errors instead of `statusInfo`/exceptions; no display strings (relative dates, "TU" rewrite, `[non lu]` stripping stay in the UI/view-model layer, with unit tests there); no `Forum.aID`-less sub-forums; unified poll icon; page number taken from the HTML when possible, falling back to the URL.

## 6. Fixtures to capture

To be captured on the maintainer's Mac with a harness in the legacy app (docs/FIXTURES.md), anonymised. Filenames are suggestions (`<lot>/<case>.html` + `.oracle.json`).

Home page (`ObjCForumsParser`):
1. `home-loggedout` (Apple absent, `hash_check` empty or absent).
2. `home-loggedin-mp` (Apple present, `hash_check` set → REDACTED, `cat=prive` row with unread count 0 and ≥ 1; check the sentence around the number).
3. `home-maintenance` (`<body><p>…`), and `error-noauth` (body without id and `.hop`).
4. A page including every sub-category in 3.1's table triggers, to verify the injections against the live list.

Topic list (`ObjCTopicListParser`), for one big forum (e.g. cat 13 Discussions) and one small:
5. `topiclist-all-page1`, `-page-middle`, `-page-last` (pagination block with `fondForum1PagesHaut`, `.left`, `pagepresuiv`, crypt links, page numbers > 9 to see how long ranges are rendered).
6. `topiclist-all-single-page` (no `.left` pager) and `topiclist-empty` (filter with no topic: "Aucun message").
7. Logged-in `owntopic=1`, `owntopic=2`, `owntopic=3` lists (blue flag, red flag, yellow `favoris.gif`, flag URLs with `page=`).
8. Rows covering: sticky (`ligne_sticky`), closed (`alt="closed"`), poll (`sondage.gif`, record the real URL), topic with exactly 1 page vs many pages, replies count ≥ 1000 (separators?), unread (`alt="On"`) vs read, last post from today / yesterday / old, a title with HTML entities and `&nbsp;`, a title containing "topic unique", a pseudo with special characters, a deleted/anonymous last author.
9. A sub-forum list (`/hfr/Programmation/PHP/liste_sujet-1.htm`) to verify tabs (`#onglet1..4`) for sub-forums.
10. Moved/redirect topics ("Topic déplacé" style rows): unknown, capture if the live forum shows any (legacy has no special handling).

MP list: 11. `mplist-unread-and-read` (one `[non lu]`, one multi-interlocutor row), `mplist-empty`.

Favorites (`forum1f.php`): 12. `favorites-flags-owntopic1`, `favorites-owntopic3`, `favorites-empty`, `favorites-multi-category`, with topics lacking a flag link, with a poll, sticky and closed; a page with a category id ≥ 100 if any exists.

Search: 13. `search-redirect` (meta refresh page), `search-no-redirect`, `search-results-page1` (rows with `.s1` snippet and 2 links in `sujetCase3`), `search-results-page2`, `search-no-results`.

Poll (with the messages auditor): 14. `poll-vote` (single choice), `poll-vote-multi` ("sélectionner N réponses"), `poll-results` (after voting/closed, with percentages that have a decimal part), `poll-vote-response-ok`, `poll-vote-response-error`.

Encoding checks: 15. Save the raw bytes with the response headers (`Content-Type`) for pages 1, 5 and 12, including a title with accented characters, to settle UTF-8 vs ISO-8859-1.

## 7. Open questions

1. URL representation in models: keep HFR's relative `String` paths (as in legacy, resolved with `k.forumURL()`) or resolve to `URL` in the parser? The legacy also mixes absolute and relative forms (`Forum.m:57-58`, `ObjCForumTopicsLoaderWorker.m:10-34`).
2. Is `aID` / `getHFRID` table the only way to get a category id for the home page forums? Do the home page links carry `cat=` anywhere (e.g. in `cCatTopic` hrefs, which are rewritten)? Check fixtures; if yes the 22-row table disappears.
3. Why are the sub-forums in the injection table (3.1) missing from the home page, and are they still missing today (dedupe rule needed)? Does a topic list for a sub-forum support `owntopic`/`subcat` (the template has an unused `subcat=` placeholder)?
4. Where should `hash_check` live? It is harvested from the home page and favorites page by the legacy parsers (and from the topic page form by the messages parser). Proposal: parsers return it as data (`SessionToken?`), HFRNetwork stores it.
5. Pagination structure: what exactly are `.left` children[0..n] (index 2 = first page), and is `firstPageNumber` ever != 1? Needs fixtures; the new parser should classify links by role instead of position.
6. `isViewed` semantics (`sujetCase1` `On`/`Off`/other values; MP `[non lu]`): does the favorites page expose read state at all (legacy never reads it)? What is the correct meaning of `hasNewMessageInTopic` (never written in this area)?
7. App-review hacks (jailbreak search substitution, Apple hidden when logged out): keep? They look like constraints of the old App Store submission rather than product behaviour; decision for the maintainer.
8. Which flags exist beyond `flag0.gif`, `flag1.gif`, `favoris.gif`? Naming of the two flag filters ("tracked" owntopic=1, "read" owntopic=2) is a guess.
9. `TopicSummary.id`: confirm that `cat` and `post` can always be parsed from the title link and flag link of list rows (legacy never did; Swift re-parses in `MainWindow.swift:~470-500`).
10. Is the legacy SuperHFRplus target still built? `BaseTopicsViewController.m` (in that target) calls `ObjCTopicListParser`, which is only compiled into HFRswift (pbxproj:5717 vs 5837). If the legacy target is dead, `Catcounter` and the UIKit controllers can be ignored entirely.
11. Do we want to keep supporting the `forumsCache.plist` NSKeyedArchiver format and the `SuperFavoritesIds` / `CollapsedFavoriteSectionIDs` / `arrayCategories*Order` / `vos_sujets` / `nb_mp` UserDefaults keys for migration? (Storage lot, listed here because the list parsers read/write them.)
12. Rows relying on the `none` class for the MP counter in headers (`findChildOfClass:@"none"` + exactly 3 `td`): is that header still the same on the current site, and is "cCatTopic red" (used by `MPBackgroundService.swift:115`) the same element?
