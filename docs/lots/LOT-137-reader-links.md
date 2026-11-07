# LOT-137 — Link handling in the reader (internal in app, external in browser)

- **Module:** App (`App/SwiftHFR/Reader/`, the reader columns in `Root/RootTabsView.swift` and `Messages/MessagesRootView.swift`)
- **Difficulty / model:** medium (Opus 5.5 author → Sonnet 5.5 review: no cookie reaches a new host, see Security)
- **Issue:** [#227](https://github.com/ezzz/HFRnow/issues/227)
- **Depends on:** LOT-095 (#187, `HFRLinkRoute`), LOT-083 (#101, the reader); LOT-119 (#210) stores the browser setting

LOT-083 already ships the ground: the web view never navigates, every link tap is handed to the app, a topic link opens in the
reader at its page and post (issue #106), other `http(s)` links open in `SFSafariViewController`. This lot finishes it: one link
parser (the router), the "Navigateur par défaut" setting, and a way back to where the link was tapped.

## Legacy sources
Read-only, ezzz/HFRnow `origin/master` at `21173e77` (the default-browser setting is newer than `2440d79`; LOT-095 cites `2440d79`).

| Legacy | What it gives |
|---|---|
| `HFRswift/Swift/Common.swift:2303-2312` (`MessageWebActionHandler.action`) | a tapped link: `isForumTopicURL` (or `file:`) → `.openInternalTopic`, other `http(s)` → `.openExternalURL`, anything else is left to the web view |
| `HFRswift/Swift/Common.swift:2473-2479` (`isForumTopicURL`) | host `forum.hardware.fr` and first path component `forum2.php` or `hfr`: lists, profiles and searches are opened as topics too |
| `HFRswift/Swift/MessagesView.swift:3896-3927` (`openInternalTopic`) | an internal link **pushes** a new `MessagesView` (`navigationDepth + 1`) at the link's page: back returns to the topic where the link was tapped |
| `HFRswift/Swift/MessagesView.swift:3963-3968` | `.openExternalURL`: `UIApplication.shared.open` when `open_links_in_default_browser`, else the `SafariInAppView` sheet |
| `HFRswift/Swift/MessagesView.swift:2874-2885` (`SafariInAppView`) | `SFSafariViewController`, default configuration, `dismissButtonStyle = .close` |
| `HFRswift/Swift/Common.swift:239-241` (`AppOpenLinksInDefaultBrowser`) | key `open_links_in_default_browser`, default `false` (LOT-119: `SettingKey.opensLinksInDefaultBrowser`) |
| `HFRswift/Swift/UserProfileView.swift:614-620` | same choice for profile links |
| `Classes/HFRplusAppDelegate.m:764-777`, `Classes/BrowserViewController.m` | Objective-C paths: `openURL:` honours the same key; `BrowserViewController` is the old in-app `WKWebView` browser (not ported: Safari's view replaces it, LOT-071 T8) |

## Behaviour

`TopicReaderModel.action(forLink:defaultBrowser:)` decides, `TopicReaderView` acts:

| Link | Action |
|---|---|
| not `http`/`https` | `.ignored` (nothing happens) |
| `HFRLinkRoute.route` gives `.topic` or `.privateMessageThread` (after `ReaderTarget.forumURL`: forum host, no port, no user info, upgraded to `https`) | `.reader(ReaderTarget)` → `follow(_:)` |
| anything else (another host, a forum page the router does not route as a topic page: lists, profiles, search, `message.php`, `quote_only`, `print`, an unusable `page=`, a forum the catalogue lacks) | `.defaultBrowser(url)` when "Navigateur par défaut" is on, else `.inAppBrowser(url)` (`SFSafariViewController` sheet) |

- **One parser.** `ReaderTarget(link:)` is built from `HFRLinkRoute` only (LOT-095 follow-up). A routed link with `numreponse`
  has no page: the reader asks `forum2.php?…&page=1&numreponse=M` and HFR serves the message's page (R25); otherwise the
  link's page (1 when absent) and its `#t<n>` anchor are kept. `ReaderTarget.Source` keeps one case, `.topic(TopicID)`: a
  canonical path is no longer fetched as written (`.path` is gone), the router gives its category from `ForumCatalogue`.
- **Rows** (`ReaderTarget(opening:)`, `MessageListModel`) still pass the row's `TopicID` as `fallbackTopic`: a canonical
  path of that same topic number in a forum the catalogue lacks (#125) opens that topic, built from the row's ID, never from
  the link. Links in a message get no fallback: what the router refuses goes to the browser.
- **Following a link** (`follow(_:)`): a post of the page shown (same topic, same page or a message link whose message is on
  the page) scrolls without a request (LOT-083). Anything else creates `linkedReader`, a new `TopicReaderModel` (same page
  source and render options, the current title when it is the same topic), which the view pushes with
  `navigationDestination(item:)`. Back clears it (`closeLinkedReader()`); the reader underneath keeps its page, document and
  web view, so it is where it was left, without a new request. The reader columns wrap the reader in a `NavigationStack`
  (`.id` of the topic or conversation: a new selection starts a new stack). A reader covered by a pushed one is not cancelled
  nor stopped on `onDisappear`.
- **Browser choice** is read at each tap (`ReaderSettings.opensLinksInDefaultBrowser`, from the store), so a change in
  Réglages applies to the next link without rebuilding the reader. The system browser opens through SwiftUI's `openURL`.
- **Returning from Safari.** The `SFSafariViewController` sheet is presented by the reader itself and the reader's state lives
  in its model (held by `NavigationModel` / `MessageListModel`), not in the sheet: closing the sheet, or coming back from the
  system browser (Safari's own "open in Safari" button, or the default-browser setting), shows the same reader, page and
  scroll position. The p. 506-507 report (legacy: back on the list after Safari, iPad Pro, iOS 26) came from legacy's
  stack; nothing in this app resets the navigation on a foreground return (`SwiftHFRApp` only rechecks unconfirmed sessions,
  which rebuilds the navigation only when the current session object changes, i.e. a logout or an account switch).

## Security
- No cookie reaches a new host: the session still fetches only `forum2.php` topic pages built from a `TopicID`
  (`LiveTopicPageSource`), and fewer links than before reach it (the router refuses answer links, single-message and print views,
  unusable pages, unknown forums). `SFSafariViewController` and the system browser have their own cookie stores; the app's
  session is never handed to them.
- A private message link posted in a public topic opens in the reader with the session, as legacy did (`isForumTopicURL`); HFR
  serves it only to a participant. That reader gets no reply composer (`isPrivateConversation`): MP replies are LOT-128's, the Messages tab has none either.

## Edge cases
- A link to the page on screen without an anchor pushes a reader of that page (legacy pushed too); the page bar, refresh and
  "after a reply" stay in place.
- A chain of links pushes a chain of readers; each fetches its page once (E25), nothing is prefetched.
- A link tapped in a pushed reader of a private conversation (Messages tab) pushes inside that tab's stack.
- Routes other than topic pages (`.topicList`, `.profile`, `.favorites`, `.privateMessageList`, `.search`, `.searchResults`,
  `.home`) have no in-app destination reachable from the reader yet: they open in the browser (follow-up: LOT-138 #228 owns a
  global route handler for universal links, share and clipboard, and can take them over).

## Pending capture
- A private message link naming a message (`forum2.php?…cat=prive&post=N&numreponse=M`): the corpus has none with a non-zero
  `numreponse` (MP list rows carry `numreponse=0`), and R25 is a public topic whose redirect target is a canonical path MPs do not
  have. The reader follows the router's rule (no page, R25-shaped request); what HFR answers is not captured
  ([#388](https://github.com/ezzz/HFRnow/issues/388)). A failure shows the reader's error, nothing is written.

## Intentional differences from legacy
- **Link long-press menu (#596, GAP-596, new, operator 2026-11-07; legacy returned nil for a plain link, i.e. WebKit's own menu with a preview, and built a menu for image links only, `MessagesView.swift:1241-1278` @ 2440d79; "Ouvrir l'image" and "Save to Photos" deferred to #615).** For an `http(s)` link: Ouvrir (the tap routing above), Copier le lien, Ouvrir dans Safari (`UIApplication.open`; iOS may give a universal link to its app) and, for non-forum links, Ouvrir dans l'app (`.universalLinksOnly`, Safari when no app answers; named for YouTube, Vimeo, Streamable only). No preview provider, `allowsLinkPreview = true` so WebKit consults `contextMenuConfigurationForElement`; nothing is fetched, with or without the session. Code: `ReaderWebController+LinkMenu.swift`; tests `ReaderLinkMenuTests`.
- Lists, profiles, searches and other forum pages that are not topic pages open in the browser, not as a broken topic
  (`Common.swift:2473-2479` treated every `/hfr/…` and `forum2.php` link as a topic).
- Answer links, single-message and print views, an unusable `page=`, and forums the catalogue lacks open in the browser (LOT-095).
- `file:` links do nothing (legacy loaded them in the reader, `Common.swift:2306`).

## Tests (`App/SwiftHFRTests/`)
- `ReaderTargetTests`: canonical links read by the router (`.topic`, catalogue category), query dropped; answer, `quote_only`,
  `print`, unusable page, list and profile links refused (with or without a fallback); an uncatalogued forum opens only as the
  row's own topic; private message links (page kept, message link without page).
- `TopicReaderModelTests`: `aFollowedLinkKeepsThePageItLeftForTheWayBack` (pushed reader, page and document untouched, no
  refetch), scroll on the page shown, message links through a pushed reader, browser choice
  (`theDefaultBrowserSettingSendsWebLinksToTheSystemBrowser`), router refusals go to the browser.
- `ReaderImageFetcherTests.theBrowserChoiceIsTheStoredSetting`: the live setting is read from the store, off by default.
- `LiveTopicPageSourceTests.aCanonicalLinkIsFetchedAsItsTopicNeverAsWritten`: the session asks `forum2.php`, never the link's path
  and query.

Shown to fail with each rule reverted: browser choice ignored, link loaded in place instead of pushed, the old
`HFRURL.topicID` parser restored for links the router refuses, the live setting forced off.
