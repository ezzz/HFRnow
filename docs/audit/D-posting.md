# Audit D — Writing to the forum (replies, quotes, edits, deletes, new topics, MPs, alerts, AQ, bookmarks, flags, smileys, image rehosting)

Legacy reference: <https://github.com/francoisgn/hfrnow> at `2440d79` (checked out read-only at `/home/user/HFRnow`).
Author: audit agent D (LOT-000, Phase 1). All paths below are relative to the legacy repo unless prefixed `new:`.
Convention: `file:line`. "unverified" = not provable from the legacy code or its tests alone (needs a captured fixture or a live check).

Boundaries (not audited in depth): networking/session/cookies/login (`hash_check` capture at login, `forceCookies`), list parsing, message-page parsing (`ParseMessagesOperation`, which produces the quote/edit/alert URLs used here), storage (BlackList, offline). Where a write flow depends on them, the dependency is named.

---

## 1. Scope

### 1.1 Target membership (how it was checked)

`SuperHFRplus.xcodeproj/project.pbxproj`:
- **HFRswift** (`15B0AA842E2C27DD0092C0FD`, pbxproj:4279) compiles Swift through one file-system-synchronized group `HFRswift/Swift` (pbxproj:4291-4293, 2671); no build-file exception set exists (no `PBXFileSystemSynchronizedBuildFileExceptionSet` in the file) so **every `.swift` under `HFRswift/Swift/` is in HFRswift**. Its ObjC `PBXSourcesBuildPhase` is `15B0AA812E2C27DD0092C0FD` (pbxproj ~5700-5760).
- The old **SuperHFRplus** target has its own phase `CA7C70B9185EF50E00B348BA`.
- `HFRswiftTests` is a synchronized group too (pbxproj:2670), hosted by HFRswift (pbxproj:5987).
- ObjC files relevant to this area that **are** in the HFRswift phase: `SmileyCache.m` (158CFA28), `MPStorage.m` (158CFA11), `Bookmark.m` (158CF9E1), `ObjCMessageActionsBuilder.m` (158CFB14), `ObjCTopicPageWorker.m` (158CFB29), `ObjCTopicListParser.m` (158CFB0B), `ParseMessagesOperation.m` (158CFA25), `LinkItem.m` (158CFA2B), `ASIFormDataRequest.m` / `ASIHTTPRequest.m` (158CFA73/71; MPStorage still uses ASI), `Favorite.m`, `FilterPostsQuotes.m`.
- Everything else listed below as "legacy-only" is compiled **only** in SuperHFRplus (`AddMessageViewController`, `NewMessageViewController`, `EditMessageViewController`, `QuoteMessageViewController`, `DeleteMessageViewController`, `AlerteModoViewController`, `RehostImage`, `SmileyViewController`, `SmileyAlertView`, `MessagesTableViewController`). They document protocol behaviour only.
- The ObjC `MPStorage` is reached from Swift through a `@convention(c)` selector bridge: `HFRswift/Swift/Common.swift:1215-1306` (`ObjCMPStorageBridge`, class looked up by name via `LegacyLoaderRuntime`). Same trick for `SmileyCache` in `ReplySmileyCatalog.swift:241-313`. Both are bridges to port away, not behaviour to keep.

### 1.2 Files

| File | Lines | Target | Responsibility | Entry points / callers |
|---|---:|---|---|---|
| `HFRswift/Swift/ReplyService.swift` | 2,132 (the file ends at 2132; numbered 1-2132) | HFRswift | **All form-based writes**: `ForumReplyPostingService` (reply, new topic, new MP, MP reply, edit; 105-739), `ForumReplyQuoteTemplateService` (quote/edit prefill GET; 741-920), `ForumMessageDeletionService` (922-1398), `ForumModerationAlertService` (1400-1733), rehost prefs/history/models (1735-1920), `Img3ReplyImageUploadService` (1958-2094), UIImage resize helpers (2096-2131) | `AnswerView.swift:123-125` (defaults), `MessagesView.swift:2801-2803` (defaults), `Common.swift:1404` (`makeReplySessionContext` warm-up) |
| `HFRswift/Swift/ReplyComposer.swift` | 205 | HFRswift | Pure text helpers: `ReplyTextInsertionEngine` (BBCode wrap, split-quote, insert) 99-205; `ReplyComposerState`/`ReplyComposerPanel` 3-50 (**unused by app code**, tests only) | `AnswerView.swift:553-570` |
| `HFRswift/Swift/ReplySmileyCatalog.swift` | 164 | HFRswift | Smiley model, `ReplySmileyCacheBridge` (ObjC `SmileyCache` bridge), bundled catalogue loader (`commonsmile.plist`) | `AnswerView.swift:124,560-561,753` |
| `HFRswift/Swift/SmileySearchService.swift` | 140 | HFRswift | `HFRSmileySearchService` (search endpoint + `<img>` regex parse), `SmileySearchHistoryStore` (UserDefaults JSON) | `AnswerView.swift:1067,1289-1291` |
| `HFRswift/Swift/AnswerView.swift` | 2,382 | HFRswift | Composer UI + the engine-like bits: context load 622-646, post 679-728, image upload 648-677, smiley keywords `wikismilies.php` 762-830, Giphy panel 2286-2345, draft persistence enum 28-35 | `MessagesView.swift:4539`, `MainWindow.swift:819` |
| `HFRswift/Swift/MessagesView.swift` | 6,580 | HFRswift | Popup actions policy 119-300; `MessagePopupActionSupport` (AQ, bookmark, favorite response) 309-430; `ReplyQuoteSelectionFormatter` 36-130; multi-quote cookies 1850-1945; favorite GET 1947-1963; AQ/bookmark prompts 1986-2100; quote/edit/MP/alert/delete orchestration 3485-3560, 3781-3835, 4281-4317 | n/a |
| `HFRswift/Swift/PollData.swift` | ~350 | HFRswift | Poll parse + **vote POST** (`PollVoteSubmitter` 44-100) — Swift-only, no legacy oracle | `PollView.swift` |
| `HFRswift/Swift/Favorites.swift` | – | HFRswift | `ForumFavoritesTopicActionService.removeFavoriteFlag` (POST `manageaction.php`) 36-103 | favorites list |
| `HFRswift/Swift/AccountSessionService.swift` | – | HFRswift | `makeReplySessionContext` 77-105: supplies `pseudo` + `hash_check` to every write (boundary: sessions) | `ReplyService.swift:146,737…` |
| `HFRswiftTests/ReplyPostingServiceTests.swift` | 1,258 | HFRswiftTests | Behaviour spec of the above (see §6) | – |
| `Classes/ObjCMessageActionsBuilder.m` | 105 | HFRswift | Builds the per-message action dictionary (quote/edit/alert/favorite/MP URLs, `canAQ`, `canBookmark`, `canDelete`) from `LinkItem` | `MessagesView` via topic page worker |
| `Classes/MPStorage.m` | 981 | HFRswift | **Forum-side storage MP** (blacklist/bookmarks/mpFlags as JSON in a private message) — see §2.10 | `ObjCMPStorageBridge` |
| `Classes/SmileyCache.m` | 462 | HFRswift | Smiley caches + app-favourite smileys persistence | `ReplySmileyCacheBridge` |
| `Classes/AddMessageViewController.m` | 1,121 | **legacy-only** | Base composer; POST logic `done` 513-636; draft 69-71,481-484 | subclasses below |
| `Classes/QuoteMessageViewController.m` | 536 | legacy-only | Form fetch + field parsing (also used for edit/new topic/MP) 28-48, 112-533 | – |
| `Classes/NewMessageViewController.m` | 15 | legacy-only | empty subclass (new topic / MP use the same `Quote…` fetch with a different URL) | – |
| `Classes/EditMessageViewController.m` | 22 | legacy-only | title "Editer", disables account picker | – |
| `Classes/DeleteMessageViewController.m` | 47 | legacy-only | `isDeleteMode = YES`, read-only text, button "Oui" | – |
| `Classes/AlerteModoViewController.m` | 419 | legacy-only | moderator alert: fetch 35-60, parse 133-180, POST `done` 205-250 | – |
| `Classes/RehostImage.m` | 490 | legacy-only | Chevereto upload `loadDataChevereto` 169-228, response 230-330, BBCode copy 395-470; dead `reho.st` upload 140-168 | – |
| `Classes/SmileyViewController.m` | 1,142 | legacy-only | Search request 868-885, parse 893-1004, history file 966 | – |
| `Classes/SmileyAlertView.m` | ~210 | legacy-only | App-favourite add/remove, keywords request 150-200; dead `addperso.php` POST (commented) 113-142 | – |
| `HFRswift/Wrapped/MessagesTableViewController.m` | 3,371 | **legacy-only** (only in SuperHFRplus phase, pbxproj:5808; comments in it mention the Swift target — unverified) | Legacy `actionFavoris` 2265-2326, AQ 2328-2460, quote cookie 2718-2750, mailto alert 2598-2607 | – |

---

## 2. Write flows

Common facts first (apply to 2.1-2.5):

- **Single write endpoint family**: forms posted by the site's own pages. The Swift code never builds the field set from scratch (except MPStorage and polls): it **GETs a page containing `<form name="hop">`, harvests every `<input>`/`<select>`, overrides a few fields, POSTs to the form's `action`**. Legacy does the same (`QuoteMessageViewController.m:209-285`, `AddMessageViewController.m:513-570`).
- **Base URL**: `https://forum.hardware.fr` (`Classes/k.m:37-40`; `ForumURL` just forwards to it, k.m:13-15).
- **Default POST target** if the form has no usable action: `<base>/bddpost.php` (new: `ReplyService.swift:697-702`, legacy `AddMessageViewController.m:203`). Legacy overrides it with `ForumURL + form@action` (`QuoteMessageViewController.m:532`), i.e. the action is **root-relative** (`/bddpost.php`); Swift resolves it against the fetch URL (`ReplyService.swift:469-487`).
- **Method / encoding of POST**: `POST application/x-www-form-urlencoded; charset=utf-8` (new: `ReplyService.swift:177`; legacy `ASIFormDataRequest.m:288-290` with `stringEncoding = NSUTF8StringEncoding`, `ASIFormDataRequest.m:51`). The app therefore **posts UTF-8**, not ISO-8859-1. Whether the server decodes it correctly for non-ASCII is not provable from the code (both apps do it, so evidently it works for accents; behaviour for characters outside Latin-1, e.g. `€`, emoji, is **unverified**). Form-encoding rules: space → `+`, `&+=?` percent-escaped, other `urlQueryAllowed` chars left raw (`ReplyService.swift:704-719`); newlines in the message body are converted `\n` → `\r\n` (`ReplyService.swift:145`, legacy `AddMessageViewController.m:554`).
- **Response decoding**: new code tries UTF-8 first, then ISO-8859-1 (`ReplyService.swift:304-309`). Legacy decodes with the charset from the response header, default ISO-8859-1 (`ASIHTTPRequest.m:2362`, `defaultResponseEncoding`; `ASIHTTPRequest+Tools.m:40-47`). The real page charset is **unverified**; `SmileySearchService.swift:31` and `UserProfileView.swift:122-135` also assume ISO-8859-1/CP1252 pages. Needs a captured fixture with raw bytes.
- **Success/failure detection** (HTML scraping, no status codes): the server answers HTTP 200 for rejections too. Both apps look at `<div class="hop">`:
  - legacy: failure ⇔ the `.hop` node contains an `<a>` or `<input>`; message = `.hop` text (`AddMessageViewController.m:594-598`; `AlerteModoViewController.m:130`; `SmileyAlertView.m`). Success text = `.hop` text; anchor = regex `<meta http-equiv="Refresh" content="[^#]+([^"]*)" />` group 1 (**includes the `#`**) (`AddMessageViewController.m:616-622`).
  - new: success ⇔ the page contains `http-equiv="refresh"` **or** a `class="hop"` whose next 2000 chars contain neither `<a` nor `<input` (`ReplyService.swift:681-695`). Failure message = `.hop` text with tags replaced by spaces and entities decoded, cut at the first `</` (`ReplyService.swift:579-625`; **duplicated 4×**: 579, 843, 1242, 1619). Anchor = text after `#` in the refresh `content` (`:627-644`, **excludes** `#`); redirect URL = `url=` part resolved against the topic URL (`:646-668`).
  - **No dedicated flood/rate-limit detection**: a flood rejection is just a `.hop` that contains a link, surfaced as `submissionRejected(message)`. The only evidence of its wording is a *synthetic* test fixture ("Afin de prévenir le flood, veuillez patienter." + `<a href="/faq.php">`, `ReplyPostingServiceTests.swift:310-345`) — **the real HTML is unverified**.
- **Logged-out detection**: `identification.php` or `name="login"` anywhere in the HTML, or the words "mot de passe" + "pseudo" without `name="hop"` (`ReplyService.swift:670-679`, same in the quote service at 891-900 and deletion at 1333-1342); the alert service has a stricter variant (pseudo field AND password field AND no hop form, `:1667-1693`) because the looser one misfired on a normal alert page (test `:799`). Result: `ReplyPostingError.authenticationRequired`.
- **Auth inputs**: every write needs (a) the account cookies in the shared cookie jar and (b) `hash_check` (CSRF-like token) plus `pseudo` (display name), obtained from `makeReplySessionContext` (`AccountSessionService.swift:77-105`: account's stored hash, else `HFRplusAppDelegate.hash_check`; cookies re-forced from the main account while **preserving cookies named `quotes*`**, `:99-107`). Both values *override* whatever the fetched form contained (`ReplyService.swift:161-166`). `hash_check` is originally scraped from `<input name="hash_check">` on pages (`FavoritesTableViewController.m:371-373`, `ObjCFavoritesLoaderWorker.m:105`, `LoginService.swift:100`). Legacy: multi-account; the POST uses the *selected* account's cookies with `setUseCookiePersistence:NO` (`AddMessageViewController.m:571-573`); new: always the *main* account.
- **Timeouts**: none set on writes (URLSession default 60 s); legacy `kTimeoutMini` for fetches.

### 2.1 Reply (existing topic, incl. fast-answer)

Source URL: `topicAnswerURL` = `href` of the first `<a>` inside `#repondre_form` of the topic page (`Classes/ObjCTopicPageWorker.m:156-157`, made absolute at `:142-143`; flows into `MessagesView.swift:3114,3189` → `composerSubmitURL`, opened at `MessagesView.swift:3836-3848`). A `forum2.php?…&numreponse=…` page and `message.php?config=hfr.inc&cat=13&post=42` both contain `<form name="hop">` (tests use both).

1. **GET** the answer URL (`ReplyService.swift:229-271`). Status must be 2xx; logged-out check; side effect: scrape `<div id="dynamic_smilies">` `<img src alt>` into the forum-favourite smiley cache (`:249-252`, `:504-555`).
2. Extract `<form … name="hop"> … </form>` by lazy regex (first match only, `:489-502`). Harvest:
   - every `<input name=…>`: `checkbox` → `"1"` if `checked` attr present else `"0"`; `radio` → value only if `checked`; everything else (text, hidden, submit…) → `value` or `""` (`:311-341`). Attribute values are **not HTML-entity-decoded** (see §7, bug B1).
   - every `<select name=…>`: selected option's `value`, else first option's (`:343-365`).
   - The `<textarea id="content_form">` is ignored for replies (overridden).
3. Merge the **query items of the fetch URL** into the params where absent (`:149-157`) — legacy never did this (unverified effect: extra `page`, `new`, `nojs`, `numreponse`, `quote_only` … sent).
4. Remove `allowvisitor`, `have_sondage`, `sticky`, `sticky_everywhere` when their value is `"0"` or empty (`:294-302`); legacy only sent these when `"1"` (`AddMessageViewController.m:521-526`).
5. Set: `content_form` = message with `\r\n` (`:160`; legacy first strips emoji with `removeEmoji`, ranges U+1D000–1F77F and U+2100–26FF, `AddMessageViewController.m:553`, `RangeOfCharacters.m:306-325` — **not ported**); `pseudo`; `hash_check`; `config=hfr.inc` if absent (`:167-169`); then caller overrides: `sujet` (only if a subject field is shown), `subcat` (only if a category picker is shown), `dest` (if a recipient is known) (`AnswerView.swift:686-695`).
6. **POST** to form action (default `bddpost.php`) (`:174-183`).
7. Response → status non-2xx ⇒ `serverError`; logged-out ⇒ `authenticationRequired`; `isSuccessfulPost` false ⇒ `submissionRejected(hop message)`; else result = `{refreshAnchor, refreshURL, statusMessage}`. UI refreshes the last page using `refreshURL` if present else `anchor` (`MessagesView.swift:4299-4317`, only when the user is on the last page).

Hidden fields observed (from tests / MPStorage POST): `cat`, `post`, `p`, `numreponse`, `hash_check`, `pseudo`, `sujet`, `subcat`, `dest`, `config`, `MsgIcon`, `verifrequet`, `parents`, `ColorUsedMem`, `signature`, `new`, `owntopic`, `sond`, `sondage`, `smiley`, `wysiwyg`, `page`, `password`, `emaill`, `cache`, `search_smilies`, `stickold`, `numrep`, `submit` (list from `MPStorage.m:772-824`; the *actual* reply form's field list is **unverified** — needs a fixture).

Legacy differences worth knowing: the legacy parser only takes inputs that have **both** `name` and `value` attributes (`QuoteMessageViewController.m:221`); `MsgIcon` only if `checked` (`:223-227`); legacy fetches `[urlQuote lowercaseString]` (whole URL lower-cased, `:36`; same for alert `AlerteModoViewController.m:40`) — new code does not lowercase.

### 2.2 Quote and multi-quote

Two independent mechanisms.

**(a) Single quote button** ("Citer"). `quoteURL` = decoded `urlQuote` of the message. The URL is **obfuscated in the HTML**: it lives in the CSS `class` attribute of the parent element of `<img alt="answer">` (`HFRswift/Wrapped/ParseMessagesOperation.m:371-372`), and must be decoded with `decodeSpanUrlFromString`: drop the first 20 chars, then read pairs of chars, each mapped through the alphabet `"0A12B34C56D78E9F"` (index = nibble) into one byte (`SuperHFRplus/Helpers/RangeOfCharacters.m:92-114`). Applies to `urlEdit` too (`ParseMessagesOperation.m:374-375`). `ObjCMessageActionsBuilder.m:80-89` only decodes when the string is >20 chars, contains no `/` and no `http` (i.e. skips already-plain URLs). **Boundary with message-page parsing; this decoder is mandatory for every quote/edit URL.**
- Flow: GET `quoteURL` → take `<textarea id|name="content_form">` content, decode entities, `\r\n`/`\r` → `\n` (`ReplyService.swift:767-799`, `:823-841`) → prefill composer. The server generates the `[quotemsg=cat,post,numreponse]…[/quotemsg]` text. Then the composer POSTs to the topic's *answer* URL (`composerSubmitURL = topicAnswerURL ?? url`, `MessagesView.swift:3563`), so the quote URL is only a template source. Decoder is a 7-entity replace list (`:902-915`; the Reply service has a larger one, `:721-734`, with numeric forms of `"`).
- **Quote of a text selection** ("Citer la sélection"): `ReplyQuoteSelectionFormatter.format` (`MessagesView.swift:36-130`, tests `ReplyPostingServiceTests.swift:1101-1132`): finds `[quotemsg=N,N,N]…[/quotemsg]` blocks; one block → replace its body with the selection (or bold the selection inside the full quote); several blocks → pick the first containing the selection (case-insensitive); legacy equivalent `QuoteMessageViewController.m:461-525`. Pure text logic, portable as-is.

**(b) Multi-quote** (select several posts, then answer). It is a **client-side cookie protocol**: `quoteJS` = `onclick` of the post's `quoter('hardwarefr', cat, post, numreponse)` link (`ParseMessagesOperation.m:386-387`). The app writes the cookie the site's own JS would write:
- name `quotes<arg0>-<arg1>-<arg2>` (e.g. `quoteshardwarefr-13-42`), value = concatenation of `|<numreponse>` markers (toggle: append if absent, remove if present; delete the cookie when empty), domain `.hardware.fr`, path `/`, **expires now+1 h** (`MessagesView.swift:1853-1929`; legacy `MessagesTableViewController.m:2718-2750,2666-2680`).
- The cookie lives in `HTTPCookieStorage.shared`; the session context deliberately preserves `quotes*` cookies when it re-forces account cookies (`AccountSessionService.swift:99-107`). The server then pre-fills the next answer form's textarea with all selected quotes — this is why the quote/answer GET must carry the cookie. Server-side behaviour is **unverified** (inferred from the cookie name and the preserve-cookie hack).
- `isQuoteSelectionEnabled` (checked state in the popup) = cookie value contains `|<numreponse>` (`:1922-1927`).

### 2.3 Edit

- Entry: `editURL` (obfuscated like `quoteURL`, present only on the user's own posts; `isOwnMessage` is derived from its presence, `ObjCMessageActionsBuilder.m:38-46`).
- Flow (new): GET editURL via the quote-template service (prefill, as 2.2a) → composer opens with `composerPersistsDraft=false`, `composerSubmitURL = editURL` (`MessagesView.swift:3525-3531, 3555-3566`) → on Send the generic `postReply` re-GETs **the edit URL** (form), overrides `content_form` (and `sujet`/`subcat` if the form exposes them: editing the first post of own topic), and POSTs to the form's action. Test: `testPostReplyOmitsInactivePollFlagWhenEditingTopicOwnerPost` (`:130-197`) — edit URL `message.php?…&sondage=0&owntopic=1&numreponse=123`, form has `sujet` text, `subcat` select, the four flag checkboxes → flags dropped, `sujet`/`subcat` overridden.
- Real edit POST action: legacy MPStorage edits an existing MP via **`bdd.php`** and creates via **`bddpost.php`** (`MPStorage.m:772-774`) → the edit form's action is probably `/bdd.php`; the test fixtures use `/bddpost.php` everywhere. **Unverified.** Do not hard-code; always read the form action.
- Divergence: legacy does not send `delete` unless in delete mode (`AddMessageViewController.m:527-531`); the new generic path sends whatever `delete` input the edit form has (checkbox → `"0"` when unchecked) — unverified whether this matters.

### 2.4 Delete

- Entry: only offered when `editURL != nil && canDelete && messageIndex != 0` (`MessagesView.swift:251-257`; `canDelete = index > 0` at `ObjCMessageActionsBuilder.m:43`), after a confirmation dialog (`MessagesView.swift:3805-3835`). First post of a topic cannot be deleted from the UI.
- Flow (`ForumMessageDeletionService.deleteMessage`, `ReplyService.swift:954-1007`): session context → GET editURL → hop form (inputs+selects, **plus** `content_form` textarea existing text, entity-decoded, newlines normalised `:1036-1038`) → merge URL query → set `delete=1`, `content_form` = existing text (`\r\n`), `pseudo`, `hash_check`, `config` → POST form action → success via `isSuccessfulDelete` (same heuristic as reply, `:1344-1358`).
- Result: `refreshAnchor` = the `numreponse` query item of the edit URL (preferred), else the refresh anchor; `refreshURL` from meta refresh; statusMessage = hop text. Legacy extracted the anchor with `numreponse=([0-9]+)&` from the quote URL (`AddMessageViewController.m:611-614`).
- Deletion = "edit with `delete=1` and the unchanged text" (legacy `DeleteMessageViewController.m:42-44`, `AddMessageViewController.m:527-531`).

### 2.5 New topic and private messages (new MP, MP reply)

All use the same `postReply` path; only the source URL and extra fields differ.

- **New topic**: URL = `href` of `#md_btn_new_topic` on the topic-list page (`Classes/ObjCTopicListParser.m:134-135`; `Common.swift:1562`; `MainWindow.swift:820`). The form exposes `sujet` (text, 70-char UI limit, `AnswerView.swift:179-181`, `MainWindow.swift:825`) and `subcat` (`<select>`, options parsed `ReplyService.swift:392-414`; picker required, `AnswerView.swift:157-163`). `isSubjectEditable` = a non-hidden `<input name=sujet>`; `isSubcategoryEditable` = any `<select name=subcat>` (`:267-268`). Legacy used the same `haveTitle` logic (`QuoteMessageViewController.m:241-249`).
- **New MP**: URL = `MPUrl` = link containing `/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=` on the message's author block (`ParseMessagesOperation.m:389-390`; shown for non-own messages, `MessagesView.swift:207-216`; from profile via `UserProfileQuickActions`). The form has `dest` (recipient; legacy shows it editable) and `sujet`. `AnswerView` always sends `dest` override when a recipient is known (`:695`), `requiresSubject` = true for MPs (`MessagesView.swift:3537-3545`).
- **MP reply**: answer URL of a `cat=prive` topic page; same as 2.1. Inputs `dest`/`sujet` may be hidden in this case and are surfaced as read-only context (`fetchComposerContext`, `ReplyService.swift:217-227`; test `:663-696`).
- There is **no UI entry for a blank "compose MP" without a recipient** in HFRswift (only via avatar/profile) — unverified that none exists elsewhere (`grep` of `message.php` found none).
- Poll creation: not supported (`have_sondage` is removed when `0`, and no poll fields are exposed).

### 2.6 Moderator alert ("Alerter")

- Entry: `alertURL` = first `href` containing `/user/modo.php` inside the message (`ParseMessagesOperation.m:377-378`), shown for others' messages; if absent but a permalink exists the menu falls back to an **anonymous mail**: `mailto:marc@hardware.fr?subject=[HardWare.fr] Signalement d'un contenu illicite&body=Message : <permalink>` (`MessagesView.swift:236-241, 3762-3777`; legacy `MessagesTableViewController.m:2598-2607`). That address is hard-coded — personal data of a third party, worth a conscious decision.
- Flow (`ForumModerationAlertService`, `ReplyService.swift:1400-1500`):
  1. GET alertURL; logged-out check.
  2. **"Already alerted" detection**: the first `class="hop"` container contains `<a` or `<input` ⇒ `.alreadyAlerted(message)` (`:1524-1531`; legacy `AlerteModoViewController.m:132-140`). Note this is the *inverse* meaning of the reply check (there a link in `.hop` means rejection); the alert page shows a normal form without `.hop`.
  3. Otherwise find `<form … action=…modo.php…>` (`:1509-1522`), take **all inputs** (name+value; same parse as reply) and the action URL resolved against alertURL (default `<base>/user/modo.php`, `:1695-1700`). Legacy: `ForumURL + "/user/" + action` and inputs requiring both `name` and `value` (`AlerteModoViewController.m:158-177`).
  4. `submitAlert(reason:)`: reason trimmed non-empty else `.emptyMessage`; POST params + `raison` (`\r\n`; legacy strips emoji `:209`) (`:1465-1500`). **Success = a non-empty hop message** (`:1495-1499`), nothing else is checked; legacy shows whatever `.hop` text (`:226-240`).
  5. No `hash_check`/`pseudo` is added here (they come from the form's own inputs if present — unverified).

### 2.7 AQ ("Alerte Qualitay") — external service `aq.super-h.fr`

Not an HFR form: a community third-party service. Entry only for non-MP topics (`canAQ = !isPrivateCategory`, `ObjCMessageActionsBuilder.m:19`).
- Pre-check: `GET https://aq.super-h.fr/api/getAlertesByTopic.php?topic_id=<topic>`; "already signalled" ⇔ the body (UTF-8 string) **contains the numeric post id as a substring** (`MessagesView.swift:322-338`). Substring match can false-positive (post id contained in another number/URL). Failure ⇒ `nil` ⇒ "Création d'AQ impossible". Legacy timeout 2 s (`MessagesTableViewController.m:2332-2336`); response format example in a legacy comment (`:2340-2349`): `<alertes> pseudo=…&post_id=…&post_url=…&commentaire=…`.
- Create: `POST https://aq.super-h.fr/api/addAlerte.php`, `application/x-www-form-urlencoded`, timeout 5 s, no cookies/auth. Body, **fixed field order** (`MessagesView.swift:381-399`, test `MessageWebActionHandlerTests.swift:382-396`):
  `alerte_qualitay_id=-1&nom=<title>&topic_id=<id>&topic_titre=<topic title>&pseudo=<current display name, lowercased>&post_id=<digits of post id>&post_url=<permalink>&commentaire=post de <author>`
  Percent-encoding: only `[A-Za-z0-9._-]` left raw (`:407-410`). Body bytes written as ASCII (`:359`). Response body `"1"` ⇒ success, anything else ⇒ error code shown as "Code erreur X" (`:370-372`). Legacy comment records the field semantics (`MessagesTableViewController.m:2441-2455`); notably `alerte_qualitay_id` = existing AQ id to re-report the same message, `-1` = new; "pseudo is not secured, anyone can create an AQ in any name".
- Data sent to a third party: pseudo (lowercased), topic id/title, post id/URL, author name, free-text title. See §5.

### 2.8 Favourites / flags (topic-level)

- **Add a topic to favourites from a message**: `GET <favoriteURL>`, `favoriteURL` = `href` of the first link containing `addflag` in the message (`ParseMessagesOperation.m:383-384`; shown only if `canBeFavorite`, `MessagesView.swift:227-229`). It is a **state-changing GET**. Response parsed with `<div class="hop">([^<]+)</div>` for a toast text, fallback "Favori mis à jour" (`MessagesView.swift:1947-1963, 420-431`; legacy `MessagesTableViewController.m:2265-2326`, `.*<div class="hop">([^<]+)</div>.*`). No success/failure distinction beyond the text; any network error ⇒ "Erreur réseau". Whether the URL carries `hash_check` is **unverified** (it is a server-generated href).
- **Remove a favourite flag from the favourites list**: `POST https://forum.hardware.fr/modo/manageaction.php?config=hfr.inc&cat=0&type_page=forum1f&moderation=0` with body `hash_check, topic1=-1, topic_statusno1=-1, action_reaction=message_forum_delflags, type_page=forum1f, topic0=<topicId>, valuecat0=<catId>, valueforum0=hardwarefr` (`Favorites.swift:36-103`; legacy `FavoritesTableViewController.m:1836-1853`). Only HTTP status is checked (`Favorites.swift:92-100`). `hash_check` here comes from the app-delegate global only (`Favorites.swift:49-56`), not the per-account hash.
- **Mark topic read / flag position** are GETs of `aURLOfFlag`/`nonlu`/`delflag` hrefs (`MessagesTableViewController.m:1559-1570`, `FavoritesTableViewController.m:1604-1607`): belong to the list/message-page audits; mentioned for completeness.
- "Super favourites" (`SuperFavoritesIds`) are app-local (`Favorites.swift:106+`): not a forum write.

### 2.9 Poll voting (Swift-only; no legacy oracle)

`PollVoteSubmitter.submit` (`PollData.swift:44-100`): params = all `<input type="hidden">` of the poll block + one field per chosen option (`option.fieldName` = the input's `name`; value = the option's **1-based index** for single-choice, `"1"` for multiple-choice); `POST https://forum.hardware.fr/user/vote.php?config=hfr.inc`, `Content-Type: application/x-www-form-urlencoded` (no charset), response decoded **UTF-8 only**; error ⇔ `.hop` contains `<a`/`<input`; **a response without any `.hop` is treated as success** (`:79-84`). Using the position index as the radio value is a guess (unverified). Legacy only displayed polls (`MessagesTableViewController.m:833`, `showPoll:`). Needs fixtures (poll before/after vote).

### 2.10 Bookmarks and MP flags — the "MPStorage" private message (forum-side database!)

Bookmarks are **not local**: `MessagePopupActionSupport.createBookmark` → `ObjCMPStorageBridge.addBookmark` → ObjC `MPStorage.addBookmarkSynchronous` (`MessagesView.swift:401-416`, `Common.swift:1283-1296`). Shown when `UserDefaults mpstorage_active` and not a private category (`ObjCMessageActionsBuilder.m:18`).

Protocol (`Classes/MPStorage.m`):
- **Storage = one private message** in the user's MP inbox, topic title (`sujet`) = constant `a2bcc09b796b8c6fab77058ff8446c34` (`MP_NAME`, `:21`), recipient `MultiMP` (`MP_SENDTO`, `:22`), body = a JSON document `{"data":[{"version":"0.1","blacklist":{"list":[…]},"mpFlags":{"list":[…]},"bookmarks":{"list":[…]}, …}], "sourceName":"iOS","lastUpdate":<ms>}` (creation template `:629-630`). Shared with other HFR+ clients (`sourceName` records the writer).
- **Find it**: scan MP list pages `forum1.php?config=hfr.inc&cat=prive&page=N&subcat=&sondage=0&owntopic=0&trash=0&trash_post=0&moderation=0&new=0&nojs=0&subcatgroup=0`, rows `class~"sujet ligne_booleen"`, title cell `sujetCase3` equal to `MP_NAME` or `[non lu] MP_NAME`, topic id = `post=` query item of its link, pages from `.fondForum1PagesHaut .left` last child (`:588-621`). Topic id cached per pseudo-alias in `UserDefaults["dicMPStorage_postid"]` (`:536-566`).
- **Read**: `GET forum2.php?config=hfr.inc&cat=prive&post=<id>&numreponse=0&page=1&p=1&subcat=0&sondage=0&owntopic=0` with `setUseCookiePersistence:NO` and the main account's cookies (`:769-776`). Parse: `.messagetable` second `<td>`: `numrep` = id of the `para…` div minus the 4-char prefix (`:880-881`), JSON = text of its `<p>` with U+00A0 removed (`:882-885`). If the body contains the word `destiné` (the "this message is not for you / not found" page) the cached id is dropped and the search is redone, offering re-creation (`:858-866`).
- **Create**: `POST bddpost.php?config=hfr.inc` with the full field list in `MPStorage.m:772-824` (`p=1, pseudo, ColorUsedMem="", submit="Valider votre message", parents="", MsgIcon=1, verifrequet=1100, new=0, search_smilies="", stickold="", sond=0, signature=1, sondage=0, smiley=0, owntopic=0, numrep="", hash_check, cat=prive, wysiwyg=0, page=1, password="", emaill=0, config=hfr.inc, cache="", content_form=<json>, sujet=MP_NAME, dest=MultiMP, numreponse="", post=""`). **Update**: same fields but URL `bdd.php?config=hfr.inc`, `numreponse=<sNumRep>`, `post=<topic id>`, no `dest`. This is the only place where the full POST field set of the editor is known — an invaluable oracle for the form-builder.
- **Success** = response body contains the French substring `succès` (`:660-666, 686, 746`); anything else = failure (shown to the user with the `.hop` text on create).
- **Read-modify-write** for every change (blacklist add/remove, bookmark add/remove, flag update): GET → parse → mutate → POST (`:249-330`, `:333-355`); no locking/ETag → lost updates between devices/clients; `bIsMPStorageSavedSuccessfully` gates later reads (`:152-156`). Bookmark JSON entry: `{post, cat, author, numreponse, label, createDate(ms)}` (`:320`, `:540-558` for parse).
- `saveMPStorageAsynchronous` actually posts **synchronously** (`startSynchronous`, `:737`); `addBookmarkSynchronous` is called synchronously from the UI (`Common.swift:1283` → main thread blocking).
- Boundaries: blacklist/whitelist and mpFlags semantics belong to the storage audit; the *transport* (find/read/create/update the storage MP) belongs here.

---

## 3. Smileys and image rehosting

### 3.1 Smiley catalogue sources

1. **Bundled "common" smileys**: `SuperHFRplus/commonsmile.plist` (59 entries, 35 with `editor=true`; keys `code`, `src` (https://forum-images.hardware.fr/icones/…), `resource` (bundled GIF name), `editor`) loaded in both targets (pbxproj:685, 1341). New loader `BundleReplySmileyCatalogLoader` (`ReplySmileyCatalog.swift:110-144`) keeps `editor==true` only and loads GIFs from the app bundle (`AnswerView.swift:1725-1740`, folder `Assets/HFR/Smilies`). Legacy `SmileyCache.m:90-102`.
2. **Forum-favourite ("smilies persos") list**: scraped from `<div id="dynamic_smilies">` `<img src alt>` on **every reply/answer form fetch** (`ReplyService.swift:249-252, 504-555`; legacy `QuoteMessageViewController.m:146-205`), stored in `SmileyCache.arrFavoritesSmileysForum` through KVC (`ReplySmileyCatalog.swift:262-278`). Legacy also downloaded each image into `Caches/SmileCache` (`QuoteMessageViewController.m:157-195`); new code does not (remote GIF via `URLSession.shared` + in-memory `NSCache`, `AnswerView.swift:1741-1749`).
3. **App-local favourite smileys** (not the forum's): `NSKeyedArchiver` dictionary `code → SmileyFavorite{sCode,sRawUrl,dateAdded}` in `Documents/smiley_favorites_cache2` (`SmileyCache.m:SMILEY_CACHE_FAVORITES_DIC`, `AddAndSaveDicFavoritesApp:` and `loadDicFavorties`), sorted by `dateAdded`; add fails (returns NO) if the code is already present, remove fails if absent. Toggled from the smiley sheet and from the message-page smiley long-press (`AnswerView.swift:733-757`, `MessagesView.swift:3318`). The forum-side add (`POST /user/addperso.php?config=hfr.inc`, fields `hash_check`, `smilie`) is **commented out** in legacy (`SmileyAlertView.m:113-142`) — server-side favourites are never written by the app.
4. **Search**: `GET https://forum.hardware.fr/message-smi-mp-aj.php?config=hfr.inc&findsmilies=<q>` (`SmileySearchService.swift:386-405`; legacy `SmileyViewController.m:879`). Response = HTML fragment of `<img src alt>`; parse every `<img>`; `alt` = code, `src` = image URL (`:413-442`; legacy takes `src`/`alt` from every `img`, `:900-903`). Query semantics: legacy always sends `+word1 +word2` (AND, `SmileyViewController.m:868`, encoded with `+`→`%2B`, space→`%20`); new code sends words either bare (any keyword) or `+`-prefixed when the "all keywords" switch is on (`AnswerView.swift:1308-1318`), min 3 chars (`SmileySearchService.swift:387`, `AnswerView.swift:1277`). No auth, no cookies (`URLSession.shared`; it does carry the shared jar by default — unverified relevance).
5. **Keywords of a smiley** (wiki): `GET /wikismilies.php?config=hfr.inc&detail=<code, urlPathAllowed-encoded>`, value of `<input name="keywords0" value="…">`, entities decoded (partial list), split on commas/whitespace (`AnswerView.swift:762-830`, duplicated in `MessagesView.swift:3322-…`; legacy `SmileyAlertView.m:150-200`, timeout 2 s). Code `[:ezzz]`-style contains `[`,`:` which `urlPathAllowed` leaves raw — unverified OK.
6. **Search history**: new `UserDefaults["smileySearchHistory_v1"]` JSON, ≤50 entries, only queries ≥3 chars with ≥1 result (`SmileySearchService.swift:457-509`). Legacy: `Documents/smileysSearch.plist` NSKeyedArchiver of `SmileySearch{sSearchText,nSearchNumber,dLastSearch}` (`Constants.h:88`, `SmileyViewController.m:949-970`); **no migration** from legacy to new.
7. Legacy also kept an in-memory cache of search results per query (`SmileyCache.m` `cacheSmileyRequests`).

### 3.2 Image rehosting

- **Service in use**: self-hosted **Chevereto** at `img3.super-h.fr` (community image host). `POST https://img3.super-h.fr/api/1/upload/?key=<API key>` (`ReplyService.swift:1970`; legacy `RehostImage.m:171`). **The API key is hard-coded in the new Swift source** (`ReplyService.swift:1962-1963`, comment "keep in sync with legacy API_KEY_CHEVERETO_IMG3"); legacy keeps it in an untracked `api_keys.h` (not present in the repo at `2440d79`). Value deliberately not reproduced here.
- **Protocol**: `multipart/form-data`, fields: `imageCaption` = `"Some Caption"` (constant) and `source` = JPEG bytes with filename `snapshot_<random>.jpg`, `Content-Type: image/jpeg`; cookies disabled; timeout 60 s; no `format=json` param (JSON is the default of the v1 API) (`ReplyService.swift:1982-2060`; legacy `RehostImage.m:171-210`). New code uses a UUID boundary, legacy the fixed string `unique-consistent-string`.
- **Pre-processing**: orientation normalised, longest side downscaled to the user setting (400/600/800/1000/**1200 default** px, never upscaled), re-encoded JPEG **quality 1.0** (`ReplyService.swift:2096-2131`; legacy `UIImage+Resize scaleAndRotateImage`, `RehostImage.m:130-134`; setting key `rehost_resize_before_upload`). **File-size/quota limits are not enforced client-side**; only a (synthetic) test mentions "File too big - max 500 KB" (`ReplyPostingServiceTests.swift:1002-1037`): real server limits **unverified**.
- **Response**: JSON. Success ⇔ `status_code == 200` (payload value preferred over HTTP status); `image.url` (full), `image.medium.url`, `image.thumb.url`, `image.width/height`; no "preview" size in Chevereto (new `previewURL` always nil; legacy `link_preview` nil). Error message from `error.message` (`ReplyService.swift:2007-2034, 2062-2083`; legacy `RehostImage.m:230-320`, error text `"<code> - <message>"`). Legacy example payload in a comment (`RehostImage.m:236-297`) is a ready fixture template.
- **BBCode snippets** (`RehostUploadedImage.formattedSnippet`, `ReplyService.swift:1866-1892`): `linkOnly` → bare URL; `imageNoLink` → `[img]URL[/img]\n`; `imageWithLink` → `[url=FULL][img]URL[/img][/url]\n`; variant fallbacks: preview → medium → mini → full, mini → medium → full, medium → full. Setting keys: `rehost_use_link` (0 imageWithLink, 1 imageNoLink, 2 linkOnly; legacy enum `bbcodeImageWithLink` default), `rehost_resize_before_upload` (`ReplyService.swift:1795-1810`; legacy `RehostImageViewController.m:81-99`).
- **History**: `Documents/rehostImagesSwiftUI.json` (JSON `[RehostUploadedImage]`) — separate from the legacy archive (`RehostImage` NSCoding, v1) so legacy history is not carried over (`ReplyService.swift:1895-1919`).
- **Dead / historical hosts**: legacy `reho.st/upload` (HTML-scraping of 8 `<code>` blocks, `RehostImage.m:140-168, 195-224`) is unused code (`loadData:` calls Chevereto only, `:135`); image-viewer normalisation still rewrites `reho.st/thumb/`, `rehost.diberie.com/Picture/Get/t/` and `img3.super-h.fr/images/…th.` URLs to the full image (`MessagesView.swift:3299-3314`) — read-side concern but shows which hosts exist in old posts.
- **Third-party GIFs (Giphy)**: `GiphyUISDK` (binary framework in `Frameworks/`) with a hard-coded SDK key in `HFRswiftApp.swift:20`; rating `R`, gifs+recents; inserts `[img]<original gifUrl>[/img]\n` (`AnswerView.swift:2286-2345`). Legacy: `[Giphy configureWithApiKey:API_KEY_GIPHY]` (`AddMessageViewController.m:154`). Out of scope for the engine (UI SDK) but the snippet format is protocol.

---

## 4. Drafts

| What | New app | Legacy |
|---|---|---|
| Reply draft | Single **global** string `@AppStorage("composerDraftText")` (`MessagesView.swift:2668`), shared across all topics/accounts; stored on `onDisappear` of the sheet via `ComposerDraftPersistence.draftAfterDismiss`, cleared after a successful post only for persistent composers (`AnswerView.swift:28-35, 262-267, 702-705`; tests `ReplyPostingServiceTests.swift:1134-1160`). Persisting is enabled **only** for the plain "Répondre" composer (`MessagesView.swift:3842-3849`); quote, selection-quote, edit and MP composers use `persistsComposerDraft=false` (`:3512, 3548, 3543`), so they neither load nor overwrite the draft. | One global `UserDefaults["brouillon"]` (`AddMessageViewController.m:69, 481-484`); on Cancel with text the user is asked "Enregistrer le texte comme brouillon ? / Remplacer le brouillon ?" with a 60-char extract (`:157-188, 440-474`); cleared automatically after a post when the draft had been inserted (`:601-603`); inserted via explicit action (`sBrouillonUtilise`). |
| New-topic draft | `@State newTopicDraftText` in `MainWindow.swift:277` → **memory only**, lost on relaunch; cleared on success (`:828`). Subject/category are never persisted. | none (same global draft) |
| Subject, recipient, category | not persisted | not persisted |
| Undo/redo | in-memory stacks (200 steps) (`AnswerView.swift:78-81, 268-278`) | n/a |
| Image history & prefs | see §3.2 | see §3.2 |
| Quote cookies | HTTP cookie jar, TTL 1 h | same |

`ReplyQuoteDraftMerger` (`MessagesView.swift:15-34`, merges a quote into an existing draft) is **dead code** — only tests call it.

Port note: HFRStorage should own a small `DraftStore` (key = {reply(topic), new-topic(forum), mp(recipient)}); keep "ephemeral composers never touch the global draft" as a tested rule.

---

## 5. Security notes

1. **Hard-coded third-party keys in the new tree**: Chevereto upload key (`ReplyService.swift:1962-1963`) and Giphy SDK key (`HFRswiftApp.swift:20`). Legacy keeps them out of git (`api_keys.h` absent). In the new repo (AGENTS.md rule 4: secrets never enter the repo) both must come from build-time config/CI secrets; any key already committed in the legacy history should be considered public/rotatable. (Not copied here.)
2. **Tokens in logs (legacy)**: `AddMessageViewController.m:524,534,538,541,549,557,560,564,568` log every POST field including `hash_check`, `pseudo` and the **whole message body**; lines 574-579 log cookie names/domains/lengths and headers. New code prints only `"POST error: …"` (`AnswerView.swift:725`) but `MessagesView.swift:2836` prints topic URLs; MPStorage logs the whole response and JSON (`MPStorage.m:660,685`). In the new engine: no logging of request bodies, headers, cookies, `hash_check`.
3. **CSRF-style token** (`hash_check`) is read from the page and from the account store and **overrides** the form's own value (`ReplyService.swift:164-166`); if the stored value is stale the form's fresh one is thrown away — unverified lifetime. Prefer: use the form's token when present, fall back to the stored one.
4. **State-changing GETs** (`addflag`, `delflag`, `nonlu`) follow server-supplied hrefs; make sure only same-host (`forum.hardware.fr`) absolute URLs are followed (the builder prefixes the forum base for relative hrefs but passes through any `http(s)://` host, `ObjCMessageActionsBuilder.m:70-78`; the new `postReply` also happily POSTs to whatever absolute action the fetched form declares, `ReplyService.swift:486`). A host allow-list in HFRNetwork is a cheap hardening (the POST carries `hash_check` + cookies).
5. **Data sent to third parties**: AQ service gets pseudo, topic id/title, post id/URL, author, free text, over HTTPS, unauthenticated, spoofable (service-side trust model); Chevereto gets the (possibly EXIF-containing? — the UIImage re-render drops metadata in the resize branch but `jpegData` of an un-resized `normalized` image comes from the `UIImage`, metadata not preserved; unverified) user photo; Giphy SDK gets device/usage data (SDK behaviour, not audited); mailto alert goes to `marc@hardware.fr`.
6. **MPStorage** writes user data (blacklist, bookmarks, per-topic read positions) into a private message visible in the user's inbox to the forum operators; the constant title is public in the code.
7. Cookie handling for multi-quote writes cookies named by server-provided JS arguments into the shared jar with a hard-coded domain `.hardware.fr` (`MessagesView.swift:1905`); fine, but ensure parsing of `quoteJS` rejects anything but `[A-Za-z0-9_-]` in the cookie name.
8. Non-HTTPS: no `http://` is used for writes; legacy comments reference `http://forum.hardware.fr` only in dead code. ATS exceptions: not audited.

---

## 6. Existing tests (what they pin down)

`HFRswiftTests/ReplyPostingServiceTests.swift` (1,258 lines; XCTest, `URLProtocolMock` transport mock at `:1227`; injected `sessionContextProvider` → `{pseudo:"testeur", hash:"hash123"}`). All HTML fixtures are **hand-written snippets, not captured pages**.

| Test (line) | Asserts |
|---|---|
| `testPostReplySuccessUsesReplyFormThenPostsBody` (13) | exactly 2 requests GET then POST; `content_form`=`"Bonjour\r\nMonde"`; `pseudo`, `hash_check` injected; meta-refresh `0;url=/forum2.php?page=12#t789` ⇒ anchor `t789` |
| `…AppliesSubjectAndRecipientOverrides` (72) | `sujet`, `dest` overrides win over form values |
| `…OmitsInactivePollFlagWhenEditingTopicOwnerPost` (130) | the four checkbox flags absent when unchecked; `subcat`/`sujet` overridden (edit URL `owntopic=1&numreponse=123`) |
| `…FailsWhenAuthIsRequired` (199) | login form in GET ⇒ `authenticationRequired` and no POST |
| `…WhenSessionContextFails…` (240) / `…WhenMessageIsBlank…` (275) | no network when session missing / message blank |
| `…SubmissionRejectedParsesHopMessage` (310) | 200 + `.hop` containing `<a>` ⇒ `submissionRejected("Afin de prévenir le flood, veuillez patienter. Aide")` (tags → spaces) |
| `testFetchQuoteTemplate…` (373, 405, 437) | textarea `content_form` content returned; numeric entities decoded; missing hop form ⇒ `replyFormUnavailable` |
| `…ServerErrorParsesHopMessageWithoutClassPrefix` (477, 540) | HTTP 5xx + `class="hop"` message in `serverError` |
| `testPreloadReplyContextLoadsForumFavoriteSmileys…` (616) | `dynamic_smilies` scraped into the bridge |
| `testFetchComposerContextReturnsPrivateMessageSubjectAndRecipient` (663) | `sujet`/`dest` + editability flags |
| `testDeleteMessageSuccess…` (698) | GET edit URL, POST to `/bddpost.php` with `delete=1`, existing text `\r\n`-normalised and entity-decoded, `numreponse` from URL, refresh URL/anchor/status |
| `testModeration…` (764-957) | already-alerted when `.hop` has a link; no false login detection from generic "pseudo/mot de passe" text; login form ⇒ `authenticationRequired`; submit posts `raison` with `\r\n`, returns hop text; blank reason ⇒ no network |
| `testImg3Upload…` (959, 1002) | multipart has `name="source"`; JSON parse of full/medium/thumb + width/height; `status_code != 200` ⇒ `serverError(400,"File too big - max 500 KB")` (message invented) |
| `testRehostUploadedImageFormatsBBCode…` (1040) | snippet matrix |
| `ReplyQuoteDraftMerger*` (1064-1099) | dead-code helper |
| `ReplyQuoteSelectionFormatter*` (1101-1132) | selection quote/bold/multi-block |
| `ComposerDraftPersistence*` (1134-1160) | draft rules of §4 |

Related: `MessageWebActionHandlerTests.swift:352-396` (post-id digits extraction, `hop` message extraction for favourite, **AQ body byte-exact**), `MessagePopupMenuPolicyTests.swift` (which actions appear and in which order: quote first, edit third, delete requires `editURL` and index>0, alert fallback, favourite needs capability+URL), `ReplyComposerStateTests.swift` (dead `ReplyComposerState` + text insertion).
**Not covered**: new-topic with `subcat` options parsing (only via context test), MP creation, multi-quote cookie protocol, poll vote, `favoriteURL`/`manageaction` flows, MPStorage/bookmarks, smiley search parse & query building, entity decoding of attribute values, non-UTF-8 responses, redirects, the real form field set, double-post protection.

---

## 7. Quirks, workarounds, visible bugs, dead code

**Bugs / risks (new code)**
- **B1 — attribute values are not entity-decoded.** `parseInputFields` returns raw attribute text (`ReplyService.swift:311-341, 557-577`). Hidden/text fields such as `sujet` with `&amp;`, `&quot;`, `&#039;` are re-posted still encoded (double-encoded on the wire) and shown raw in the composer (`fetchComposerContext` → `composerSubject`). Legacy used libxml2 which decodes. Likely real on MP-reply/edit/new-topic subjects; unverified on live pages.
- **B2 — emoji / non-Latin-1 not stripped** (legacy `removeEmoji`). Effect on the server (mojibake, truncation, rejection) unverified; legacy removal suggests there was a problem.
- **B3 — edit/reply merges the fetch URL's query items into the POST** (`:149-157`) and **always overrides the form's `hash_check`** (`:164-166`); legacy did neither.
- **B4 — success heuristic is looser than legacy**: any `meta refresh` ⇒ success even if a `.hop` with a link is present (`:681-695`); and a page with no `.hop` and no refresh ⇒ rejection with `nil` message. For poll vote the opposite default (no `.hop` ⇒ success, `PollData.swift:79-84`). Needs captured error pages.
- **B5 — no post-timeout recovery**: if the POST succeeds but the response is lost, the user sees an error and may re-post (legacy at least warns "Votre message a peut être été posté malgré tout", `AddMessageViewController.m:631`).
- **B6 — regex HTML parsing**: lazy `</form>`/`</select>`/`</div>` matches, attribute regex `attribute\s*=` matches inside other attribute names (`data-name=`, `username=`), `selected` matched anywhere in the `<option>` tag, only the first `hop` form, case-sensitive literals (`class="hop"` fallback). Replace with SwiftUI-free SwiftSoup parsing.
- **B7 — decode heuristic UTF-8→Latin-1**: an ISO-8859-1 page that happens to be valid UTF-8 would be mis-decoded; use the declared charset (needs fixture to know it).
- **B8 — AQ pre-check is a substring search** on the whole body (`MessagesView.swift:335`).
- **B9 — Smiley keyword fetch and smiley search use `URLSession.shared`** (shared cookie jar, no timeout tuning); duplicated code in `AnswerView.swift:762` and `MessagesView.swift:3322`.
- **B10 — `Task.sleep(nanoseconds:)`, `DispatchQueue.main.async`, `URLSession.dataTask` closures** in popups (`AnswerView.swift:705, 849`; `MessagesView.swift:1947-1963`) — convention violations, irrelevant for the port.
- **B11 — Edit sends the form's `delete` input** (see 2.3), unlike legacy.
- **B12 — `Content-Type` for poll vote lacks charset, response decoded UTF-8 only.**
- **B13 — MPStorage lost-update race** (2.10) and main-thread blocking.

**Duplication**
- `ReplyService.swift` repeats the same helpers: `parseHopMessage` ×4 (579/843/1242/1619), `decodeHTML` ×4, `extractHopFormHTML` ×3, `parseInputFields` ×3, `parseSelectFields` ×2, `attributeValue` ×3, `parseFormAction` ×3 (one variant for `modo.php`), `isLoggedOutForm` ×4 in 3 slightly different versions, `urlEncodedForm`/`escapeFormComponent` ×3 (+ `Favorites.swift:97-103`, `PollData.swift` `percentEncoded`, `MessagesView` `legacyPercentEncode`), `decodeHTMLEntities` ×4 with **different entity lists** (Reply/Quote: with `&#034;`, `&#34;`, `&#x22;`; Deletion/Alert: without — so a numeric-entity quote in a deleted message's text is posted back undecoded), `queryParameters` ×2, `defaultSubmitURL` ×3. `postReply(message:topicURL:)` is declared in the protocol extension *and* the class (`:49-53`, `:209-211`). ~1,000 of the 1,399 lines before the rehost block are copy-paste.
- Smiley keywords fetch: 2 copies. Cookie-jar session creation: 4 copies (`:116-136, 756-765, 943-951, 1415-1423`).

**Dead / unused code**
- `ReplyComposerState`, `ReplyComposerPanel` (tests only), `ReplyQuoteDraftMerger`, `ReplySmileyCatalogLoading.loadFavoriteSmileys`, `ReplySmileyCacheBridge.favoriteSmileyEntries`, `ReplyImageUploadError.invalidUploadURL`.
- Legacy: `RehostImage.loadDataRehost`/`fetchContentCompleteRehost` (reho.st), `SmileyAlertView.addToFavoriteSmileys` commented `addperso.php` POST, `NewMessageViewController` (empty), `isDeleteMode` stub returning NO in the base class (`AddMessageViewController.m:508-511`), UIAlertView delegate code.

**Legacy quirks worth preserving or consciously dropping**
- `lowercaseString` on quote and alert URLs (`QuoteMessageViewController.m:36`, `AlerteModoViewController.m:40`) — probably a workaround for mixed-case params in decoded URLs; test with fixtures before dropping.
- Quote decoding alphabet `0A12B34C56D78E9F` and 20-char prefix skip (2.2a).
- `MsgIcon` radio only if `checked`; checkbox "0/1" encoding; the four flags only when "1".
- Legacy POST loop ignores `delete` outside delete mode.
- 1 h cookie lifetime for multi-quote; cookie must be on `.hardware.fr`.
- `succès` / `destiné` French substring checks in MPStorage (locale-dependent site text).
- Legacy multi-account: posts with the *selected* account's cookies (`selectCompte` picker, disabled in edit mode `EditMessageViewController.m:17`); new app posts as main account only — a functional gap if multi-account posting is wanted.

---

## 8. Proposed lots

Numbering is provisional (LOT-D1…); to be renumbered by the LOT-000 synthesis. "Fixtures" refers to §9.

| Lot | Module | Scope | Difficulty | Depends on | Fixtures |
|---|---|---|---|---|---|
| **D1 — Hop form parser** | HFRParsing (+ HFRModels `ForumForm`, `FormField`) | SwiftSoup parse of `<form name="hop">` → `ForumForm {action, fields[name,value,type,checked], selects[options,selected], textareaContent, dynamicSmileys[], isSubjectEditable, subcategories[], dest, sujet}`; entity-decoded; rules of §2.1 (checkbox 0/1, radio checked, select first/selected, `MsgIcon`, flag dropping policy as a *separate* pure function). Also a "moderation form" variant (`action~modo.php`). Replaces `ReplyService.swift` 311-555 ×3. | medium | HFRModels | F1-F8, F11 |
| **D2 — Hop response classifier** | HFRParsing | Pure `HopResponse` classifier: `{kind: success/rejected/loggedOut/alreadyAlerted/…, message, refreshURL, refreshAnchor}` from HTML + status; one place for `.hop` text extraction, meta refresh, login detection (stricter variant), `succès` check for MPStorage. Differential test: legacy rule (hop without `a/input`) vs new rule on every captured response. | medium | HFRModels | R1-R10 |
| **D3 — Post-form engine (reply/new topic/MP/edit/delete)** | HFRNetwork | `ForumWriter`: GET form → apply overrides → POST (UTF-8 form-encoding incl. `\r\n`, emoji policy decided in ADR) → classify. Typed API: `reply`, `editMessage`, `deleteMessage`, `newTopic`, `newPrivateMessage`, `replyPrivateMessage`; `ComposerContext` fetch (subject/dest/subcats). Host allow-list for form actions; hash_check policy (form value first, stored fallback). Double-post guard + "maybe posted" error. Mock transport. | difficult | D1, D2, session/cookie lot (account cookies, `hash_check`) | F1-F8, R1-R8 |
| **D4 — Quote engine** | HFRParsing (decoder, selection formatter, textarea extraction) + HFRNetwork (quote template GET, multi-quote cookie store) | `decodeSpanUrl` (alphabet+prefix) as a shared util *coordinated with the message-page lot*; quote template fetch; `ReplyQuoteSelectionFormatter` port + `splitQuote`; multi-quote cookie read/write/toggle (`quotes<a>-<b>-<c>`, `\|id`, 1 h, `.hardware.fr`). | medium | D1, message-page lot (provides quoteJS/quoteURL), network cookies | F2, F3, C1 |
| **D5 — Moderator alert** | HFRNetwork (+ D1 variant, D2) | prepare/submit alert (`modo.php`), already-alerted state, mailto fallback value object. | easy | D1, D2 | F9, R9 |
| **D6 — AQ client** | HFRNetwork | `getAlertesByTopic` + `addAlerte` with byte-exact body encoding, response `"1"`; parse the `alertes` listing properly instead of substring; configurable base URL; ADR on sending pseudo to a third party. | easy | – | A1-A3 |
| **D7 — Topic flags & favourites writes** | HFRNetwork (+ D2) | `addflag` GET, `manageaction.php` delflags POST, mark-unread links; same-host validation; hop message extraction. Coordinate with list lot for `aURLOfFlag`. | easy-medium | D2, session | R11-R13 |
| **D8 — MPStorage client + schema** | HFRNetwork (transport: find MP by title across pages, read JSON, create, update with `numreponse`, `succès` check) + HFRModels (`MPStorageDocument`: blacklist, bookmarks, mpFlags, versioning) + HFRStorage (cached storage topic id per pseudo alias, local copy) | Port read-modify-write with retry-on-conflict (re-read before write, merge by `numreponse`/`post`), off-main-thread; keep wire-compat with other clients (`sourceName`, `lastUpdate`). | difficult | D1/D2, MP list parser (list lot), session | M1-M7 |
| **D9 — Smileys** | HFRModels (catalogue from `commonsmile.plist` → JSON resource) + HFRParsing (search result `<img>` list, `dynamic_smilies`, wiki `keywords0`) + HFRNetwork (search, wiki detail) + HFRStorage (app favourites, search history, with **migration** of `smiley_favorites_cache2` / `smileysSearch.plist` if user data matters) | AND/OR query builder (`+word` semantics) as pure function; no UIKit/GIF decoding (app layer). | easy-medium | – | S1-S4 |
| **D10 — Image rehost client** | HFRNetwork (Chevereto multipart upload, JSON → `RehostedImage`, error mapping, injectable base URL/key) + HFRModels (`RehostedImage`, BBCode snippet formatter) + HFRStorage (upload history, prefs) | Resize/JPEG stays in the app (UIKit). Key from config, never in source. Decide on keeping legacy-history migration. | easy | – | I1-I3 |
| **D11 — Poll vote** | HFRParsing (poll block → form model) + HFRNetwork (`vote.php`) | Needs real fixtures to settle radio value semantics. Coordinate with message-page lot (poll HTML). | medium | D2 | P1-P4 |
| **D12 — Drafts** | HFRStorage | `DraftStore` keyed by target (reply topic / new topic forum / MP recipient), ephemeral-composer rule, one-time migration of `brouillon`/`composerDraftText`. | easy | – | – |
| **D13 — HFR-PROTOCOL write chapter** | docs | Consolidate §2 facts into `docs/HFR-PROTOCOL.md` once fixtures confirm them (field list of the real forms, redirect shapes, error texts, charset). | easy | D1-D3 fixtures | all |

Suggested order: D1 + D2 (unblocks everything, purely offline) → D3 → D4/D5/D7 → D9/D10/D12 (parallel, small) → D6 → D11 → D8 (hardest, depends on MP list parsing and cross-client semantics).
Model routing per AGENTS.md §6: D3 and D8 Opus (reply posting / network), D1/D2 Sonnet with Opus review, D5/D6/D9/D10/D12 Sonnet.

---

## 9. Fixtures to capture (anonymised, per `docs/FIXTURES.md`)

Forms (GET), each in raw bytes (to settle charset) — **F**:
- F1 topic page `forum2.php` bottom fast-answer form (`#repondre_form`, `form[name=hop]`) logged in; F1b same logged out.
- F2 `message.php?…&cat=13&post=…` plain reply page (empty textarea).
- F3 quote page: single quote; F3b multi-quote with the `quotes…` cookie set (2-3 posts); F3c quote of a post that itself quotes (nested `[quotemsg]`).
- F4 edit page for a normal post; F4b edit of the first post of own topic (has `sujet`, `subcat`, flag checkboxes `have_sondage/allowvisitor/sticky/sticky_everywhere`); F4c edit with `&amp;`/`&quot;` in subject.
- F5 new-topic page (`#md_btn_new_topic` target) with the subcategory `<select>` (selected + unselected variants).
- F6 new-MP page (`cat=prive&dest=…`); F6b MP reply page (hidden `dest`/`sujet`).
- F7 delete page (= edit page of a non-first post).
- F8 pages containing `dynamic_smilies` (0, 3, with special chars).
- F9 moderation alert page `user/modo.php?…`: not yet alerted (form) and already alerted (hop with link).
- F10 the message-page HTML around one post showing the obfuscated quote/edit class strings, `addflag`, `modo.php`, MP and `quoter(...)` links (shared with the message-page audit) + the decoded expected URLs.
- F11 the same forms with a **poll** present (before/after vote).

Responses (POST) — **R**: R1 reply OK (full HTML incl. meta refresh), R2 reply rejected: flood/too fast, R3 empty message, R4 topic locked/forbidden, R5 invalid/expired `hash_check`, R6 logged out, R7 edit OK, R8 edit by non-owner, R9 delete OK and delete of a post already deleted, R10 new topic OK and new topic without subject, R11 alert sent / duplicate, R12 `addflag` GET OK and already-flagged, R13 `manageaction.php` delflags response, R14 poll vote OK / invalid. Also one **HTTP 302/5xx/maintenance** page each.
MPStorage — **M**: M1 MP list pages containing the storage MP (title with and without `[non lu]`), M2 storage topic page (`messagetable`, `para<N>` div), M3 storage JSON samples (empty, with bookmarks, with mpFlags, malformed), M4 "destiné" error page, M5 successful create/update responses (`succès` wording), M6 failed update, M7 MP list multi-page.
Smileys — **S**: S1 `message-smi-mp-aj.php?findsmilies=…` with 0/1/many results and with `+` AND-form, S2 `wikismilies.php?detail=…`, S3 `commonsmile.plist` as JSON resource, S4 special-char codes.
Images — **I**: I1 Chevereto success JSON (use `RehostImage.m:236-297` as base, real `img3` response), I2 error JSON (too big, bad key, wrong format), I3 non-JSON/HTML error.
AQ — **A**: A1 `getAlertesByTopic` response with/without the post, A2 `addAlerte` responses (`1`, error codes), A3 empty topic.
Cookies — **C**: C1 request-capture of the `quotes…` cookie as set by the site's own JS (name/value/expiry/domain).
Extra: raw request captures (proxy) of one real reply POST, one edit POST (to learn `bdd.php` vs `bddpost.php`), one new-topic POST: the byte-exact body is the oracle for D3 (field set + order + charset).

---

## 10. Open questions

1. **Server charset**: what `Content-Type`/`<meta charset>` do HFR pages and POST handlers use? Is `charset=utf-8` in the POST honoured, and how are characters outside Latin-1 (emoji, `€`, `œ`) stored? (decides emoji policy and decoding; §2 intro, B2, B7).
2. Exact **field list and order** of the real reply/new-topic/MP/edit forms, and the **form `action`** for edit (`bdd.php`?) and delete.
3. Is the form's own `hash_check` always fresh and equal to the stored one? Why does the app override it (account switching)?
4. Real **flood / rate-limit** page and wording; HTTP status of rejections; any `Retry-After`.
5. Does the server really consume the `quotes…` cookie for multi-quote, with which exact cookie name arguments (`quoter('hardwarefr', cat, post, id)` → cat? post?), and does the cookie have to be sent on `message.php` only?
6. Why lowercase the quote/alert URLs in legacy? Any case-sensitive parameter?
7. What do `addflag`/`delflag`/`nonlu` hrefs look like (hash in URL?) and what do they return on success vs duplicate?
8. Poll vote: real radio/checkbox `value`s, response page, and whether the app's index-based value is right.
9. Chevereto: real size/dimension limits, accepted formats, API key ownership/rotation, whether `format=json` is needed, whether EXIF is stripped by our re-encode.
10. AQ: does `getAlertesByTopic` return structured data to parse instead of substring matching? Is the service still maintained (legacy comments mention an older `toyonos.info` host)? Is sending the pseudo acceptable under the new app's privacy policy?
11. MPStorage: must the new app remain wire-compatible with HFR+/other clients (shared title/recipient/JSON schema)? Who owns the `MultiMP` account? Is the `bdd.php` update form stable? Is optimistic concurrency feasible (compare `lastUpdate`)?
12. Multi-account posting: required for the new app (legacy posted with the selected account; new posts as main account only)?
13. `HFRswift/Wrapped/MessagesTableViewController.m` target membership: pbxproj says SuperHFRplus only, while source comments describe Swift-target behaviour — confirm it is not compiled into HFRswift (unverified).
14. Are there other write entry points not found by `grep` (e.g. report-to-moderators from a profile, topic subscription "suivi", "mark as read on the whole forum", private-message deletion)? A full list of POST/GET-with-side-effect URLs should be cross-checked with the network audit.
