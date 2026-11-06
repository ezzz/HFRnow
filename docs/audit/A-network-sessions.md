# Audit A — Networking, sessions, accounts, search services

Legacy repo: `/home/user/HFRnow` @ `2440d79` (read-only). All paths below are relative to it unless prefixed `new:`.
Convention: `file:line` citations; "unverified" = not provable from the code alone (needs a captured fixture or a device run).
Boundaries: HTML list/message parsing, reply posting and storage are audited by other agents; they are only mentioned where they touch networking.

---

## 1. Scope

### 1.1 Target membership

Evidence: `SuperHFRplus.xcodeproj/project.pbxproj`.
- **HFRswift target** (`15B0AA842E2C27DD0092C0FD`, pbxproj:4279) compiles the Sources phase at pbxproj:5710-5756. That phase lists every ObjC file of this audit plus ASIHTTPRequest.
- **All Swift files** of `HFRswift/Swift/` are in the target through the file-system-synchronized group `Swift` (pbxproj:2671, linked at pbxproj:4290-4292). There is no `membershipExceptions` entry anywhere in the pbxproj (grep: 0 hits), so every `.swift` file in that folder is compiled.
- `APP_SWIFT=1` is defined in the HFRswift build configurations (pbxproj:6072, 6153; two more at 5967/6014 belong to other targets, unverified which). It disables UIKit-only ObjC blocks, notably the ObjC BGTask registration (`Classes/HFRplusAppDelegate.m:155-170`, `#ifndef APP_SWIFT`).

| File | Lines | In HFRswift? | Notes |
|---|---:|---|---|
| `Classes/ObjCTopicListLoaderWorkerBase.{h,m}` | 37 + 76 | yes (pbxproj:5710+ "…LoaderWorkerBase.m") | base class of the topic-list workers |
| `Classes/ObjCForumsLoaderWorker.{h,m}` | 10 + 56 | yes | home page, forum list |
| `Classes/ObjCForumTopicsLoaderWorker.{h,m}` | 15 + 195 | yes | topic list of a forum |
| `Classes/ObjCFavoritesLoaderWorker.{h,m}` | 18 + 197 | yes | `forum1f.php`; also contains **parsing** |
| `Classes/ObjCMPTopicsLoaderWorker.{h,m}` | 7 + 21 | yes | private-message list |
| `Classes/ObjCTopicSearchWorker.{h,m}` | 8 + 69 | yes | intra-topic search (`transsearch.php`) |
| `Classes/ObjCForumSearchWorker.{h,m}` | 11 + 344 | yes | global search (`search.php`) |
| `Classes/ObjCTopicPageWorker.{h,m}` | 19 + 210 | yes | topic page fetch (+ rendering glue, out of scope) |
| `Classes/MultisManager.{h,m}` | 28 + 299 | yes | multi-account keychain store + cookie switching |
| `Classes/HFRplusAppDelegate.{h,m}` | 84 + 857 | yes | only `hash_check`, `login/logout`, MP badge, `checkForNewMP` matter |
| `Classes/ASIHTTPRequest+Tools.m` → `SuperHFRplus/Helpers/ASIHTTPRequest+Tools.m` | 51 | yes (ASIHTTPRequest+Tools.m in phase) | `safeResponseData` (iconv UTF-8 sanitiser) |
| `SuperHFRplus/Vendor/ASIHTTPRequest/*` | ASIHTTPRequest.m = 5087 | yes | vendored v1.8.1-8 (2011), ARC-less |
| `HFRswift/Swift/LoginService.swift` | 173 | yes | pure Swift, URLSession |
| `HFRswift/Swift/AccountSessionService.swift` | 199 | yes | wraps MultisManager |
| `HFRswift/Swift/AccountsStore.swift` | 87 | yes | `ObservableObject` |
| `HFRswift/Swift/MPBackgroundService.swift` | 161 | yes | Swift port of ObjC `checkForNewMP` |
| `HFRswift/Swift/ForumSearchService.swift` | 305 | yes | bridge (selector call) to `ObjCForumSearchWorker` |
| `HFRswift/Swift/TopicSearchService.swift` | 172 | yes | bridge to `ObjCTopicSearchWorker` |
| `HFRswift/Swift/SmileySearchService.swift` | 140 | yes | pure Swift |
| `HFRswift/Swift/Common.swift` | 3215 | yes | networking-relevant parts only: 855-1385 (loader runtime + bridges), 1402-1700 (loader bridges), 1700-1900 (topic-page bridge) |

**Legacy-only (not compiled into HFRswift; ignore for the migration):** `Classes/FavoritesTableViewController.m` (second copy of favorites fetch+parse, hash_check at :372-374), `Classes/ForumsTableViewController.m` (:235-236), `Classes/AddMessageViewController.m` (reply; POST debug logging at :575-577), `Classes/OnlineMessagesTableViewController.m` (cookie helpers :2610-2647), `Classes/CompteViewController.m`. None appears in the HFRswift Sources phase (pbxproj:5710-5756). The ObjC workers above are the *extracted* versions of that logic.

### 1.2 Callers from HFRswift Swift code

| Legacy entry point | Swift wrapper | Used by |
|---|---|---|
| `ObjCForumsLoaderWorker fetchContentWithCompletion:` | `ObjCForumsLoader` (`Common.swift:1480-1508`) | `MainWindow.swift:21` |
| `ObjCForumTopicsLoaderWorker fetchContentForForum:flagIndex:pageURL:completion:` | `ObjCForumTopicsLoader` (`Common.swift:1535-1575`) | `MainWindow.swift:64` |
| `ObjCFavoritesLoaderWorker fetchContentWithCompletion:` | `ObjCFavoritesLoader` (`Common.swift:1408-1438`) | `Favorites.swift:219` |
| `ObjCMPTopicsLoaderWorker fetchContentWithCompletion:` | `ObjCMPTopicsLoader` (`Common.swift:1445-1476`) | `MPListView.swift:54` |
| `ObjCTopicPageWorker fetchContentForTopicURL:anchor:completion:` | `ObjCTopicPageLoader` (`Common.swift:~1745-1900`) | `MessagesView.swift:2799, 3041, 3070, 3143` |
| `ObjCForumSearchWorker performForumSearchWithParams:/fetchForumSearchPageURL:/cancelForumSearch` | `ObjCForumSearchService` (`ForumSearchService.swift:245-305`) | `ForumSearchView.swift:34` |
| `ObjCTopicSearchWorker performTopicSearchWithParams:` | `ObjCTopicSearchService` (`TopicSearchService.swift:114-161`) | `MessagesView.swift:2804`, `TopicSearchSheetView.swift:34` |
| `MultisManager` (selectors) | `ObjCLegacyAccountsManager` (`Common.swift:1058-1265`) → `ObjCAccountSessionService` | `AccountsStore`, `LegacySessionPreparation` (`Common.swift:1402-1406`), `ReplyService.swift:737, 918, 1396, 1731`, `AppSettingsView.swift:183, 235, 256` |
| `LoginService` | `ObjCAccountSessionService.addAccount` (`AccountSessionService.swift:61-75`) | `AddAccountView` via `AccountsStore` |
| `MPBackgroundService` | — | `HFRswiftApp.swift:21, 28, 33`, `MainWindow.swift:1148` (badge) |
| `HFRSmileySearchService` | — | `AnswerView.swift:1067` |

The bridge layer is **runtime reflection**: `NSClassFromString` + `NSSelectorFromString` + `unsafeBitCast(method(for:))` (`Common.swift:855-885`, `TopicSearchService.swift:141-144`, `ForumSearchService.swift:281-284`). Nothing is type-checked at compile time; selector names are strings.

### 1.3 Other Swift networking *outside* this area (mentioned, not audited)

Direct `URLSession.shared` use exists in `Favorites.swift:37-95` (`modo/manageaction.php`, delete favourite flag), `MessagesView.swift:332, 363, 2447, 3330` (AQ/aide-question POST, etc.), `PollData.swift:62-71` (poll vote), `ReplyService.swift` (3+ services, own `URLSessionConfiguration.default`, `:131, :759, :946`), `AQPlusView.swift`, `UserProfileView.swift:127-130`, `AnswerView.swift:775, 1741`. Multi-quote cookie read/write: `MessagesView.swift:1879-1920` (see §4). These must be inventoried by the reply/messages audit; they all depend on the same global cookie jar.

---

## 2. Architecture today

```
SwiftUI views / view models (HFRswift/Swift/*.swift)
   │  protocol (FavoritesLoading, ForumTopicsLoading, TopicPageLoading, ForumSearchServicing, TopicSearchServicing, …)
   ▼
Swift "ObjC*" bridge classes  ── NSClassFromString + selector + unsafeBitCast ──►  ObjC *Worker classes
                                                                                         │
                                                                                         ▼
                                              ASIHTTPRequest (callbacks, own NSOperationQueue, CFNetwork stream)
                                              + NSURLSession (ObjCForumSearchWorker only)
                                                                                         │
                                              HTTPCookieStorage.shared  ◄── global singleton, the ONLY session state
                                              HFRplusAppDelegate.hash_check ◄── global singleton string
                                              Keychain (A0SimpleKeychain) ◄── MultisManager account blob
```

Key properties:
1. **The cookie jar is global and mutable.** An "active account" is nothing more than "the keychain cookies of the MAIN account copied into `HTTPCookieStorage.shared`" (`MultisManager.m:107-123`, `200-212`). Each list fetch re-copies them first (`Common.swift:1402-1406`).
2. **The workers mix three concerns**: URL derivation, transport, and parsing (workers call `ObjCTopicListParser`, `ObjCForumsParser`, `ParseMessagesOperation`, `HTMLParser` directly: `ObjCForumTopicsLoaderWorker.m:163`, `ObjCForumsLoaderWorker.m:28`, `ObjCTopicPageWorker.m:105-117`, `ObjCFavoritesLoaderWorker.m:79-159`). Only the transport/URL part belongs to HFRNetwork.
3. **Side effects on globals during parsing**: parsers write `hash_check` and the MP badge into the app delegate (`ObjCFavoritesLoaderWorker.m:97-106`, `ObjCForumsParser.m:41-42`).
4. **ObjC `ObjCTopicListLoaderWorkerBase` is a stateful object** holding pagination (`currentUrl`, `nextPageUrl`, …) that Swift reads back through KVC (`Common.swift:1560-1575`, `controller.value(forKey: "currentUrl")`).
5. **Swift-native pieces** are `LoginService`, `SmileySearchService`, `MPBackgroundService` (URLSession async/await); everything else is ObjC.

---

## 3. HFR protocol facts

Host: `https://forum.hardware.fr` (`Classes/k.m:37-40`; `+ForumURL` returns it, `k.m:13-15`; an IPv6-era host-switching routine is commented out, `k.m:16-34`). `config=hfr.inc` is the forum "config" on all pages except global search (see below).

### 3.1 Endpoint table

| # | Purpose | Method | URL (relative to host) | Params / body | Source |
|---|---|---|---|---|---|
| E1 | Home = forums list (+ `hash_check`, MP count via header) | GET | `/` | none | `ObjCForumsLoaderWorker.m:20`; `ObjCForumsParser.m:41-42` (hash) |
| E2 | Topic list of a forum | GET | `/forum1.php?config=hfr.inc&cat={catID}&page={n}&subcat=&owntopic={0..3}` | `owntopic`: 0=all, 1=tracked ("flag1" = drapeau), 2=read (flag0), 3=favourites. Page param `page=1` forced when deriving. | built `ObjCForumTopicsLoaderWorker.m:88`; derived from the forum's own URL `:36-82`; mapping flagIndex→URL `:128-141`; Swift enum `Common.swift:1520-1526` (`all=0,favorites=1,tracked=2,read=3`) |
| E3 | Favourites (flagged topics, all forums) | GET | `/forum1f.php?owntopic={1\|3}` | `owntopic=3` if `NSUserDefaults vos_sujets == 1`, else `1` | `ObjCFavoritesLoaderWorker.m:46-48` |
| E4 | Private messages list | GET | `/forum1.php?config=hfr.inc&cat=prive&page=1` | fixed | `ObjCMPTopicsLoaderWorker.m:9` |
| E5 | Topic page | GET | `{topicURL}` as given by the list parser (`/forum2.php?config=hfr.inc&cat=..&post=..&page=..`, or rewritten `/hfr/<cat>/<sub>/<slug>_<id>_<page>.htm`) | page number extracted via `page=` or `_(\d+)\.htm` | `ObjCTopicPageWorker.m:14-43, 86`; URL shapes also `Common.swift:2253-2257` (`forum2.php` or first path component `hfr`) |
| E6 | Intra-topic search | POST | `/transsearch.php` | fields `hash_check, p, post, cat, word, spseudo, filter=1, firstnum, currentnum` (last two only if not "from first post") | `ObjCTopicSearchWorker.m:24-32`; fields `TopicSearchService.swift:45-63`; field whitelist read from the page's `<form action="/transsearch.php">` `ObjCTopicPageWorker.m:166-179` |
| E7 | Global search | POST | `/search.php?config=hardwarefr.inc` (**absolute URL hard-coded, config differs from hfr.inc**) | `hash_check, cat, search, resSearch=200, orderSearch=0, titre, searchtype, pseud="", daterange, [jour, mois, annee]` in that exact order | `ObjCForumSearchWorker.m:31, 158-181` |
| E8 | Global search, results | POST, then GET for pagination | URL in a `<meta http-equiv=refresh>` of E7's response | same body as E7; URL from regex `<meta[^>]*http-equiv=…refresh…content="\d+;\s*url=…">`, `&amp;`→`&` | `ObjCForumSearchWorker.m:211-240, 304-320`; pages: `:62-95` |
| E9 | Login | POST | `/login_validation.php?config=hfr.inc` | `pseudo, password, action=send, login=Se connecter`; `application/x-www-form-urlencoded; charset=utf-8` | `LoginService.swift:51-68` |
| E10 | Profile page (hash + avatar) | GET | `/user/editprofil.php?config=hfr.inc&page=5` (login) ; `…&page=1` (cookie refresh) | `hash_check` read from page 5; avatar `<img>` after `profilCase3` | `LoginService.swift:87-113`; `MultisManager.m:281` |
| E11 | Smiley keyword search | GET | `/message-smi-mp-aj.php?config=hfr.inc&findsmilies=+word1+word2` | query ≥3 chars; `+`,`&`,`=` stripped from allowed set | `SmileySearchService.swift:12, 17-25, 38-42` |
| E12 | MP unread count (background) | GET | `/` (home) | none; counts the first integer in the node `class="cCatTopic red"` | `MPBackgroundService.swift:80-135`; ObjC original `HFRplusAppDelegate.m:227-246` |
| E13 | Remove favourite flag (outside area, cited for the cookie/hash dependency) | POST | `/modo/manageaction.php?config=hfr.inc&cat=0&type_page=forum1f&moderation=0` | `hash_check, topic1=-1, topic_statusno1=-1, action_reaction=message_forum_delflags, type_page=forum1f, topic0, valuecat0, valueforum0=hardwarefr` | `Favorites.swift:55-85` |

Sub-facts:
- Relative-URL normalisation: list URLs are stored host-relative (leading `/`); absolute `http(s)://forum.hardware.fr/…` are stripped to path+query+fragment (`ObjCForumTopicsLoaderWorker.m:10-34`, `Common.swift:1374-1392`, `ObjCForumSearchWorker.m:332-342`). The effective URL after redirects is recovered from the ASI request and re-relativised (`ObjCTopicPageWorker.m:94, 187-191`). Rebuilding E2 from a category id when the forum URL lacks `forum1.php`: `ObjCForumTopicsLoaderWorker.m:84-89, 116-120`.
- `hash_check`: hidden `<input name="hash_check" value=…>` on pages E1/E3 (`ObjCFavoritesLoaderWorker.m:105-106`, `ObjCForumsParser.m:41`) and on the profile page E10 (regex `name="hash_check"[^>]*value="([^"]+)"`, `LoginService.swift:100`). It is the anti-CSRF token required by every POST (E6, E7, E13, reply). Per-account value is persisted as `HASH` in the keychain blob (`MultisManager.m:62-64, 214-226`); the *live* value is a single global string `HFRplusAppDelegate.hash_check` (`HFRplusAppDelegate.h:65`).
- Pagination fields (`firstPageUrl/lastPageUrl/nextPageUrl/previousPageUrl/pageNumber…`) come from `ObjCTopicListParsingResult` (parser audit); the worker only copies them (`ObjCTopicListLoaderWorkerBase.m:56-74`).
- MP count on the favourites page: node `class="none"` containing exactly 3 `<td>`; the 2nd `<td>` text `[^.0-9]+([0-9]+)[^.0-9]+` → `$1` (`ObjCFavoritesLoaderWorker.m:97-103`).
- Not logged in on E3: body lacks an `id` attribute; message is the first `<p>` or `.hop` text, fallback "Authentification requise" (`ObjCFavoritesLoaderWorker.m:87-95`).

### 3.2 Text encoding (verified vs. unverified)

Evidence is mixed; the server charset is **not proven by the code**.
- Requests are sent as **UTF-8**: ASIFormDataRequest default `NSUTF8StringEncoding` (`SuperHFRplus/Vendor/ASIHTTPRequest/ASIFormDataRequest.m:51`), Swift forms `charset=utf-8` (`LoginService.swift:61`, `Favorites.swift:74`, `ReplyService.swift:177`), global search body UTF-8 (`ObjCForumSearchWorker.m:176`).
- Responses: ASI default is ISO-Latin-1 (`ASIHTTPRequest.m:296`, `setDefaultResponseEncoding:NSISOLatin1StringEncoding`) but overridden by the `Content-Type` charset when present (`ASIHTTPRequest.m:2356-2360`). The topic worker forces UTF-8 (`ObjCTopicPageWorker.m:89`); `safeResponseData` is a UTF-8→UTF-8 `iconv` that *drops invalid sequences* (`ASIHTTPRequest+Tools.m:19-37`); `MPBackgroundService.swift:90` and `PollData.swift:71` decode UTF-8; `LoginService.decodeHTML` tries UTF-8 then Latin-1 (`LoginService.swift:136-141`); `AnswerView.swift:786`, `MessagesView.swift:3341` UTF-8 then Latin-1; `ReplyService.swift:308, 805, 1080, 1506` Latin-1; `UserProfileView.swift:127-130` Latin-1 then CP1252.
- Conclusion: the legacy treats the forum as **UTF-8 with historical Latin-1 fallbacks**. The "ISO-8859-1 / windows-1252" assumption of the brief is **not confirmed**; the new code must capture the real `Content-Type` and `<meta charset>` of each endpoint in a fixture (see Open questions). `SmileySearchService.swift:32` decodes **Latin-1 first**; since Latin-1 decoding never fails, its UTF-8 fallback is dead code and non-ASCII bytes would be mis-decoded (smiley codes are ASCII, so it works in practice).
- Form encoding in global search percent-encodes with `alphanumericCharacterSet` + `-._*` (`ObjCForumSearchWorker.m:194-199`). `alphanumericCharacterSet` includes Unicode letters, so accented characters (é, à…) are **not** percent-encoded in the body (legacy bug; sent as raw UTF-8 bytes in a body declared `application/x-www-form-urlencoded` with no charset). Whether the server accepts this is unverified.

### 3.3 Headers

- Global search sets only `Content-Type: application/x-www-form-urlencoded` (`ObjCForumSearchWorker.m:141`); no custom `User-Agent`/`Accept-Language`.
- ASI sends its default UA (`AppName/version rv:build (device; iOS …)`) built in `ASIHTTPRequest.m:4362-4400`, plus `Accept-Encoding: gzip` (`allowCompressedResponse` default YES, `ASIHTTPRequest.m:294`).
- URLSession paths use CFNetwork's default UA. No `Referer`, no `Origin`. Whether HFR checks any of these is unverified.

### 3.4 Redirects and errors

- ASI follows redirects by default (`ASIHTTPRequest.m:290`); the topic worker relies on this to learn the real URL (e.g. `post=` permalink → page) via `request.url` (`ObjCTopicPageWorker.m:94`).
- Intra-topic search **disables redirects** and treats the `Location` header as the success signal; no `Location` → "Aucun résultat" error code `-11` (`ObjCTopicSearchWorker.m:33, 39-52`). Domain `ObjCTopicSearchWorker.search`, codes -10/-11/-12.
- Global search expects HTML with a meta-refresh; missing → error `-2` "Aucune page de résultats" (`ObjCForumSearchWorker.m:46-54`); invalid URL → `-3`.
- **No HTTP status handling anywhere in the workers**: success = "transport did not fail". 4xx/5xx pages are fed straight to the parsers. Only `SmileySearchService.swift:26-29` and `Favorites.swift:80-82` check `statusCode`.
- Application-level errors are detected by *content*: login success = body contains `login_redirection.php` (`LoginService.swift:72`); favourites not authenticated = body has no `id` (see above); topic search = presence of `Location`.

### 3.5 Timeouts, rate limits

`kTimeoutMini=30`, `kTimeoutMaxi=60`, `kTimeoutAvatar=10` (`Classes/Constants.h:70-72`). List workers call the **class-level** `[ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMini]` before every request (`ObjCTopicListLoaderWorkerBase.m:37`, `ObjCForumsLoaderWorker.m:19`, `ObjCFavoritesLoaderWorker.m:50`), which mutates a process-wide static (`ASIHTTPRequest.m:53, 4101`; ASI's own initial default is 10 s). Topic page worker sets none (inherits whatever the last list call set). Topic search 60 s (`ObjCTopicSearchWorker.m:34`). Global search 15 s request+resource (`ObjCForumSearchWorker.m:8, 131-132, 140`). Background MP check 5 s (`HFRplusAppDelegate.m:228`, `MPBackgroundService.swift:86`). URLSession.shared paths: system default (60 s request). No rate limiting, retry, or backoff exists in the audited files (grep for 429/retry: none). ASI shared queue is max 4 concurrent operations (`ASIHTTPRequest.m:275`).

---

## 4. Sessions, cookies & accounts

### 4.1 Cookies

- Cookie store: `HTTPCookieStorage.shared` / `NSHTTPCookieStorage sharedHTTPCookieStorage` for everything except global search (cookies disabled, see below) and the ReplyService sessions (custom config but `cookieStorage: .shared`, `ReplyService.swift:120-135`).
- Cookie names the code relies on:
  - `md_user` — holds the user's **pseudo key**; the account identity. "Logged in" means a non-`deleted` `md_user` exists (`LoginService.swift:118`, `MultisManager.m:55, 231, 248, 261`, `AccountSessionService.swift:303`). Value `deleted` is the server's logged-out marker.
  - `quotes{a}-{b}-{c}` — multi-quote selection, domain `.hardware.fr`, path `/`, 1 h lifetime, written client-side (`MessagesView.swift:1889-1908`) — already documented in `new:docs/HFR-PROTOCOL.md`. Because account switching wipes the jar, `makeReplySessionContext` saves cookies whose name `hasPrefix("quotes")` and restores them afterwards (`AccountSessionService.swift:108-110, 83-85`).
  - Other server cookies (session/auth password hash, etc.) are stored opaquely; their names are **not referenced** in the code. Unverified: names, lifetimes, `Secure`/`HttpOnly` flags.
- Login cookie capture: after E9 the response headers are parsed manually with `HTTPCookie.cookies(withResponseHeaderFields:for:)` and inserted into `HTTPCookieStorage.shared` (`LoginService.swift:76-85`) — redundant with URLSession's automatic handling (a duplicate write, harmless). All cookies whose `domain.contains("hardware.fr")` are then snapshotted as the account's cookie list (`:115-117`).
- Global search: ephemeral configuration with `HTTPCookieAcceptPolicy.never`, `HTTPCookieStorage = nil`, `HTTPShouldSetCookies=NO` on both session and request (`ObjCForumSearchWorker.m:125-139`) → **search is anonymous**; only `hash_check` goes in the body (taken from the global app-delegate value, `:159`, may be empty or belong to a previously active account). Reason unverified (comment-free); probably to avoid cookie rewrite side effects.
- Clearing: `clearCookies()` deletes **every** cookie in the shared jar (`LoginService.swift:131-134`, `MultisManager.m:155-165, 200-212`).

### 4.2 Login flow (Swift, `LoginService.login`, `LoginService.swift:48-129`)

1. Delete all shared cookies (`:49`) — **before** credentials are validated; a failed login therefore logs the current account out of the jar (keychain data intact; the jar is re-filled on the next list fetch by `LegacySessionPreparation`).
2. POST E9 with form `pseudo, password, action=send, login=Se connecter` (`:62-68`), `URLSession.shared` (default redirect following).
3. Success test: response text contains `login_redirection.php` else `LoginError.invalidCredentials` (`:72-74`). HTTP status not checked.
4. Store response cookies; GET E10 (page 5); extract `hash_check` by regex (`missingHash` error if absent, `:100-102`); extract avatar URL by regex `profilCase3[\s\S]*?<img[^>]*src="…"` and download it, errors swallowed (`try?`, `:104-113`).
5. Require a non-`deleted` `md_user` cookie, else `missingPseudoCookie` (`:118-120`).
6. Return `LoginResult{displayPseudo (as typed), pseudoKey (md_user value), cookies, avatarData, hash}`.
7. `ObjCAccountSessionService.addAccount` then: trims pseudo (`AccountSessionService.swift:62-65`), calls `MultisManager.addCompte(pseudo:cookies:avatar:hash:)` and `setPseudo(asMain:)` (`:68-75`). The password is **not stored** anywhere (not in `LoginResult`, not in the keychain blob). Silent re-login with a password is therefore impossible; session renewal relies solely on cookie lifetime/refresh.

### 4.3 Account storage (`MultisManager`)

- Single keychain item `HFR_COMPTES_KEY` (`Classes/Constants.h:115`) in `A0SimpleKeychain` (Carthage SimpleKeychain, default accessibility `AfterFirstUnlock`, non-synchronizable, no access group: `Carthage/Checkouts/SimpleKeychain/SimpleKeychain/A0SimpleKeychain.m:40-46, 229-236`; the app embeds the xcframework, pbxproj:800-801).
- Payload: `NSKeyedArchiver archivedDataWithRootObject:` of an `NSArray<NSMutableDictionary>` (`MultisManager.m:81, 100`), read with the **deprecated, non-secure** `unarchiveObjectWithData:` (`:45, 51`). Keys: `PSEUDO` (md_user value), `PSEUDO_DISPLAY` (typed pseudo), `COOKIES` (`[NSHTTPCookie]`), `HASH`, `AVATAR` (image `NSData`), `MAIN` (`NSNumber` bool) (`Constants.h:116-121`; `AccountSessionService.swift:192-199`). This blob is the **migration format** if existing users' accounts must be imported.
- Every read re-unarchives the whole blob (`comptes()` is called many times per operation; `AccountSessionService.swift:77-89, 148-163`).
- `addCompte`: first account becomes MAIN (`:70-72`); duplicates detected by `md_user`; **a duplicate is silently dropped and its fresh cookies are not saved** (`:73-82`; so re-login of an existing account does not refresh stored cookies, but the shared jar was updated by the login itself and `setCookiesForMain` reloads the *old* stored cookies of the MAIN account, `:83`).
- Switching main: `setPseudoAsMain:` flips `MAIN` flags, saves, then `setCookiesForMain` = logout (delete all cookies, `HFRplusAppDelegate logout`, notification `kLoginChangedNotification`) + install the main account's cookies + `login` + notification again (`MultisManager.m:88-123, 155-165`); `MPStorage initOrResetMP:` follows (`:104`).
- Delete: removes the entry; if none left → logout; if one left or the deleted was main → promote the first remaining (`:125-153`). Note: the avatar-only/cookie-only removal from the shared jar is not done when a non-main account is deleted (correct) but nothing wipes `MPStorage`/bookmarks of that account (storage audit).
- `Swift AccountSessionService` account `id` = `PSEUDO` or display name (`:34-44`); lookup by normalised (case/diacritic-insensitive) id in three tiers (`:148-163`).
- `AccountsStore` listens to `kLoginChangedNotification` (`AccountsStore.swift:42-48`), `currentAccount` = MAIN else previous else first (`:51-58`).
- `kLoginChangedNotification` is a string literal duplicated in Swift (`AccountsStore.swift:43`) vs `Constants.h:60`.

### 4.4 Session preparation / "multi-account switching" at request time

`LegacySessionPreparation.prepareCurrentAccountSession()` (`Common.swift:1402-1406`) calls `makeReplySessionContext(cookieStorage: .shared)` (a *reply*-posting API) before favourites, MP and topic-list fetches (`Common.swift:1421, 1457, 1548`). Effects: resolve the MAIN account (fallback to first usable, which silently re-marks it main, `AccountSessionService.swift:165-186`), delete all cookies and reinstall that account's cookies (preserving `quotes*`), then re-store the global hash. The forums-list and topic-page loaders do **not** call it. This makes account selection a *side effect of every list load* and races with concurrent requests (cookie jar wiped mid-flight).

### 4.5 Session expiry / refresh

- No explicit expiry detection beyond: favourites parser "Authentification requise" (E3), login-needed heuristic only there. E4/E1/E2 anonymous pages parse without error.
- Cookie refresh: `updateAllAccounts` at launch (`HFRplusAppDelegate.m:147`) GETs `editprofil.php?...page=1` for each stored account with `useCookiePersistence:NO` and `requestCookies` set (`MultisManager.m:280-287`); on finish stores `request.responseCookies` into the matching account (`:290-293`, `updateCookies` `:228-240`). Bugs: (a) it overwrites the stored cookie array with *only* the cookies in the response, which may drop cookies not re-sent; (b) the keychain is rewritten even when nothing matched; (c) no failure callback; (d) delegate-based, no completion → untestable. Also the first-run branch migrates cookies present in the jar into a new account (`:245-253`) and a "migrate bis" branch repairs `PSEUDO`/`PSEUDO_DISPLAY` and de-duplicates (`:254-277`; note the dedup actually only marks `okAcc`, which is never used, `:257-258, 271`).
- `deleted` value on `md_user` = server told us we were logged out; treated as no pseudo (`:55, 231, 261`).

### 4.6 Background MP check

ObjC (`HFRplusAppDelegate.m:214-270`, **compiled but not registered in HFRswift** due to `#ifndef APP_SWIFT` at :155) and Swift port (`MPBackgroundService.swift`). Identifier `com.hfrplus.refresh_mp`, `earliestBeginDate` +60 s (`:35-37`), Info.plist permits it (`HFRswift/Info.plist:5-8`, background modes fetch+processing `:211-215`). Flow: GET `/` with the *currently installed* cookies (only the main account; other accounts are never checked), regex the `cCatTopic red` node, take the first integer, compare with `UserDefaults nb_mp` (sanitised to 0 if >1000 or <0), store, and post a local notification "Vous avez un nouveau message privé" if increased (`MPBackgroundService.swift:70-108`, `scheduleNotification` `:140-160`). Deep link payload: `MessagesNotificationNavigation.*` keys.

---

## 5. Concurrency & caching

- **ASI workers**: callbacks delivered on ASI's own queue/main depending on request type; completion handlers are re-dispatched with `dispatch_async(dispatch_get_main_queue())` (`ObjCForumsLoaderWorker.m:51`, `ObjCForumTopicsLoaderWorker.m:172, 189`, `ObjCFavoritesLoaderWorker.m:151`, `ObjCTopicSearchWorker.m:18, 41, 59`, `ObjCTopicPageWorker.m:205`). **Parsing happens on the ASI callback thread** (not main) for forums/topic list/favourites. Parsers touch globals (`hash_check`, UserDefaults) from that thread.
- Stale-response protection: forums/topic-list/favourites compare `request == self.request` (`ObjCForumsLoaderWorker.m:27, 34`, `ObjCForumTopicsLoaderWorker.m:159, 179`); global search uses a monotonically increasing `forumSearchRequestID` plus session invalidation (`ObjCForumSearchWorker.m:97-123, 244, 287`). Favourites worker never nils `request` and has no staleness guard (`ObjCFavoritesLoaderWorker.m:42-60`). Topic-page worker has none (a late response from a previous request calls the new completion, `ObjCTopicPageWorker.m:92-99`, though `cancelFetchContent` is called at the start of each fetch).
- **Swift 6 strictness**: nothing here is `Sendable`; `unsafeBitCast`'d C function pointers with blocks cross threads; `ObjCForumSearchService.activeWorker` is mutated from blocks (`ForumSearchService.swift:246, 279, 286`) and `withCheckedContinuation` can be resumed from the ObjC background queue; `self` is captured strongly in the block (`ForumSearchService.swift:285-286`). `AccountsStore` is `@MainActor ObservableObject` (violates the new project's rules).
- **Global mutable state** involved in correctness: `HTTPCookieStorage.shared`, `HFRplusAppDelegate.hash_check`, `ASIHTTPRequest defaultTimeOutSeconds`, `UserDefaults` (`nb_mp`, `nb_mp_failure`, `vos_sujets`, `recherche_categorie`, `arrayCategoriesVisibleOrder`, `arrayCategoriesHiddenOrder`).
- **Caching**: no ASI `downloadCache` is set in the audited files (grep for `downloadCache`/`cachePolicy` in `Classes/ObjC*Worker.m`: 0 hits) → no HTTP cache for ASI traffic; global search forces `NSURLRequestReloadIgnoringLocalCacheData` (`ObjCForumSearchWorker.m:130`); Swift `URLSession.shared` uses the default shared `URLCache` (HFR cache headers unverified); AQ/other services pass `.reloadIgnoringLocalCacheData`. The only in-memory state kept across fetches is on the worker instance (`arrayData`, pagination fields) and `inputData`/`swiftSearchInputData` (form fields scraped from the last topic page, `ObjCTopicPageWorker.m:148-179`). No offline cache here (offline storage is another audit area: `OfflineStorage.m` appears in the sources list).
- **Cancellation**: ASI `cancel` + nil (`ObjCTopicListLoaderWorkerBase.m:22-25`); `ObjCForumSearchService.cancel()` reaches the worker only while `activeWorker` is set. The completion of a cancelled global search is called with `NSURLErrorCancelled` (`ObjCForumSearchWorker.m:106-115`), mapped to `.cancelled` (`ForumSearchService.swift:288-291`). Base-worker `cancelFetchContent` drops the completion silently (nothing is called back), so a view awaiting a cancelled load never finishes — with callbacks this is acceptable, with async/await the new API must define cancellation as `CancellationError`.

---

## 6. Security notes

1. **Credentials**: password only lives in memory during `LoginService.login`; it is not persisted (verified: no password key in `AccountKeys` or `MultisManager`). It is not logged (`print` statements in `LoginService` do not exist; `MPBackgroundService` only prints errors).
2. **Cookies** (the real credential) are persisted in the keychain as an `NSKeyedArchiver` blob with `AfterFirstUnlock` accessibility (not `ThisDeviceOnly`; so included in encrypted backups/migration; unverified whether iCloud-synced: `kSecAttrSynchronizable` is not set). They also live in the system `HTTPCookieStorage.shared` (disk, app sandbox). The unarchiver is `unarchiveObjectWithData:` (no secure-coding class allow-list).
3. **Avatar bytes** are stored in the same keychain blob (can be large; keychain is a poor place).
4. **hash_check** persisted in the keychain (`HASH`) and held in a global string.
5. **Logging of sensitive data (legacy-only files)**: `FavoritesTableViewController.m:374` logs the hash; `AddMessageViewController.m:538, 541` log hash values; `:575-577` logs cookie names/domains/value lengths (not values). In HFRswift-compiled code: `ObjCTopicPageWorker.m:121-127, 183` log URLs and `post`/`cat` (`NSLog`, including in release); `HFRplusAppDelegate.m:249` logs counters. No password/cookie value is logged in the audited HFRswift code.
6. **TLS**: ATS is the default (no `NSAppTransportSecurity` key in `HFRswift/Info.plist`: grep 0 hits), all hosts are `https://`. But ASIHTTPRequest reads the user default `adv_ssl` (setting "Certificats auto-signés", `SuperHFRplus/InAppSettings.bundle/Advanced.plist:19-24`) and, if on, sets `validatesSecureCertificate = NO` for every ASI request (`ASIHTTPRequest.m:303-305`) → an opt-in **TLS-validation bypass** affecting all list/search/favourites fetches and the cookie refresh (credentials in cookies are exposed to MITM). Whether the InAppSettings bundle is exposed in the HFRswift UI: unverified. The Swift `URLSession` paths ignore it. The new app must drop it.
7. **Anonymous global search with an unrelated hash** (§4.1) means the account's `hash_check` is sent in a request without cookies; harmless but incoherent.
8. **Third-party secret in source**: `HFRswift/Swift/HFRswiftApp.swift:17` contains a Giphy API key literal (outside this audit's scope; flagged because AGENTS.md forbids committing secrets).
9. **`login()` clears every cookie before the credential check** (`LoginService.swift:49`): a typo in the password logs the active account out of the jar.
10. **iconv sanitiser leaks** the `outbuf`/`iconv_t` on the (theoretical) error path and returns `nil` (`ASIHTTPRequest+Tools.m:29-33`).
11. **Banned-words hack** in global search: a query containing `jailbreak`, `cydia`, `pengu`, `apple jb` is silently replaced with a base64 string that decodes to a sentence about not wanting to live on this planet (`ObjCForumSearchWorker.m:149-156`). Purpose unverified (likely App-Review driven); the new app should not reproduce this obfuscation without a documented reason. It also lowercases every search query (`:149`).

---

## 7. Quirks & dead code

- `ObjCTopicListLoaderWorkerBase` declares `fetchContentStarted:` etc. as empty hooks (`.m:47-54`); `ObjCForumTopicsLoaderWorker.fetchContentComplete:` uses `[theRequest responseData]` (not sanitised), whereas the forums/topic-page workers use `safeResponseData` (inconsistent; invalid UTF-8 could break the topic-list parse) (`ObjCForumTopicsLoaderWorker.m:163`).
- Header/impl mismatch: the base class has `completion` ivar used by subclasses (declared in their `.h`); `ObjCFavoritesLoaderWorker` redeclares `arrayNewData` as `NSMutableArray<Favorite *>` in a class extension while not inheriting the base (it is an `NSObject` subclass), a name copied from the base.
- `ObjCFavoritesLoaderWorker` persists category order to UserDefaults *during parsing* and calls `synchronize` (`:157-159`); `@try/@catch` is used as control flow (`:63-72`, `@throw` at `:94`).
- `ObjCForumsLoaderWorker`'s `request` is `ASIHTTPRequest`, Favorites' is `ASIHTTPRequest` too; but the base class types its request as `ASIFormDataRequest` and creates it through `[ASIHTTPRequest requestWithURL:]` (an `ASIHTTPRequest` instance assigned to an `ASIFormDataRequest *`, `ObjCTopicListLoaderWorkerBase.m:38`): type confusion that only works because no form-specific method is called.
- `checkForNewMP`: `nb_mp_failure` is incremented at the start and restored on success (`MPBackgroundService.swift:73-74, 96`), but `scheduleAppRefresh()` is called first and **resets `nb_mp_failure` to 0 on successful scheduling** (`:40, 71`) so `oldFailureCount` is always 0: the failure counter is effectively dead. Same shape in ObjC (`HFRplusAppDelegate.m:215-219, 482`). Swift port also differs from ObjC when the red node is missing: ObjC would store 0 (`intValue` of nil), Swift stores nothing (`MPBackgroundService.swift:90-91`) → the count never returns to 0 in the background. Whether the node is absent when there are 0 MPs: unverified.
- `HFRplusAppDelegate` still contains UIKit-era code (`rootController` tab bar badge `:700-750`) executing in a SwiftUI app: `updateMPBadgeWithString:` writes `nb_mp` then accesses `rootController` (nil in HFRswift, a harmless no-op via nil messaging).
- `login`/`logout` on the app delegate only toggle `isLoggedIn/statusChanged` flags (`:766-815`); `resetApp` pops nav controllers that are nil in HFRswift.
- `MultisManager.getComtpes` (typo) is the public selector name used by reflection (`Common.swift:1092`).
- `MultisManager.updateAllAccounts` "migrate bis" never uses `okAcc`; dedupe is not implemented (`MultisManager.m:257-258, 271`).
- `MultisManager.setHashForCompte` and the other setters unarchive → mutate → re-archive without locks (read-modify-write race between concurrent calls).
- `ObjCTopicSearchWorker` creates `ASIFormDataRequest` per call and never retains the worker; the block keeps the request alive. `performTopicSearchWithParams` accepts only `NSString` values (skips others).
- `TopicSearchParams.formDictionary` (Swift) *adds* `firstnum/currentnum` only when `!fromFirstPost`; `fromLegacyDictionary` derives `fromFirstPost` from absence of the keys (`TopicSearchService.swift:58-61, 68-87`).
- `ForumSearchParams.legacyDictionary` computes `jour/mois/annee` with `String(format:)` and the device calendar/time zone (`ForumSearchService.swift:119-122`); the "five years/one year" ranges are relative dates with `daterange=1`.
- `SmileySearchService` Latin-1-first decoding (see §3.2); history persisted as JSON in `UserDefaults` key `smileySearchHistory_v1` (storage audit).
- Dead Swift: `AccountSessionError.invalidPseudo` is the only error; `LoginResult.displayPseudo` equals the typed pseudo (not necessarily the server's capitalisation).
- Legacy-only duplicates: the same favourites/forums/topic fetching exists in `FavoritesTableViewController`, `ForumsTableViewController` (not compiled in HFRswift).
- Reachability is started (`HFRplusAppDelegate.m:120-122`) but the handler only logs (`:70-76`); no offline gating in network code.

---

## 8. Proposed lots (HFRNetwork)

Naming `NET-xx` is provisional; renumber into `docs/LOTS.md` format (`LOT-0xx`). Parsing is *not* in scope; where a fetch returns HTML the lot returns raw `Data` + decoded `String` + final URL, and the HFRParsing lots consume them.

| Lot | Name | Scope (legacy) | Difficulty | Depends on | Fixtures / tests |
|---|---|---|---|---|---|
| NET-01 | Transport & request primitives | `HTTPTransport` protocol (URLSession impl + mock), `HTTPRequest/Response` (status, headers, final URL, body), form-urlencoded encoder (UTF-8, correct percent-encoding fixing `alphanumericCharacterSet` bug), decoding helper (charset from header/meta, UTF-8→Latin-1/CP1252 fallbacks, invalid-byte tolerance = `safeResponseData`), timeouts (30/60/15/5 s), typed `NetworkError` (transport, HTTP status, cancelled). Replaces ASI usage in `ObjCTopicListLoaderWorkerBase.m:27-45`, `ASIHTTPRequest+Tools.m`. | easy | — | Unit tests with mock transport; captured `Content-Type` headers per endpoint (§3.2); invalid-UTF-8 sample; redirect-final-URL test |
| NET-02 | Endpoint catalogue | Typed URL builders for E1-E12: `forum1.php` (cat/page/subcat/owntopic), owntopic derivation `forumURLBySettingOwnTopic` + `forumURLWithCatID`, `forum1f.php`, MP list, `forum2.php`/`/hfr/…htm` page number parsing, relative↔absolute URL normalisation (`ObjCForumTopicsLoaderWorker.m:10-89`, `ObjCTopicPageWorker.m:14-43`, `Common.swift:1374-1392`, `ObjCForumSearchWorker.m:322-342`); update `docs/HFR-PROTOCOL.md` | easy | NET-01 | Table-driven tests from the URL shapes captured in list fixtures (owntopic 0..3, absolute and relative hrefs, `.htm` URLs) |
| NET-03 | Cookie jar & per-account session | `Session` value type owning an **isolated** `HTTPCookieStorage`/`URLSession` per account (replaces global jar + `forceCookies`), Codable cookie snapshot (properties dict), `md_user` identity, `quotes*` cookie helpers, `deleted` handling, `hash_check` held per session | medium | NET-01 | Cookie round-trip tests (expiry, domain, secure flags), two sessions in parallel never leaking cookies |
| NET-04 | Login & profile fetch | `LoginService` port: POST `login_validation.php`, success marker `login_redirection.php`, `editprofil.php?page=5` hash + avatar; fix "clear before validate"; no status-blind success | medium | NET-01, NET-02, NET-03; hash/avatar extraction may be a tiny HFRParsing lot (profile page) | Anonymised login success page, failure page, `editprofil` page 5 and page 1; mock transport multi-step test; **no real credentials** |
| NET-05 | Account store & Keychain persistence | `AccountsStore`/`AccountSessionService`/`MultisManager` behaviour: add/dedupe by `md_user`, main account selection and fallback, delete with promotion, display name vs key, case/diacritic-insensitive lookup; Keychain-backed `AccountVault` behind a protocol (in-memory for tests), `@Observable @MainActor` facade lives in the app, not here | medium | NET-03 | In-memory vault tests replicating `ObjCAccountSessionServiceTests.swift`; no real keychain on Linux CI |
| NET-06 | Legacy keychain import (optional) | Read `HFR_COMPTES_KEY` blob (`NSKeyedUnarchiver` of `NSArray<NSMutableDictionary>` with `NSHTTPCookie` values) and convert to NET-05 records; needs Apple platforms, cannot run on Linux | difficult | NET-05; decision on Open question 1 | A synthetic archive generated on macOS by a script (never a real user blob); Apple-only test target |
| NET-07 | Session health & refresh | Replace `updateAllAccounts`/`updateCookies`: GET `editprofil.php?page=1` per account, merge (not replace) response cookies, detect `md_user=deleted`/auth-required pages (favourites `body` without `id`), expose `.expired` state; policy for when to refresh | medium | NET-03, NET-05 | Page fixtures: logged-in profile page, logged-out/"Authentification requise" favourites page; responses with `Set-Cookie` variants |
| NET-08 | List fetchers (forums, forum topics, favourites, MP) | Network side of the four workers returning `RawPage(html, finalURL, encoding)`; flag→URL selection, `vos_sujets` input as a parameter (no UserDefaults), the "prepare session" step becomes explicit session injection; cancellation = Swift task cancellation | easy | NET-01..NET-03 | One recorded HTML page per endpoint (anonymous + logged-in), asserting requested URL/cookies via mock transport. Parsing of these pages is another agent's lot |
| NET-09 | Topic page fetch | `ObjCTopicPageWorker` network part: GET, follow redirects and return the **final URL** (permalink `post=` → page), page-number extraction from final URL, forced/declared charset, anchor passthrough | easy | NET-01, NET-02 | Redirect chain fixture (permalink → page URL) in mock transport |
| NET-10 | Global search | `ObjCForumSearchWorker`: cookieless session, `search.php?config=hardwarefr.inc` POST with ordered fields returning the raw response (meta-refresh extraction belongs to HFRParsing, LOT-025; the second POST and paginated GETs are the HFRClient flow, LOT-046), request-ID/cancellation semantics, parameter model (`ForumSearchParams` as in `ForumSearchService.swift:10-127`), date-range fields; decide on `hash_check` source and banned-word hack (Open questions) | medium | NET-01, NET-02 | `search.php` response with meta-refresh (anonymised), results page 1 & 2, no-result response; assert exact body bytes against legacy `forumSearchPostDataForParams` output for a table of params (oracle) |
| NET-11 | Intra-topic search | `ObjCTopicSearchWorker`: POST `transsearch.php` **without following redirects**, `Location` header as result, empty → "no result"; `TopicSearchParams` model; needs transport support for redirect suppression | easy | NET-01 (redirect policy), NET-02 | Mock transport returning 302 + `Location`, 200 without `Location`; hidden form fields fixture from a topic page |
| NET-12 | Smiley search | `HFRSmileySearchService`: URL, ≥3 chars, `+`-joined keywords, correct charset decoding (fix Latin-1-first), image extraction is a pure function (can live in HFRParsing) | trivial | NET-01 | Response fixture of `message-smi-mp-aj.php` |
| NET-13 | MP count poll (network + extraction) | `MPBackgroundService.performBackgroundCheck` core: GET `/` with the main account's session, extract unread MP count (`cCatTopic red`), result `Int?`/`0` semantics decided explicitly; BGTask scheduling, notifications and UserDefaults stay in the app | easy | NET-03 | Home-page fixtures: with and without unread MP node (resolves §7 quirk) |
| NET-14 | Shared form-POST helper adoption (cross-cutting, small) | Single `FormBody` + `hash_check` injection used by NET-04/10/11 and by the reply/favourite-flag lots owned by others (`Favorites.swift:55-85`, E13) | trivial | NET-01 | Encoding table tests |

Suggested order: NET-01 → NET-02 → NET-03 → {NET-08, NET-09, NET-11, NET-12} in parallel → NET-04 → NET-05 → {NET-07, NET-10, NET-13} → NET-06 last (optional).

---

## 9. Open questions

1. **Account import**: must the new app import existing HFR+ users' accounts from the legacy keychain blob (NET-06), or is a fresh login acceptable? This decides the access-group/service-name constraints (the new bundle id cannot read the legacy keychain unless an access group is shared; unverified whether the legacy item has one — SimpleKeychain call passes `accessGroup:nil`).
2. **Server charset**: capture `Content-Type` / `<meta charset>` for `/`, `forum1.php`, `forum2.php`, `search.php`, `transsearch.php`, `message-smi-mp-aj.php`, `login_validation.php`, `editprofil.php`. Verify whether any of them is ISO-8859-1/windows-1252 and whether non-ASCII form posts (global search with accents, pseudo with accents, reply bodies) round-trip with `charset=utf-8` bodies.
3. **Cookie inventory**: names, lifetimes and flags of cookies set by `login_validation.php` (beyond `md_user`), and whether `md_user` is enough to authenticate or an unseen password-hash cookie is required; what the server sets/returns when the session expires (`md_user=deleted`? redirect to login?).
4. **Why is global search cookieless and on `config=hardwarefr.inc`?** Is login required for search at all? Is `hash_check` mandatory for `search.php`? Does a stale or empty hash fail?
5. **Banned words / base64 string** in global search: is this an App Store requirement or a joke? Keep, drop, or document?
6. **Where does HFR tell us "not logged in" on E1/E2/E4?** Only E3 has a detector. Need fixtures of anonymous vs logged-in versions of each list.
7. **MP count when zero**: is the `cCatTopic red` node absent? (determines the right semantics for NET-13).
8. **Rate limits / bot protection**: none handled in legacy; any 429/403/Cloudflare pages observed in practice? Retry policy desirable?
9. **Multi-account background polling**: legacy checks only the active account; should the new app poll all accounts (needs one session per account → NET-03 isolates this)?
10. **Is `adv_ssl` (self-signed certificates) still a product requirement?** Recommendation: drop.
11. **Does the `ASI` redirect behaviour for POST (E6/E7) matter?** ASI's `shouldUseRFC2616RedirectBehaviour` default and 301/302/303 handling (`ASIHTTPRequest.m:2314`) turn POST into GET after redirect; URLSession does the same for 301/302/303 but verify with E7/E8 fixtures.
12. Which of the Swift-direct networking sites listed in §1.3 will be owned by which lot (reply/AQ/poll/flag deletion)? They all assume the global cookie jar and global `hash_check` that NET-03 removes.
