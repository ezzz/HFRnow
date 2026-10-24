# Audit C — Topic/message page parsing and rendering

Legacy reference: `HFRnow` at commit `2440d79` (read-only). All paths below are relative to the legacy repo root unless stated.
Scope: HTML of a topic page (`forum2.php?...` / `/hfr/.../sujet_N_P.htm`) to messages, page metadata and displayed HTML in the `WKWebView`.
Boundaries: networking, topic/forum list parsing, reply posting, blacklist/whitelist storage and account management are covered by other audits. They are mentioned only where they touch this area.

Conventions: "live" = compiled into the `HFRswift` target and reachable from the SwiftUI app. "legacy-only" = compiled only into `SuperHFRplus`. "unverified" = inferred from code, no HFR HTML available in the repo to confirm (the legacy repo contains no captured HFR page, see [Fixtures](#8-fixtures-to-capture)).

---

## 1. Scope

### 1.1 File table

Target membership comes from `SuperHFRplus.xcodeproj/project.pbxproj`. The `HFRswift` `PBXSourcesBuildPhase` is `15B0AA81…` (pbxproj:5710). The legacy target is `SuperHFRplus` (`CA7C70B9…`).

| File | Lines | HFRswift | SuperHFRplus | Status | Responsibility |
|---|---|---|---|---|---|
| `HFRswift/Wrapped/ParseMessagesOperation.m` (+`.h`, 42) | 559 | yes (pbxproj:5746) | yes | **live** (only `parseData:` / `parseData:filterPostsQuotes:...`) | HTML to `LinkItem[]` + title + last page number |
| `HFRswift/Wrapped/LinkItem.m` (+`.h`, 97) | 305 | yes (5750) | yes | **live** | Message value object + `toHTML:isMP:` (template fill and all content rewriting) |
| `HFRswift/Wrapped/MessagesTableViewController.m` (+`.h`) | 3371 | **no** | yes (pbxproj:1419, 5808) | **legacy-only** (see 1.2) | Legacy UIKit topic screen; origin of most logic now copied into the `ObjCTopic*` workers |
| `Classes/ObjCTopicPageWorker.m` (+`.h`) | 210 | yes (5727) | no | **live** | Fetch + parse + render of one topic page; page metadata, poll, search form |
| `Classes/ObjCTopicHTMLRenderer.m` | 107 | yes (5723) | no | **live** | Page shell: `<head>`, scripts, CSS variables, inline JS |
| `Classes/ObjCTopicHTMLRenderContext.m` (+`.h`) | 4 | yes (5722) | no | live (DTO) | Inputs of the shell renderer |
| `Classes/ObjCTopicMessageContentBuilder.m` | 50 | yes (5725) | no | live | Concatenate `toHTML` of all items + "new messages" separator + anchor resolution |
| `Classes/ObjCTopicMessageContentResult.m` (+`.h`) | 4 | yes (5724) | no | live (DTO) | `messagesHTML`, `resolvedAnchor` |
| `Classes/ObjCTopicToolbarHTMLBuilder.m` | 38 | yes (5721) | no | **mostly dead** (only the "Résultats suivants" branch is reachable) | HTML page-navigation toolbar |
| `Classes/ObjCMessageActionsBuilder.m` | 105 | yes (5720) | no | live | `LinkItem[]` to per-message action dictionaries consumed by Swift |
| `Classes/ObjCFilteredPostsRendererWorker.m` (+`.h`, 14) | 69 | yes (5726) | no | live | Same pipeline for the "filtered posts" feature |
| `Classes/FilterPostsQuotes.m` (context) | 386 | yes (5737) | yes | live for `fetchFilteredPostsForTopic:...` (Classes/FilterPostsQuotes.m:202-312); the rest is `#if !APP_SWIFT` | Multi-page loop feeding `ParseMessagesOperation` in filter mode |
| `SuperHFRplus/Helpers/RangeOfCharacters.m` (context) | 381 | yes (5748) | yes | live | `decodeSpanUrlFromString`, `stringByDecodingXMLEntities` |
| `SuperHFRplus/Vendor/HTMLParser/HTMLParser.m` / `HTMLNode.m` | 116 / 478 | yes (5754/5755) | yes | live | libxml2 wrapper |
| `SuperHFRplus/Vendor/RegexKitLite/RegexKitLite.m` | 2636 | yes (5753) | yes | live | ICU regex category on `NSString` |
| `SuperHFRplus/Assets/HTML/templatev2.htm` | 17 | resource (pbxproj:4709 `15316C0B…`) | yes | live | One-message HTML template |
| `SuperHFRplus/Assets/HTML/style-liste-light.css` | 1077 | resource (4708) | yes | live | The only stylesheet linked by the renderer (dark = CSS variables) |
| `jquery-2.1.1.min.js`, `jquery.doubletap.js` (104), `jquery.base64.js` (1782 bytes) | – | resources (4703, 4711, 4718) | yes | live (loaded by every page) | See 5.2 |
| `HFRswift/Swift/MessagesView.swift` (`WebView`, popup, cookies) | 6580 | yes (synchronized group `Swift`) | no | live | SwiftUI screen + `WKWebView` host |
| `HFRswift/Swift/Common.swift` (`TopicPageMessageActions`, `ObjCTopicPageLoader`, `MessageWebActionHandler`, `TopicPageURLRouting`) | 3215 | yes | no | live | Swift bridge to the ObjC workers, URL-scheme router |
| `HFRswift/Swift/PollData.swift` | 391 | yes | no | live (already Swift, regex based) | Poll HTML to `PollData`, vote POST |
| `HFRswift/Swift/FavoritePostFilterService.swift` | 319 | yes | no | live | Swift bridge to `FilterPostsQuotes` + `ObjCFilteredPostsRendererWorker` |

Swift files in `HFRswift/Swift` are included by the filesystem-synchronized group (pbxproj:2671), not by the Sources phase.

### 1.2 MessagesTableViewController: live vs dead

`MessagesTableViewController.m` is **not in the `HFRswift` Sources phase** (grep of the phase: 0 hits). It lives in the `HFRswift/Wrapped` folder, but only `SuperHFRplus` compiles it. Consequences:

- Nothing in `HFRswift` can run it. `Classes/FilterPostsQuotes.m:60-67,324-384` references it, but those parts are guarded by `#if !APP_SWIFT`; `APP_SWIFT=1` is set for the Swift target (pbxproj:5967 and 3 other configurations).
- `HFRswiftTests/ObjCWrappedClassesSmokeTests.swift:5-14` still asserts that `NSClassFromString("MessagesTableViewController")` instantiates inside the `HFRswift` test host. Since the class is not compiled there, this test most likely fails (unverified, not run).
- The file is the **historical source** of everything now copied into the live workers. It is the best "oracle for intent", not an oracle for behaviour:

| Logic in MessagesTableViewController | Where it went in HFRswift |
|---|---|
| `manageLoadedItems:` (1593-1750): build messages HTML + toolbar + shell | `ObjCTopicPageWorker handleResponseData:` (103-146) with `ObjCTopicMessageContentBuilder` / `ObjCTopicHTMLRenderer` |
| `setupFastAnswer:` (1544-1585): hidden inputs of form `hop`, flag detection (`delflag`, `flagn0.gif`, `nonlu`) | `parseMetadataFromBody:` (148-164): only the `hop` inputs and `nonlu` survive. **Topic flag state (`delflag`, red flag) is not extracted in the live path** (unverified whether Swift gets it elsewhere, area B) |
| `setupPoll:` (828-845) | `ObjCTopicPageWorker.m:159-162`; MTVC copy at 815-826 |
| `setupIntrSearch:` (847-921) | `searchInputDataFromBody:` (166-179), without the UIKit side effects |
| `loadDataInTableView:` (923-972): answer URL, MP badge from `class="none"` table (`td` count == 3) | answer URL kept (156-157); **MP badge parsing dropped** (MP count comes from elsewhere, area MP) |
| `setupPageToolbar:` (598-717): title, pager. The pager code is commented out | title + `iLastPageNumber` moved into `ParseMessagesOperation.m:491-507` |
| `swiftMessageActionsByIndex` (3194) and `swiftAbsolute*` helpers (3202-3288) | `ObjCMessageActionsBuilder.m` (the MTVC copies are redundant) |
| `EcrireCookie/LireCookie/EffaceCookie`, `actionCiter:` (2666-2750) | `MessagesView.swift:1852-1935` |
| `textQuote*` (1045-1082) | `MessageWebView.requestTextQuote` (MessagesView.swift:589-640) |
| `decidePolicyForNavigationAction` (1862-2030) JS-scheme router | `MessageWebActionHandler` (Common.swift:2031-2260) |
| `performTopicSearchWithParams:` (3317-3371) | `Classes/ObjCTopicSearchWorker.m` |
| `userTextSizeDidChange`, `userThemeDidChange` (2822-2927) | `WebView.Coordinator.applyTextSizeIfNeeded/applyThemeIfNeeded` |

Nothing in this file needs porting except as cross-check (section 6 notes the two behaviours that were lost).

### 1.3 Dead or unused code inside live files

- `ParseMessagesOperation`: `main`, `initWithData:index:reverse:delegate:`, the delegate protocol, `index`, `reverse`, `workingEntry`, `iFirstPageNumber`, `sFirstPageURL`, `sLastPageURL`, and the commented pager block (`.m:509-552`). Only `parseData:` is called (`ObjCTopicPageWorker.m:110-112`, `FilterPostsQuotes.m:128-131,280-283`).
- `LinkItem` properties never set by the parser: `flagUrl`, `typeFlag`, `lastPostUrl`, `lastPageUrl`, `viewed`, `rep`, `messageNode`, `textViewMsg`, `messageAuteur`, `isBL` (LinkItem.h:55-92). `toHTML:isMP:` ignores `isMP` (LinkItem.m:23).
- `ObjCTopicToolbarHTMLBuilder`: the page buttons (22-35) need `pageNumber > 0`, but the only caller passes 0 (`ObjCFilteredPostsRendererWorker.m:44-50`), and `ObjCTopicPageWorker` hard-codes `toolbarHTML = @""` (139). Only the "Résultats suivants" link (14-16) is reachable.
- `ObjCTopicHTMLRenderContext.refreshButtonHTML`, `customFontSizeCSS`, `searchActive` are always empty/`NO` in the live callers (`ObjCTopicPageWorker.m:136-140`, `ObjCFilteredPostsRendererWorker.m:52-56`). Font size is applied by Swift JS (MessagesView.swift:1448-1470). The `ios7 searchintra` body class is therefore never applied, although `style-liste-light.css` has `.ios7.searchintra` rules (unverified visual impact on in-topic search results).
- `ObjCTopicMessageContentResult.resolvedAnchor` is written back to a private property (`ObjCTopicPageWorker.m:134`) that is not exposed in `ObjCTopicPageWorker.h`. The Swift side scrolls with its own `anchor` (MessagesView.swift:1062-1100). The "closest following post" logic (ObjCTopicMessageContentBuilder.m:27-46) is dead; only its side effect (separator placement) is live.
- `display_images` branches `"no"` and `"wifi"` of `toHTML` (LinkItem.m:169-226) are unreachable: `HFRplusAppDelegate.m:115-116` forces `display_images = "yes"` at every launch, and no Swift settings screen exposes the key.

---

## 2. Pipeline overview

```
MessagesView (SwiftUI)                                          MessagesView.swift:3068 loadPage / 3139 loadDirectURL
  └─ ObjCTopicPageLoader.fetchTopicPage(url, anchor)            Common.swift:1781 (selectors invoked by name via NSClassFromString)
       └─ ObjCTopicPageWorker.fetchContentForTopicURL           Classes/ObjCTopicPageWorker.m:78
            ├─ ASIHTTPRequest GET {ForumURL}{url}               (network, area A)           k.m:13,37 => https://forum.hardware.fr
            ├─ HTMLParser(initWithData)  [libxml2 htmlReadDoc]                              ObjCTopicPageWorker.m:105
            ├─ ParseMessagesOperation parseData:  -> LinkItem[] + topicName + iLastPageNumber   ParseMessagesOperation.m:107
            │      (avatar download/cache with ASIHTTPRequest, waits in waitForPendingAvatarLoads)
            ├─ parseMetadataFromBody: hop inputs, repondre_form URL, nonlu, poll, transsearch form   ObjCTopicPageWorker.m:148
            ├─ ObjCTopicMessageContentBuilder -> for each item LinkItem.toHTML (templatev2.htm + regex rewriting)
            ├─ ObjCTopicHTMLRenderer -> full HTML page string (shell + theme variables + JS)
            └─ completion(html, answerURL, currentPage, maxPage, error)  [main queue]
  ├─ Swift reads KVC: sNavigationViewTitle/_topicName, swiftHasPoll, swiftPollIsNewVote, swiftPollHTML, swiftSearchInputData
  │    and swiftMessageActionsByIndex (ObjCMessageActionsBuilder)               Common.swift:1800-1836
  ├─ PollHTMLParser.parse(swiftPollHTML) -> PollData                            PollData.swift:117
  ├─ OfflineStorageTopicPageRenderer.render: write topic-<UUID>.htm in Caches/cache   Common.swift:1962
  └─ WebView.updateUIView -> WKWebView.loadFileURL(file, allowingReadAccessTo: Caches/cache)   MessagesView.swift:976
       ├─ page JS -> navigation to custom URL schemes -> MessageWebActionHandler -> MessageWebAction     Common.swift:2031
       ├─ WKUserScripts -> WKScriptMessageHandler "scrollState", "textInteractionState"     MessagesView.swift:813-897,1169
       └─ evaluateJavaScript: theme variables, message style, font size, anchor scroll, text selection

Filtered posts (Favoris "Filtrer les posts"):
  FavoritePostFilterService.performFilter -> FilterPostsQuotes.fetchFilteredPostsForTopic (loops pages, ParseMessagesOperation in filter mode, stops at 40 posts)
  -> ObjCFilteredPostsRendererWorker.renderFilteredPosts (same builder + renderer + actions builder)     FavoritePostFilterService.swift:132-237
```

Resource staging: `OfflineStorage copyAllRequiredResourcesFromBundleToCache` (Classes/OfflineStorage.m:439-473, called at launch from `HFRplusAppDelegate.m:84`) copies CSS/JS/images and default smileys from the bundle to `Caches/cache/`, so that the generated file can reference them with relative URLs. Avatars live in `Caches/cache/avatars/` (ParseMessagesOperation.m:124-132), which is inside the read-access root.

---

## 3. Parsing rules

HTML parser semantics that every rule below depends on (`SuperHFRplus/Vendor/HTMLParser/HTMLNode.m`):

- `findChildWithAttribute:matchingName:allowPartial:` (HTMLNode.m:232-273): depth-first, document order, starts at the **children** of the receiver. `allowPartial:NO` means the **whole attribute value equals** the string (so `class="a b"` never matches `"a"`); `YES` means `strstr` substring.
- `findChildrenWithAttribute` (105-142): same matching, returns all matches (descendants of matches are also visited, up to the `break` structure at 133-141).
- `firstChild` / `children` include text nodes, so positional navigation is sensitive to how libxml2 keeps or drops whitespace (unverified, depends on real markup).
- `allContents` = `xmlNodeGetContent` (text of the subtree, entities decoded). `rawContentsOfNode` = `htmlNodeDumpFormatOutput` with `format=1` (HTMLNode.m:399-416). Output is **libxml2's serialization**, not the original bytes: normalized attribute quoting, attribute order preserved, no `/>` on void tags, non-ASCII text escaped as named entities (evidence: `MessagesView.swift:4056` looks for `aucune r&eacute;ponse`), indentation newlines added.
- `setAttributeNamed` rewrites in place; `addAttributeNamed` is `xmlNewProp`, which **appends a second attribute even if one with the same name exists** (HTMLNode.m:52-59).

### 3.1 Message container structure relied upon (inferred from selectors)

All names below are exact legacy selectors. The surrounding structure is **inferred**, to be confirmed with fixtures.

```
[optional wrapper class="messagetabledel"]          deleted message          ParseMessagesOperation.m:153
  element class="messagetable"                      one per message          :137
    messageNode = firstChild of messagetable (a <tr class="message ..."> ? unverified)   :145
      firstChild.firstChild  = <a name="t<postId>">  postID, keeps the "t" prefix        :160
      .s2                      author (allContents)                          :149,168
      .avatar_center > firstChild[src]   avatar URL                          :176,453
      id contains "para"       content node (raw inner HTML)                 :177,324
      .messCase2               content cell; children[1] if <a> is prepended :365-368
      .toolbar                 date text                                     :398
      .edited                  "Message cité N fois" / "Message édité par ..." :334
      .citation / .oldcitation quote blocks; .Topic inside = "<author> a écrit :"   :191-200
      img[alt=answer|edit|profil]'s parent   quote / edit / profile actions    :371-381
      a[href contains /user/modo.php]  alert; a[href contains addflag]  favorite flag; a[href contains /message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=]  MP   :377-390
      element[onclick contains "quoter('hardwarefr'"]  multi-quote JS         :386
```

The `messagetable` for the first element of a page whose class is `messagetable` may be a "Reprise de la page précédente" copy (comment at :141). In normal mode it is **kept** (no skip); only filter mode drops index 0.

### 3.2 Fields extracted per message (`LinkItem`)

| Field | Rule (ParseMessagesOperation.m unless noted) |
|---|---|
| `postID` | `messageNode.firstChild.firstChild[name]` (:160). Value like `t1234567` (the code does `substringFromIndex:1` at :213 and rewrites `#t[0-9]+` at :235). |
| `isDel` | `messageNode.parent.parent[class] == "messagetabledel"` (:153). |
| `name` | text of first `.s2` descendant, trimmed (:149,168-169). Skipped entirely when equal to `Publicité` (:172-174). Special display names: `Modération` (LinkItem.m:45). |
| `imageUI` (avatar) | `[src]` of the first child of `.avatar_center` (:453). Downloaded to `Caches/cache/avatars/<md5(lowercased name), 32 hex>` (:423-429), no extension. Re-downloaded if the file is older than 24 h (:440) or absent (:449). Failure sets `imageUI = nil` even when a stale file existed (:464-467). Downloads run on an `NSOperationQueue` and are awaited by `waitForPendingAvatarLoads` (:37-39, called at ObjCTopicPageWorker.m:112). Timeout set globally via `[ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutAvatar]` (:121). |
| `messageDate` | allContents of `.toolbar`; ICU regex `.*([0-9]{2})-([0-9]{2})-([0-9]{4}).*([0-9]{2}):([0-9]{2}):([0-9]{2}).*` replaced by `$1-$2-$3 $4:$5:$6` (:400-401), i.e. string `dd-MM-yyyy HH:mm:ss` (French display date, kept as string, no `Date`). `""` if no toolbar text (:404). `.` does not match newlines, so on multi-line text only the matching line is rewritten and the rest is kept (unverified). |
| `dicoHTML` (content) | `rawContentsOfNode(contentNode)` where `contentNode` = first descendant with `id` containing `para` (:177,324). Taken **after** quote class rewriting and video marking (sections 4.1/4.5). If `messCase2.children[1]` is an `<a>` its raw HTML is prepended (:365-368, comment "recherche": search-result anchor). |
| `quotedNB` | `.edited` allContents matched against `.*Message cité ([^<]+) fois.*` (capture 1, trimmed, XML entities decoded) (:336-337). |
| `quotedLINK` | `href` of the first `<a>` in `.edited` (:339). |
| `editedTime` | `.edited` allContents matched against `.*Message édité par ([^<]+).*` (:350-351). Despite the name, the capture is "<pseudo> le <date>" text (unverified). |
| `urlQuote` | `class` attribute of the **parent** of `img[alt=answer]` (:371-372). It is an **obfuscated URL** (see 3.4). |
| `urlEdit` | `class` of the parent of `img[alt=edit]` (:374-375). Obfuscated. Present only for messages the user may edit. |
| `urlAlert` | `href` of the first element whose `href` contains `/user/modo.php` (:377-378). Plain, relative. |
| `urlProfil` | `href` of the parent of `img[alt=profil]` (:380-381). |
| `addFlagUrl` | `href` containing `addflag` (:383-384). "Add a favorite flag on this message" (used as `favoriteURL`). |
| `quoteJS` | `onclick` attribute of the first element whose `onclick` contains `quoter('hardwarefr'` (:386-387). Shape from the legacy consumer: `quoter('hardwarefr','<a>','<b>','<postNum>'); return false;` (MessagesTableViewController.m:2720-2731: drops 7 chars and `"); return false;"`). |
| `MPUrl` | `href` containing `/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=` (:389-390). The pseudo is in `dest=`. |
| `url`, `iPage` | Only in filter mode: `https://forum.hardware.fr` + topic URL, `&page=N` replaced by the page being parsed, `#t[0-9]+` replaced by `#<postID>` (:228-237). Regexes assume the `?...&page=N#tN` URL form; the `/hfr/.../sujet_N_P.htm` form is not handled (unverified). |

Not extracted (but needed by the new UI): poll per message (polls are page-level), signature as separate field (it is cut in `toHTML`, 4.4), per-message images/links/smileys as structured data (only rewritten HTML), moderation reason, spoiler contents, avatar URL as URL (only the cached path).

### 3.3 Page-level data

| Datum | Rule |
|---|---|
| Topic title | `findChildWithAttribute class contains "fondForum2Title"` then first `h3`, `allContents` (ParseMessagesOperation.m:491-495). Only set when `topicName` is empty. Published as `sNavigationViewTitle` / `_topicName` (ObjCTopicPageWorker.m:114-115); Swift trims (Common.swift:1814-1819). |
| Max page | `findChildWithAttribute class contains "fondForum2PagesHaut"`, inside it the first element with `class == "left"`, then `children.lastObject.contents.intValue` (ParseMessagesOperation.m:498-507). `maxPage = MAX(iLastPageNumber, 1)` (ObjCTopicPageWorker.m:120). Unverified whether the last child can be a non-numeric node. |
| Current page | **Not parsed from HTML.** Derived from the *effective* URL after redirects (`ASIHTTPRequest.url`): query item `page`, else regex `(?:\?\|&)page=(\d+)`, else `_(\d+)\.htm`, else `1` (ObjCTopicPageWorker.m:14-43,116-119,187-191). A second, slightly different implementation lives in Swift (`TopicPageURLRouting.pageNumber`, Common.swift:2471-2508, pattern `page=(\d+)` not anchored). |
| Answer form URL | `id == "repondre_form"` then first `<a>[href]` (ObjCTopicPageWorker.m:156-157); made absolute with `ForumURL` (142-144). Absent on closed topics (unverified). |
| Hidden fields of the quick-answer form | all `input[type contains hidden]` inside the element `name == "hop"` (:150-155): `cat`, `post`, `p`, `hash_check`... (the exact list is unverified). `cat == "prive"` marks a private-message topic (ObjCTopicPageWorker.m:128, ObjCMessageActionsBuilder.m:17). **`hash_check` is a secret token** (anonymize in fixtures). |
| "Unreadable" flag | any element whose `href` contains `nonlu` (:158) -> `canBeFavorite = NO` (ObjCTopicPageWorker.m:198). |
| Poll | first element with `class == "sondage"`; `hasPoll`; `isNewVote` = contains an `<input>`; raw HTML passed to Swift (:159-162). `PollHTMLParser` (PollData.swift:117-370) then runs ICU regexes: question `<b\|div class="s2">`, options `<li>...<input name=...>...<label>`, hidden fields `<input type="hidden">`, results `div.sondageLeft/.sondageTop/.sondageRight`, footer `div.sondageFooter`, max choices from the text between `</b>` and `<ol type="1"` (a number between spaces). Voting POSTs to `/user/vote.php?config=hfr.inc` (network area). |
| In-topic search form | `form[action contains /transsearch.php]`, keep inputs named `hash_check, p, post, cat, firstnum, currentnum, word, spseudo, filter`; unchecked checkboxes dropped (ObjCTopicPageWorker.m:166-179). |
| Bookmarks / flags | Not parsed in this area. Legacy MTVC read `delflag` (`isFavoritesOrRead`) and `flagn0.gif` (red flag) at MessagesTableViewController.m:1555-1580; not carried over (see 1.2). |
| Message count / "page is empty" | Search "no result" is inferred from `messageActionsByIndex.isEmpty` or text `aucune réponse` (MessagesView.swift:4050-4057). The real HFR markup is `<div class="hop">Désolé aucune réponse…` (comment at :4030, unverified). |

### 3.4 Obfuscated URLs

`urlQuote` and `urlEdit` are the **CSS class** of a link wrapper. They are decoded by `decodeSpanUrlFromString` (SuperHFRplus/Helpers/RangeOfCharacters.m:92-114): drop the first **20** characters, then each pair of characters is one byte, each character being the index in the alphabet `0A12B34C56D78E9F` (high nibble first). The topic-list parser uses the same scheme with a prefix of **12** (`decodeSpanUrlFromString2`, :116; area B). `ObjCMessageActionsBuilder` only decodes when `length > 20`, there is no `/` and no `http` in the string (.m:80-89), wraps the call in `@try`, then absolutizes (70-78). Non-ASCII bytes would be mangled by `%c` (unverified, URLs are probably ASCII).

### 3.5 Derived "actions" dictionary (what Swift consumes)

`ObjCMessageActionsBuilder.actionsByIndexForItems` (ObjCMessageActionsBuilder.m:9-62) returns `[index: [String:String]]`, index = position in the `LinkItem` array (also the DOM `id` of the message `div`). Swift decodes it in `ObjCTopicPageLoader.extractMessageActionsByIndex` (Common.swift:1838-1900) into `TopicPageMessageActions` (Common.swift:1615-1636).

| Key / Swift field | Source |
|---|---|
| `quoteURL` | decoded `urlQuote`, absolute, `&amp;` -> `&` |
| `editURL`, `isOwnMessage` | decoded `urlEdit`; `isOwnMessage = editURL non-empty` (.m:38-46) (so a moderator's edit links make foreign messages "own": unverified) |
| `profileURL`, `privateMessageURL`, `favoriteURL`, `alertURL` | `urlProfil`, `MPUrl`, `addFlagUrl`, `urlAlert` made absolute |
| `avatarImagePath` | cached avatar file path |
| `quoteJS`, `authorName`, `postID` | raw |
| `permalinkURL` | `item.url` or the page URL, fragment stripped, `#<postID>` appended (.m:91-103) |
| `canBeFavorite` | `!unreadable` (live worker) / `YES` (filter worker) |
| `isPrivateCategory` | `inputData["cat"] == "prive"` |
| `canAQ` | `!isPrivateCategory` |
| `canBookmark` | `mpstorage_active` default **and** not private (.m:18) |
| `canDelete` | `editURL != nil && index > 0` (.m:43). Page-relative index, so on page N>1 the first message is not deletable even if it could be (unverified); popup policy repeats `messageIndex != 0` (MessagesView.swift:255) |
| `topicID`, `topicCategory`, `topicTitle` | `hop.post`, `hop.cat`, trimmed title |

The menu composition and ordering logic is in Swift already (`MessagePopupMenuPolicy`, MessagesView.swift:196-308, with tests `HFRswiftTests/MessagePopupMenuPolicyTests.swift`).

### 3.6 Filters applied during parsing (policy mixed into the parser)

All in `parseData:filterPostsQuotes:startAfterThisPostId:topicUrl:topicPage:` (ParseMessagesOperation.m:111-486). Inputs read from globals: `MultisManager.getMainCompte[PSEUDO_DISPLAY_KEY]` (own pseudo), `BlackList.shared` (`isBL/isWL`), `NSUserDefaults` (`filter_posts_quotes`, `filter_posts_min_quotes`, `embedded_videos`).

1. `startAfterPostId`: skip messages up to and including that id (:160-166). Used for "filtered posts" starting after a flag.
2. In filter mode the first `messagetable` of the page is dropped (:141-144).
3. `Publicité` author skipped (:172-174).
4. Post kept in filter mode if (`bFilterCurrentPost = NO`): author is own pseudo (:184), or `filter_posts_quotes` contains `wl` and the author is whitelisted (:187), or it quotes the own pseudo (:206-208), or (`filter_posts_quotes` contains `pseudo`) its content contains the own pseudo as text (:327-331), or `quotedNB >= filter_posts_min_quotes` (default 3) (:345-347). Otherwise dropped (:320-322, 359-361). `wl_pseudo` is the default (`HFRplusAppDelegate.m:109-112`).

Note that the own-pseudo comparison only lowercases, while BL/WL matching also removes U+200B and lowercases (`BlackList.m:130-141`).

---

## 4. Content transformations

All are applied per message, in this order, by `LinkItem.toHTML:isMP:` (LinkItem.m:23-303) on the string produced by libxml2's serializer. The regexes depend on libxml2's exact output (attribute order, quoting, no `/>`).

### 4.1 During parse (DOM level, `ParseMessagesOperation`)

| Transformation | Rule |
|---|---|
| Old quote class | `class="oldcitation"` -> `class="citation"` (:191-194) |
| Quote classification | For each `.citation`, author = `.Topic` text minus its last **10** characters (the French suffix " a écrit :") (:200-203). If author == own pseudo: class `citation_me_quoted` and the post is kept (:206-208). Else if whitelisted: `citation_whitelist` (:209). Else if blacklisted: class `citation_blacklist`, `id="2<NN><postId-without-t>"` (`NN` = running quote index, 2 digits), attributes `auteur=<author>` and `style="display:none;"`, and on the first `<p>` child add `class="pbl"` and the same `id` (:211-223). Counter increments only for quotes with a long enough header (:224). |
| Embedded videos | If `embedded_videos` is `yes` or `both`: for every `a.cLink` of the whole page (re-scanned for each message, :260) whose grand-grandparent has `class == "messCase2"` and whose parent is not `.signature`, match href against 4 regexes (YouTube `watch?v=`, `youtu.be`, Vimeo, Streamable; Dailymotion, Coub, Twitch present but commented out/unused) (:241-258,265-298). Matching link: `class="embedvideo"`, adds `hrefemb=<embed URL>` and `hreftxt=<raw text of first child>` (:301-304). Embed URLs: `https://www.youtube.com/embed/<id>[?start=<s>]`, `https://player.vimeo.com/video/<id>`, `https://streamable.com/s/<id>`. |
| Link-text and attribute injection | Because `addAttributeNamed` appends, a node can end with two `class`/`id` attributes (see quirk 12). |

### 4.2 In `toHTML` (string level, in order)

1. Load `templatev2.htm`, remove `\n` (:37-39). Add classes on the `message` div: `del` (deleted), `mode` (author `Modération`), `me` (own pseudo), `whitelist`, or for blacklisted authors `bl` + `style="height:0px;` and header `bl` (:41-54). Own-pseudo comparison here is `lowercaseString` only.
2. Replace `%%AUTEUR_PSEUDO%%`, `%%POSTID%%`, `%%MESSAGE_DATE%%` (trimmed), `%%popup_action%%` (:56-60). **The pseudo is inserted without HTML escaping.**
3. Avatar: with a cached file, `style="background-image:url('<path>');"`, else class `noavatar` (:62-70).
4. Content: trim, delete the literal separator `---------------` (:72-74).
5. Blacklisted quotes (:76-94): regex `<table class="citation_blacklist" id="([0-9]+)" auteur="([^"]+)"` is prefixed by a "show quote" mini table (`<table class="bl_quote_show" id="1$1">`, text `<author> a écrit :` or `Citation masquée` if `blacklist_hide_pseudo`) with inline JS that toggles `getElementById($1)`, `getElementById(1$1)` and `getElementById(3$1)`. `<p class="pbl" id="N">` is replaced by a hide button row. No element with id `3<N>` is ever created (a JS TypeError on the last statement; the earlier statements run).
6. Custom smileys (:96-134): `<img src="https://forum-images.hardware.fr/images/perso/<file>" alt="[:<code>]" title="...">` -> `<img onClick="window.location='oijlkajsdoihjlkjasdosmiley://smileycode/<code>/'+encodeURIComponent(this.src); return false;" class="smileycustom" src="https://forum-images.hardware.fr/images/perso/<file>">` (code has `'` escaped).
7. Standard smileys (:138-141, 228-231): `<img src="http://forum-images.hardware.fr/<...>/<name>" alt=".." title="..">` -> `|NATIVE-<name>-98787687687697|` -> `<img src='<name>' />`, i.e. local file copied to `Caches/cache` by `OfflineStorage` from `commonsmile.plist`. Only the **`http://`** form matches (the `https://` variant is commented out at :143-147), so `https` standard smileys, if the forum emits them, are loaded from the network (unverified which is real).
8. Embedded videos (:148-158): regex `<a rel="nofollow" href="..." target="_blank" class="embedvideo" hrefemb="..." hreftxt="...">text</a>` -> `<div class="embedvideo"><iframe src="<hrefemb>" frameborder="0"></iframe></div>` (mode `both` adds `<br><a href=..>text</a>`). The link text group is `[^<]+`, so links with markup inside are not converted.
9. Domain fix: `hfr-rehost.net` -> `reho.st` (:163).
10. Relative links: `href="/forum2.php` -> `https://forum.hardware.fr/forum2.php` (:167), again `href="/forum2.php?config=hfr.inc` (:268), `<a href="/hfr/` -> `https://forum.hardware.fr/hfr/` (:269) (comment: "security issue on href for quotations").
11. Images (with `display_images == yes`, the only reachable mode): linked images `<a rel="nofollow" href=H target="_blank" class="cLink"><img src=S alt title onload style></a>` and bare `<img src alt title onload style>` -> same elements with `class="hfrplusimg"`, `title="<messageIndex>"`, `longdesc` and an `onClick` navigating to `oijlkajsdoihjlkjasdoimbrows://<index>/<encodeURIComponent(alt)>` (:182-190). The `onload`/`style` attributes in the regex are what HFR's own image tag carries (unverified).
12. Signature: unless `display_sig == yes`, cut everything from `<span class="signature">` and append `</div>` (:233-247). The renderer also adds class `nosig` to the container (ObjCTopicHTMLRenderer.m:10,32).
13. Appended blocks: `<a class="quotedhfrlink" href="<quotedLINK>"><quotedNB></a>`; `<p class="editedhfrlink">édité par <editedTime></p>` (:249-254). In filter mode a leading `<a class="filteredpostlink" href="<url>">Voir dans le sujet non filtré[ - page N]</a>` (:255-262).
14. CSS tweak: `<span style="color:blue">` -> `<span style="color:var( --color-action)">` (code-block keyword color) (:265).
15. Placeholders: `%%MESSAGE_CONTENT%%` replaced **before** `%%%%ID%%%%` and `%%ID%%` (:271-276), then all `\n` are removed (:279).
16. Blacklisted author: prepend a collapsed header `<div class="message headerblacklist" id="10<index>">` plus `<div class="message separator" id="20<index>">`, and JS buttons that change height of `id=<index>` (:281-295). Author shown, or empty if `blacklist_hide_pseudo`.

### 4.3 Message list level (`ObjCTopicMessageContentBuilder`)

- Concatenates `toHTML` outputs; `index` (array position) is the DOM id (`%%ID%%`).
- "New messages" separator: with a non-empty fragment (flag) that parses to a post number, `<div class="separator1"></div>` is inserted **after** the post whose digits equal the flag and only if it is not the last post (ObjCTopicMessageContentBuilder.m:27-35). `separatorRequested = anchor.length > 0` (ObjCTopicPageWorker.m:85). In search results Swift moves the separator **before** the matched post by string surgery (`rewriteSeparatorBeforeAnchor`, MessagesView.swift:4065-4081).
- `resolvedAnchor` (closest following post when the flagged post is gone) is computed but never used (see 1.3).

### 4.4 Whitelist, blacklist, own-pseudo semantics (summary)

| Case | Parser effect | HTML effect |
|---|---|---|
| Author is own pseudo | keep in filter mode | `.message.me` |
| Author whitelisted | keep in filter mode if `filter_posts_quotes` has `wl` | `.message.whitelist` |
| Author blacklisted | none | `.message.bl` collapsed to `height:0`, placeholder header, show/hide JS |
| Quote of own pseudo | keeps the post | `table.citation_me_quoted` |
| Quote of whitelisted | none | `table.citation_whitelist` |
| Quote of blacklisted | none | hidden quote + toggle UI (`citation_blacklist`, `bl_quote_show`) |

BL/WL lists are persisted outside this area (`BlackList.m`, per account; HFRStorage). The parsing area only needs `isBL/isWL(pseudo)` and `ownPseudo`.

---

## 5. Rendering pipeline (WKWebView)

### 5.1 Page shell (`ObjCTopicHTMLRenderer.m:9-105`)

A single `stringWithFormat:` produces an XHTML-transitional document:

- `<head>`: `jquery-2.1.1.min.js`, `jquery.doubletap.js`, `jquery.base64.js` (relative URLs; staged by OfflineStorage), viewport (no zoom), `<link id='light-styles' href='style-liste-light.css'>`, `<style>` with custom font CSS (always empty in the live path) and `.smileycustom {max-height:45px;}` in `<style id='smileys_double'>`.
- `<body class='ios7 | ios7 searchintra'>` (only `ios7` in the live path), anchors `top`/`bas`, then `<div class='bunselected nosig?' id='qsdoiqjsdkjhqkjhqsdqdilkjqsd2'>` wrapping the messages HTML, then `#endofpage`, `#endofpagetoolbar` markers used by Swift to scroll to the bottom (MessagesView.swift:2232-2240).
- Inline script: `DOMContentLoaded -> loadedML()` that navigates to `oijlkajsdoihjlkjasdoloaded://loaded` after 700 ms; `touchstart` navigates to `...touch://touchstart`; `toggleDiv`; `HLtxt/UHLtxt`; `swap_spoiler_states(obj)` (toggles `visibility` of the first inner `div`, used by the forum's own `onclick` on spoilers, CSS `div.masque{visibility:hidden}` at style-liste-light.css:130); `$('img').error(...)` swaps broken images to `photoDefaultClic.png` (reho.st) or `photoDefaultfailmini.png`; `touchHeaderMessage(node, 'avatar'|'message')` (see 5.3); then 26 `document.documentElement.style.setProperty('--color-...')` calls (`ThemeColors`), including `--imagefile-avatar` and `--imagefile-loadinfo` (light/dark file names).
- The final `stringByReplacingOccurrencesOfString:@"iosversion"` is a global replace over the whole document including message text (ObjCTopicHTMLRenderer.m:104): a message containing the word `iosversion` is rewritten.

### 5.2 Resources and themes

- Stylesheet: only `style-liste-light.css` is linked (also forced again by `applyMessageStyleIfNeeded`, MessagesView.swift:1418-1422). Dark mode is **entirely CSS variables**. The ObjC shell sets them from `ThemeColors`, then Swift **overwrites the same variables** after load with `MessageWebLegacyThemeVariables` (MessagesView.swift:2381-2427; a bootstrap `WKUserScript` at document start, :787-805, and again in `applyThemeIfNeeded`, :1289-1337). The two lists are duplicates (ObjC list: ObjCTopicHTMLRenderer.m:46-71). Other legacy CSS (`style-liste.css`, `-dark`, `-oled`, `-retina*`) are bundled but unused by the live path.
- Message style variants ("classic" / "modern") and message colors are injected by Swift as a `<style id="hfrswift-message-style">` plus root variables (MessagesView.swift:1340-1432); body text size by `<style id="hfrswift-text-size">` forcing `.message .content .right { font-size: Npx !important }` (:1448-1470). Legacy used jQuery `.css('cssText', ...)` (MessagesTableViewController.m:2822+).
- Resources are loaded from `Caches/cache` through `loadFileURL(_:allowingReadAccessTo:)` (MessagesView.swift:976, Common.swift:1962-1972). The list copied at launch is in `OfflineStorage.m:441-471`. Anything not in that list (e.g. a new smiley file not in `commonsmile.plist`) will 404 in the page.
- Avatars are referenced by absolute filesystem path in an inline `background-image:url('/…/Caches/cache/avatars/<md5>')` (LinkItem.m:63).

### 5.3 JS bridge (page to native)

There are two channels.

**Custom URL schemes** (navigation interception in `WebView.Coordinator.decidePolicyFor`, MessagesView.swift:1485-1520, routed by `MessageWebActionHandler`, Common.swift:2031-2260; unit tests in `HFRswiftTests/MessageWebActionHandlerTests.swift`):

| Scheme | Emitted by | Meaning |
|---|---|---|
| `oijlkajsdoihjlkjasdoauto://begin\|previous\|next\|end\|choose` | toolbar HTML (dead page-nav) | `loadPage` with initial scroll (`next` -> top, `previous`/`end` -> bottom). `choose`, `submitsearch`, `filterPostsQuotesNext` return `nil` -> `.ignore` (Common.swift:2095-2121) |
| `...popupavatar://<x>/<y>/<messageIndex>`, `...popupmessage://...` | `touchHeaderMessage` JS (ObjCTopicHTMLRenderer.m:45): x = center of tapped header element, y = top of its parent, index = `selectedNode.parentNode.parentNode.id` | native action menu (`popupPayload`, Common.swift:2135-2158) |
| `...imbrows://<index>/<urlencoded image URL>` | image `onClick` | `presentImageViewer(url)` (double percent-decoding allowed, Common.swift:2200-2230) |
| `...smiley://smileycode/<code>/<urlencoded image URL>` | custom smiley `onClick` | favorite smiley management (Common.swift:2173-2198) |
| `...loaded://`, `...touch://`, `...preloaded://` | shell JS | ignored |
| `...refresh://` | (removed refresh button) | `refreshCurrentPage` |
| `http(s)`, `file`, forum2.php/hfr links | normal `<a>` | `openInternalTopic` (host `forum.hardware.fr` with first path component `forum2.php` or `hfr`, or `file`), else `openExternalURL` for link taps; `#bas` ignored |

The scheme prefix `oijlkajsdoihjlkjasdo` is an arbitrary obfuscation constant, not an HFR fact.

**`WKScriptMessageHandler`** (Swift-injected `WKUserScript`s, MessagesView.swift:813-897,1169-1225): `scrollState` ({atBottom, y, viewportHeight, contentHeight}) and `textInteractionState` (selection/context menu active). Text quoting uses `evaluateJavaScript` on selection, walks up to `.message`, reads its numeric `id` (< 100 to avoid the blacklist helper ids 10x/20x) and maps it to `messageActionsByIndex[index].quoteURL` (MessagesView.swift:589-640).

### 5.4 Multi-quote cookie

- `quoteComponents(from: quoteJS)` (MessagesView.swift:1852-1878): take text between the first `(` and the first `)`, split on `,`, strip quotes, drop empties, require at least 4 values; cookie name `quotes<v0>-<v1>-<v2>`, quote id `<v3>`.
- `toggleQuoteSelection` (:1924-1950): read cookie (via `HTTPCookieStorage.shared`, skipping expired), marker `|<id>`; if `contains(marker)` remove it, else append; empty value deletes the cookie, otherwise write cookie `domain .hardware.fr`, `path /`, expires now + 3600 s (:1895-1908).
- `isQuoteSelectionEnabled` (:1915) drives the popup label.
- The HFR "quote" URL (`urlQuote`) then returns all selected messages server-side (documented in `docs/HFR-PROTOCOL.md`).
- Bug: matching uses substring `contains("|123")`, so a selected `|1234` is considered to contain `|123`, and the removal `replacingOccurrences` would corrupt it. Same logic in the legacy original (MessagesTableViewController.m:2726-2733). Low probability, since ids of one topic usually have equal length.
- Boundary: this is cookie state shared with the HTTP stack, so it belongs next to `HFRNetwork` cookie handling.

### 5.5 Persistence of generated HTML

`topic-<UUID>.htm` files are written to `Caches/cache` for every page load and never deleted by this code path (Common.swift:1962-1972; the legacy `OfflineStorage createHtmlFileInCacheForTopic` used a stable `topic-<page>.htm` name). Cleanup is unverified.

---

## 6. Quirks, visible bugs and dead code

Numbered for cross-reference; "port" says what the new implementation should do.

1. **Regexes over libxml2 serialization** (LinkItem.m:80,105,139,149,172-190,265). Attribute order and quoting are produced by `htmlNodeDumpFormatOutput`. Port: do DOM-level rewrites (SwiftSoup) and do not reproduce byte-exact HTML; the oracle for these must be semantic (see lots).
2. **Newline removal after content insertion** (LinkItem.m:279): all `\n` in message text/code are deleted. Token replacement order lets a post containing `%%ID%%` be rewritten (:271-276). Global replace of `iosversion` over the page (ObjCTopicHTMLRenderer.m:104).
3. **Unescaped pseudo** in template (LinkItem.m:56) and in the blacklist header (:293).
4. **YouTube timestamp bug**: `[2]*60 + [2]*3600` should be `[1]*3600` (ParseMessagesOperation.m:281). The regex only matches `t=<h>h<m>m<s>s` (:275); plain `?t=90` is not converted (unverified against real links).
5. **Video scan inside the per-message loop** (:260-317): the whole body is scanned for each message (the first iteration converts everything, later ones find nothing). Behaviour is global per page, not per message.
6. **Filtered renderer always non-private**: `inputData.cat` is a numeric `catID` string, so `isPrivateCategory` is never true (ObjCFilteredPostsRendererWorker.m:34-38). `canAQ`/`canBookmark` therefore always follow the non-private rules there.
7. **Dead anchor resolution** (see 1.3). If the flagged post was deleted, the fallback is `location.hash`, which does nothing (MessagesView.swift:1082-1090).
8. **HTMLParser given a non-NUL-terminated buffer**: `htmlReadDoc((xmlChar*)[data bytes], ...)` (HTMLParser.m, initWithData). `ParseMessagesOperation.initWithData` strips `\0` and re-encodes (:47-49), but the live path passes the raw `NSData` straight to `HTMLParser` (ObjCTopicPageWorker.m:105, FilterPostsQuotes.m:130). Reads past the buffer are possible (unverified). Port: SwiftSoup on a `String`.
9. **Avatar cache**: key `md5(lowercased pseudo)` (CommonCrypto), 24 h TTL via creation date, failure drops a valid stale avatar (:464-467), file path embedded in HTML.
10. **Own-pseudo comparison ignores U+200B** while BL/WL strip it (ParseMessagesOperation.m:184 vs BlackList.m:132-137).
11. **Date regex** is greedy and unanchored on multi-line text (:400-401).
12. **Duplicate attributes/ids** from `addAttributeNamed` (:214-222, 302-304): the blacklist table and its `<p>` share the same `id`; a `<p>` that already has a class gets two `class` attributes. The browser keeps the first.
13. **`canDelete = index > 0`** is page-relative (ObjCMessageActionsBuilder.m:43; MessagesView.swift:255).
14. **Quote author = header minus last 10 characters** (ParseMessagesOperation.m:203). Breaks if the French string changes (and for quotes of anonymous/deleted accounts: unverified).
15. **`filterPostsQuotesNext` / `submitsearch` links are ignored** by the Swift router (Common.swift:2095-2121). A native control replaces them (`advanceToNextFavoritePostFilterResults`, MessagesView.swift:3970) (the in-page "Résultats suivants" link seems redundant: unverified).
16. **Stale error domain**: Swift checks `MessagesTableViewController.search` code `-11` (MessagesView.swift:4044) but the live worker uses `ObjCTopicSearchWorker.search` (Classes/ObjCTopicSearchWorker.m:15,47,60). The "no more results" toast path is likely unreachable (search area).
17. **Stale smoke test** for `MessagesTableViewController` (see 1.2).
18. **Anchor JS injection**: the URL fragment is interpolated unescaped into `'\(a)'` (MessagesView.swift:1062-1092).
19. **Page number derived in two places** with different regexes (ObjCTopicPageWorker.m:14-43; Common.swift:2471-2508). Current page is not read from the HTML at all.
20. **Multi-quote substring match** (5.4).
21. **Poll vote encoding** uses `.urlQueryAllowed`, which leaves `&`, `+`, `=` unescaped (PollData.swift:62-65, 386-388) (network/poll-submit area).
22. **jQuery 2.1.1 + `$('img').error(...)`**, `jquery.base64.js` and `jquery.doubletap.js` are loaded on each page but only the image error handler and `addClass/removeClass` on dead toolbar buttons use jQuery in the live path (unverified for `doubletap`/`base64`).
23. **Page-level secrets in memory/API**: `swiftSearchInputData` and `inputData` carry `hash_check`. Treat as sensitive.
24. **Features dropped from the legacy controller**: MP badge from the page, topic flag state (`delflag`, red flag), "reprise" handling, swipe navigation, offline mode (`isModeOffline`). Confirm with product owner whether the new app needs them (open questions).

---

## 7. Proposed lots

Numbering `LOT-C##` is provisional (to be remapped by LOT-000 in `docs/LOTS.md`). Module names follow `docs/ARCHITECTURE.md`. "App-side" = SwiftUI app or a feature module, **not** `HFRKit` (it may still be pure Swift and Linux-testable). Difficulty uses the repo scale (`trivial/easy/medium/difficult`). Model routing follows AGENTS.md §6 (message parser -> Fable 5.1).

### 7.1 Design decisions the lots assume (to be confirmed by an ADR before C03)

1. **Parser = pure, policy-free.** `HFRParsing` returns *all* messages with raw facts (author, quotes with authors, content HTML, links). Blacklist/whitelist, own pseudo and the "filter posts & quotes" rules (section 3.6) become a separate pure function in app-side code, fed by `HFRStorage`. This removes the three global singletons (`MultisManager`, `BlackList`, `NSUserDefaults`) from the parser, which is what `ARCHITECTURE.md` rule 2 requires.
2. **No avatar download in the parser.** The parser returns the avatar URL. Caching (md5 key, 24 h) is a storage/network concern.
3. **Content rewriting is DOM-level.** SwiftSoup is allowed only inside `HFRParsing` (ADR 0002), so content normalization (smileys, images, links, videos, signature split, quote blocks) must live there. Decided by [ADR 0006](../adr/0006-content-normalization-in-parsing.md): the output is display-independent (normalized HTML + typed lists), with no `MessageRenderOptions`; display choices are applied app-side.
4. **Rendering stays a WKWebView with HTML/CSS** (the CSS is 1077 lines of tuned styling); only the assembly and the JS bridge are rewritten.

### 7.2 Lot list

| Lot | Name | Scope | Module | Difficulty | Depends on | Fixtures |
|---|---|---|---|---|---|---|
| C00 | Oracle exporter for topic pages | Legacy-side harness (Phase 2): dump per fixture `[LinkItem]` fields (3.2), page metadata (3.3), `swiftMessageActionsByIndex`, and `toHTML` output as JSON, with a configurable context (own pseudo, BL, WL, defaults). Also capture the raw HTML as received. | legacy app (Mac) | medium | none | all of section 8 |
| C01 | Models | `TopicPage` (title, currentPage?, maxPage, answerFormURL, formFields, unreadable, poll?, searchForm, messages), `Message` (postID, author, deleted, avatarURL, dateText, `content: MessageContent`, quotes[], editInfo, quotedCount/link, actions) with `MessageContent` = the C08 result (contentHTML, signatureHTML?, images[], smileys[], links[], embeds[]), `MessageActions` (absolute URLs, `QuoteSelectionToken`), `PollRaw` (no `MessageRenderOptions`: ADR 0006 makes the output display-independent). All `Sendable`/`Equatable`/`Codable` for oracle JSON. | HFRModels | easy | none | none |
| C02 | Obfuscated URL decoder + URL helpers | `decodeSpanUrl(prefix:)` (alphabet `0A12B34C56D78E9F`, prefixes 20/12, 3.4), absolutization (`//`, `/`, relative, `&amp;`), permalink builder, page-number-from-URL and page replacement (merge `ObjCTopicPageWorker.m:14-43` and `TopicPageURLRouting`, Common.swift:2451-2540). Shared with the topic-list audit (B). | HFRParsing | easy | C01 | URL samples from every fixture |
| C03 | Message block extraction (core) | Find `messagetable` blocks, deleted wrapper, post id, author (skip `Publicité`), date string, edit info and quoted-count (`Message cité N fois` / `Message édité par`), content HTML slice (`para`), search-result prefix anchor, "reprise" detection, avatar URL. Replace positional `firstChild.firstChild` with selectors, and prove equivalence on fixtures. | HFRParsing | difficult | C01, C02, C00 | first/middle/last page, single page, deleted, edited, quoted-count, ads, moderation, anonymous viewer, MP topic, special pseudos |
| C04 | Per-message action links | quote/edit (decode), alert, profile, MP, addflag, `quoteJS`, `isOwnMessage`; builds `MessageActions` (replaces `ObjCMessageActionsBuilder`) without the UI-policy flags (`canAQ`, `canBookmark`, `canDelete` move to C14). | HFRParsing | medium | C01, C02, C03 | logged-in/own-post/anonymous/closed topic/MP topic |
| C05 | Quote analysis | Detect `citation`/`oldcitation`, extract quoted author (robust against the "a écrit :" suffix rule, 6.14), nesting depth, quote index; expose `Message.quotes`. No BL/WL logic. | HFRParsing | medium | C03 | simple, nested, old-style, anonymous quoted, own/BL/WL quoted, quotes in quotes, long names |
| C06 | Page metadata | Title, max page (with all pager shapes), answer form URL, `hop` hidden fields incl. `cat=prive`, `nonlu`, topic flag/favorite state (decide if needed), search form fields, first-page / last-page / single-page / closed-topic variants. | HFRParsing | medium | C01, C02 | page variants of section 8 |
| C07 | Poll parsing | Port `PollHTMLParser` (PollData.swift:117-370) from ICU regex to SwiftSoup; models for voting/results/closed; max-choices rule; hidden fields. Vote submission belongs to HFRClient (LOT-054, ADR 0008), not this lot. | HFRParsing | medium | C01 | poll not voted, voted, closed, multi-choice, no-vote-allowed |
| C08 | Content normalization (DOM rewriting) | Smileys (standard vs custom `perso`, http/https), images (linked vs bare, `reho.st` rewrite, `onload/style` variants, broken image), relative-link absolutization (`/forum2.php`, `/hfr/`), `cpp` color tweak, separator removal, signature split (return `signatureHTML` separately), spoilers left intact, code blocks, `---------------`. Output: content HTML + typed lists (images, smileys, links) so the app does not re-parse. | HFRParsing | difficult | C03, ADR | smileys, images, links, code, spoilers, signature, rehost, special characters |
| C09 | Video embed detection | Rules of ParseMessagesOperation.m:238-317 as a pure function `embed(for: URL, time:)`, fixing the hour bug and optionally accepting plain `t=<seconds>`; keeps the "not in signature" rule. | HFRParsing | easy | C08 | YouTube (long/short, with t=), Vimeo, Streamable, link in signature, text-bearing link |
| C10 | Visibility policy | Pure function `(messages, FilterContext{ownPseudo, blacklist, whitelist, options}) -> annotated messages` implementing section 3.6 and 4.4 (BL/WL/own, `filter_posts_quotes` modes, min quotes, `startAfterPostId`, drop index 0 in filter mode, U+200B-insensitive matching). | app-side (pure) | medium | C03, C05 | all, with context variants; reuses C00 outputs |
| C11 | Filtered-posts use case | Orchestrate `FilterPostsQuotes.fetchFilteredPostsForTopic` (FilterPostsQuotes.m:202-312): page loop, stop at 40 posts, `finished`, cancellation, "Voir dans le sujet non filtré" URL (supports both URL forms). Calls HFRNetwork + HFRParsing + C10. | app-side | medium | C03, C10, network lot | multi-page topic with sparse matches |
| C12 | Message HTML builder | `templatev2.htm` assembly: classes (`del/mode/me/whitelist/bl`), avatar, escaped pseudo and date, quote blocks with BL show/hide, `quotedhfrlink`, `editedhfrlink`, `filteredpostlink`, BL placeholder header, new-message separator, search-result separator placement (replace string surgery at MessagesView.swift:4065), message DOM ids. Properly escapes and avoids token-collision bugs. | app-side (pure) | difficult | C03, C05, C08, C10 | snapshot tests on the full fixture set (HTML structure, not bytes) |
| C13 | Page shell and resources | Replace `ObjCTopicHTMLRenderer`: static HTML shell + CSS variable injection (single source of truth, remove the ObjC/Swift duplication), bundle the CSS/JS with `WKWebView.loadHTMLString(baseURL:)` or a `WKURLSchemeHandler` instead of copying files into `Caches/cache`, drop jQuery if possible, keep `swap_spoiler_states`, image error fallback, theme variables, `endofpage` markers. | app-side | medium | C12 | visual checks on the same fixtures |
| C14 | JS bridge and navigation | Typed `WKScriptMessageHandler` messages instead of `oijlkajsdoihjlkjasdo*://` schemes (message popup, avatar, image, smiley, scroll, selection), link routing (internal topic vs external), text-selection quoting (index < 100 constraint disappears with typed ids), scroll/anchor logic with escaped fragment. Port tests from `MessageWebActionHandlerTests`. | app-side | medium | C13 | n/a (unit + UI) |
| C15 | Message action policy | `canAQ`, `canBookmark`, `canDelete`, `canBeFavorite`, popup order (`MessagePopupMenuPolicy`), and the multi-quote selection state. | app-side (+ small piece in HFRNetwork for the cookie) | easy | C04 | n/a |
| C16 | Multi-quote cookie store | `quotes<a>-<b>-<c>` read/toggle/delete on `.hardware.fr`, 1 h, exact match on ids (fix 5.4). Belongs with cookie management. | HFRNetwork | easy | network cookie lot | cookie round-trip tests |
| C17 | Avatar cache | md5-of-lowercased-pseudo key (or URL-keyed), TTL 24 h, no deletion of a valid stale file on failure, API returning a local file URL or letting the web view load remote URLs. Cache API in HFRStorage, download in HFRNetwork, coordination in the app (HFRClient cannot import HFRStorage). | HFRStorage | easy | none | none |
| C18 | Differential test suite | For every fixture: C03-C09 output equals oracle JSON (field-level), C12 output equals oracle HTML after normalization (DOM compare), documented deviations (4, 6, 8, 12, 14, 16). | tests | medium | C00, C03-C12 | all |

Suggested order: C00 and C01 in parallel, then C02 -> C03 -> (C04, C05, C06, C07 in parallel) -> C08/C09 -> C10 -> C12 -> C13/C14 -> C11/C15/C16/C17 -> C18 (the differential tests are written inside each lot; C18 is the roll-up gate).

Intentional differences to record in the specs: no libxml2 byte-for-byte HTML (1), no `\n` stripping (2), HTML escaping of pseudos (3), fixed YouTube hour (4), `isPrivateCategory` correct in filtered mode (6), dead anchor resolution not reproduced (7), no avatar side effects in the parser (9), fixed multi-quote matching (20).

---

## 8. Fixtures to capture

Capture on a Mac with the legacy app (Phase 2, C00). Each fixture = raw HTML + oracle JSON + the legacy context (own pseudo, BL, WL, relevant defaults). Anonymize per `docs/FIXTURES.md`: pseudos, profile/MP/`dest=` URLs, `hash_check` and every hidden form value, avatar URLs, the pseudo in `quoteJS` if any. Private-message content must be replaced by placeholder text.

| ID | Page | Purpose |
|---|---|---|
| F01 | Normal topic, page 1, 40 messages, logged in | baseline: all fields, all action links |
| F02 | Same topic page 2+ (middle) | "reprise" first block, `previous/next` pager |
| F03 | Last page, partially filled | `maxPage`, no next, reply form |
| F04 | Single-page topic | no `fondForum2PagesHaut` `left` content: `maxPage == 1` |
| F05 | Topic fetched anonymously (logged out) | absence of edit/quote/MP links, `quoteJS` |
| F06 | Locked/closed topic | no `repondre_form` |
| F07 | Page with own messages (edit and delete links) | `urlEdit` decoding, `isOwnMessage`, `canDelete` |
| F08 | Page with edited messages, "Message cité N fois" (N=1, 3, 12) | `.edited` regexes |
| F09 | Deleted messages (`messagetabledel`) | `isDel` |
| F10 | Moderation message and an ad (`Publicité`) | special authors |
| F11 | Quotes: simple, nested (3 levels), old-style (`oldcitation`), quote of anonymous/deleted account, long author names | quote rules |
| F12 | Quotes of own pseudo, of a WL pseudo, of a BL pseudo; posts by WL and BL authors (needs fixed legacy context) | policy variants incl. `blacklist_hide_pseudo` on/off |
| F13 | Spoilers (`div.masque`, nested spoilers), spoiler with image | spoiler markup |
| F14 | Images: linked (`a.cLink > img`), bare, `hfr-rehost.net`/`reho.st`, broken URL, animated gif | image regexes (`onload`/`style` attributes) |
| F15 | Smileys: standard (note http vs https), custom `perso`, many in a row, with apostrophe in code | smiley regexes |
| F16 | Links: absolute, `/forum2.php?...`, `/hfr/...`, link to a message `#tNNN`, link with markup inside | link rewriting |
| F17 | Code blocks (`table.code`, `ol.olcode`), keyword coloring (`color:blue`), cpp tag | code and `---------------` |
| F18 | Embedded video links: YouTube long/short/with `t=`, Vimeo, Streamable, Dailymotion, Twitch (should not embed), in signature | video rules |
| F19 | Messages with signatures (short, with image, with link) | signature split |
| F20 | Poll not voted (single choice), multi-choice, voted/results, closed | poll parser |
| F21 | MP topic (`cat=prive`), single and "multiples" | private rules, `hop` fields |
| F22 | In-topic search result page (non filtered, with `#t` fragment) and search with no result | `aucune réponse`, separator, `transsearch` form |
| F23 | Topic with unread marker (`nonlu`) and favorite flag links | `nonlu`, `addflag`, `delflag` |
| F24 | Pseudos with spaces, accents, `&`, `<`, zero-width space, very long; empty avatar; avatar over http | escaping and cache key |
| F25 | A page containing a NUL byte or invalid UTF-8 | parser robustness (6.8) |
| F26 | Filtered-posts run on a topic (multi-page), plus the legacy output of `ObjCFilteredPostsRendererWorker` | filter mode |
| F27 | Page 1 vs page `max+1` request (redirect to last page) | effective URL vs current page |

Also keep, per fixture, the response URL (after redirect) and request URL, since `currentPage` depends on it.

---

## 9. Open questions

1. What is the exact markup around a message (`table`/`tr`/`td` tags, whitespace)? The positional `firstChild.firstChild` rule (ParseMessagesOperation.m:145,160) needs fixtures F01/F02 to replace by a selector.
2. Does the first block of page 2+ ("Reprise de la page précédente", comment at ParseMessagesOperation.m:141) appear in normal mode, and should the new app show it? The legacy shows it in normal mode and hides it only in filter mode.
3. Does HFR emit `https://forum-images.hardware.fr/...` for standard smileys now? Only the `http://` form is rewritten to a bundled image (LinkItem.m:139).
4. What does the pager look like when there are many pages (ellipsis nodes)? Is `children.lastObject` always the last page number (ParseMessagesOperation.m:506)?
5. What does HFR return for a page number above the maximum? (ASIHTTPRequest follows redirects; current page is read from the final URL.) Needed by `maybeProbeNextPageAfterRefresh` (MessagesView.swift:3022).
6. Which values can `hop` hidden inputs take, and which of them are needed outside of `cat`/`post`/`p`/`hash_check`?
7. Is `isOwnMessage == (editURL != nil)` correct for moderators/admins?
8. Should the new app keep the topic flag/favorite state and the MP badge parsing that the legacy controller had (1.2)? If yes, which lot owns them (C06 or list area B)?
9. ADR needed: where do DOM-level content rewrites live, given SwiftSoup is confined to `HFRParsing` (7.1 point 3)? And should `HFRModels` carry `MessageRenderOptions`?
10. Keep jQuery? Only `$('img').error` and legacy toolbar classes seem to need it in the live path (6.22).
11. Offline reading (`OfflineStorage` topic files, `isModeOffline` in the legacy controller) is out of this audit but changes the parser's input contract (HTML from disk). Is it in scope for the new app?
12. `display_images` is forced to `yes`; confirm whether the "no"/"wifi" modes are intended to come back (LinkItem.m:169-226 is a lot of code for a dead branch).
13. Does the stale `ObjCWrappedClassesSmokeTests` currently pass or fail on `MessagesTableViewController`? (not run here)
14. Are there HFR variants for mobile (`/mobile/` or `m.hardware.fr`) that the new app should prefer? Nothing in the legacy code uses them.
