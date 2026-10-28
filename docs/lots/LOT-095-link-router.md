# LOT-095 — Inbound link router (HFR URL → route)

- **Module:** HFRParsing
- **Difficulty / model:** easy (Sonnet → Opus)
- **Issue:** [#187](https://github.com/ezzz/HFRnow/issues/187). Feature: FEAT-020 ([#164](https://github.com/ezzz/HFRnow/issues/164)), proposed by Bybifok (credit: [CREDITS.md](../../CREDITS.md)). Other lot of the feature: LOT-138 ([#228](https://github.com/ezzz/HFRnow/issues/228), the app side: universal links, share, clipboard). Absorbs bug #106 (links keep page and anchor).

`HFRLinkRoute.route(for: URL) -> HFRLinkRoute` decides, from a URL alone, which screen a forum link opens, at which page and
message. Pure function, no request, no page parsing. The app turns the route into navigation; a route never fetches anything by itself.

## Legacy sources
Legacy repository <https://github.com/francoisgn/hfrnow> at `2440d79` (same paths on `origin/master`). Legacy has no router: each screen decides for itself.

| Legacy | What it gives |
|---|---|
| `HFRswift/Swift/Common.swift:2473-2479` | `isForumTopicURL`: host equals `forum.hardware.fr` and the first path component is `forum2.php` or `hfr`. Everything else on http(s) goes to the browser. Lists, profiles and `/hfr/recherche/…` are therefore treated as topics (see differences) |
| `Common.swift:2672-2727` | `TopicPageURLRouting.pageNumber`: `page=` first, then the regexes `page=(\d+)` and `_(\d+)\.htm`. Mirrored by `HFRURL.page(in:)` (LOT-020), used here as the differential reference |
| `Common.swift:2672-2686` | `searchMatchURL`: a `numreponse=` becomes the anchor `#t<numreponse>` when the link has no fragment |
| `Common.swift:2549-2553` | `numreponse=0` means none |
| `MessagesView.swift:3868-3940` | `normalizedForumTopicURLString` (absolute forum URL to `/path?query#fragment`) and `openInternalTopic` (page from the link, else 1) |
| `Classes/Bookmark.m:17` | bookmark link: `/forum2.php?config=hfr.inc&cat=<c>&post=<p>&numreponse=<n>#t<n>`, no `page` |
| `AQPlusView.swift:341-375` | AQ items open through the same normalisation and page reading |
| `Classes/Forum.m:34-60` | forum path to `cat` (`ForumCatalogue`, LOT-014), used for the slug segment of canonical URLs |
| `Classes/BrowserViewController.m:23`, `HFRplusAppDelegate.m:859-868` | legacy has no universal-link handling (`continueUserActivity` returns `YES` and does nothing) |

Oracle: LOT-002 list oracles (`maxTopicPage`, `pageNumber`, `lastPageNumber`, topic and forum `aURL*` fields) and LOT-003 topic oracles
(`page.currentPage`, `actions[].permalinkURL`, `postID`, and the `cat` of the same message's `quoteURL`). No new exporter: legacy never
computed a route, so the legacy-derivable subset (page, message, category) is differential-tested from the existing oracle output
(LESSONS 52); the routing decisions are checked against every `href` of the capture corpus.

## Behaviour

```swift
public enum HFRLinkRoute: Sendable, Hashable {
    case home
    case topic(HFRTopicLink)                  // id: TopicID, page: Int?, anchorPostNumber: Int?
    case privateMessageThread(HFRTopicLink)   // forum2.php with cat=prive
    case topicList(HFRTopicListLink)          // category, subcategory: HFRSubcategory?, page, filter: TopicListFilter
    case privateMessageList(page: Int)
    case favorites(filter: TopicListFilter)   // .flagged or .favorites
    case profile(userID: Int)
    case search                               // /search.php
    case searchResults(path: String)          // forum-relative path with its query
    case external(URL)
    static func route(for url: URL) -> HFRLinkRoute
}
```

A link is routed only when it is `http` or `https`, host exactly `forum.hardware.fr` (case-insensitive), no user info, no explicit port
(LESSONS 37, 43). Anything else, and every shape below that is not listed, is `.external(url)`: the app opens it outside the app and never
requests it with the account session.

| Shape (HFR-PROTOCOL) | Route |
|---|---|
| `/hfr/<cat>/[<sub>/]<slug>-sujet_<post>_<page>.htm[#t<n>]` (R5) | `.topic`: category from `ForumCatalogue` (exact match of the `<cat>` segment), `page`, anchor `n` |
| `/forum2.php?cat=<n>&post=<p>[&page=<n>][&numreponse=<m>][#t<m>]` | `.topic`; `cat=prive` gives `.privateMessageThread`. The page is read from `page=`, **except** when a message number is present (see below) |
| `/hfr/<cat>/[<sub>/]liste_sujet-<page>.htm` | `.topicList`, filter `.all`, sub-forum as the path segment |
| `/forum1.php?cat=<n>[&page=][&subcat=][&owntopic=0..3]` (R2) | `.topicList` (page 1 when absent, `subcat` empty or 0 means the whole forum); `cat=prive` gives `.privateMessageList(page)` (R4) |
| `/forum1.php?…&recherches=1…&search=…` (R50b) | `.searchResults(path:)`: the terms live in the query, so it is never a topic list |
| `/forum1f.php?owntopic=1\|3` (R3) | `.favorites` |
| `/hfr/profil-<id>.htm` (R9) | `.profile` |
| `/search.php` | `.search` |
| `/` | `.home` |

Rules shared by all routes:
- `&amp;` is decoded and the first of a repeated parameter wins, as in `HFRURL`; the path is read percent-encoded, so `%2F` never creates a segment.
- A numeric value (`page`, `post`, `subcat`, `numreponse`, ids) is a positive ASCII integer. **Present but unusable** (`page=0`, `page=abc`, an overflow) makes the link `.external`; it never falls back to page 1. Absent is allowed where a default is meaningful: lists default to page 1, topics report `page: nil` ("the link names no page").
- `config` must be absent or `hfr.inc`. `cat=0` is not a forum (moderation links use it).
- The anchor is `#t<n>` (`n` positive); other fragments (`#bas`, `#haut`, `#formulaire`) are ignored.
- `numreponse=M` (non-zero) gives the anchor `M` when the fragment names none (legacy `searchMatchURL`) **and sets `page` to nil**: HFR answers `forum2.php?…&page=1&numreponse=M` with a redirect to the page holding `M` (R25), so the `page=` of such a link is not the message's page. Legacy read it as page 1 (see differences). The app requests the link and reads the page from the redirect, as legacy did for its final URL (`Common.swift:3364`).
- Print and single-message views of a topic (`print`, `quote_only`, `trash`, `trash_post` other than empty or `0`, captures R21) are not the topic page: `.external`.

## Edge cases
- Host: lookalikes (`forum.hardware.fr.evil.example`, `evilforum.hardware.fr`, `www.`, trailing dot), `user@` and `user:pw@`, `forum.hardware.fr@evil.example`, ports (`:443`, `:80`, `:8443`), `ftp:`, `javascript:`, `mailto:`, app schemes, relative references: all `.external`. An empty port (`https://forum.hardware.fr:/…`) is the same origin and is routed. `http://forum.hardware.fr/…` is routed (ADR 0006 amendment 1: the app upgrades it when requesting).
- Unknown forum segment (`/hfr/NotAForum/…`) or a different case (`/hfr/Apple/…`, the catalogue matches exactly, as legacy did): `.external`. HFR forums the catalogue lacks are therefore opened outside the app until `ForumCatalogue` is completed (pending capture #125).
- Canonical shapes with a zero or non-numeric page or id, extra path segments (`/hfr/a/b/c/slug-sujet_…`), or fewer (`/hfr/slug-sujet_…`): `.external`.
- Intra-topic search results (`forum2.php?…&word=…&currentnum=M#tM`, §7 E28) route to the topic, page and message; the highlighted word is not carried.
- Private-message threads have no known canonical `/hfr/…` form: not routed.
- Not routed (`.external`), each with its evidence: `message.php` (composer), `user/*`, `viewbbcode.php`, `profilebdd.php?pseudo=` (its redirect target is not captured), `/hfr/recherche/pseudo-<name>.htm` (§7b: member-posts URL unsettled), `/hfr/<forum>/nouveau_sujet.htm` and `nouveau_sondage.htm`, `forum2.php3` (old shape in R06, unexplained), `forum.php`, `forum1f.php` with `owntopic=0` or `2` (R3 documents 1 and 3 only), `rss.php`, `wikismilies.php`, assets and account pages.
- The router does not parse text: pulling a link out of clipboard text is LOT-138.

## Fixtures
No new capture, no hand-built page. Tests:
- `HFRLinkRouteTests`: every shape above with anonymized ids, plus the refusals; both URL shapes of bug #106 (canonical `…_2201.htm#t<id>` and `forum2.php?…&page=2201#t<id>`) keep page and message.
- `HFRLinkRouteHostTests`: lookalike hosts, user info, ports, schemes.
- `HFRLinkRouteCorpusTests`: every distinct `href` of the 111 captured pages (over a thousand distinct links). Each forum link is routed or belongs to a listed page kind the router does not own; all nine route kinds occur; topic links equal what `HFRURL` reads from them; every corpus link rehosted on a lookalike host is `.external`.
- `HFRLinkRouteOracleTests`: LOT-002 and LOT-003 oracles, hundreds of page links and permalinks against the legacy values; the category of each canonical permalink equals the `cat` of its own quote link (checks the slug table against the real forum).

Each test was shown to fail with the relevant rule reverted: port check removed, user-info check removed, `numreponse` page rule removed, print/quote views allowed, unusable `page` silently dropped.

## Pending capture
- Site `apple-app-site-association` ([#127](https://github.com/ezzz/HFRnow/issues/127)): which App IDs and paths the site names. It does not change this router (it decides from the URL), but LOT-138 must not claim paths the router sends to `.external`, nor miss the ones it routes.
- Home rows without `id="cat<N>"` and full sub-forum lists ([#125](https://github.com/ezzz/HFRnow/issues/125)): completes the forum list; a forum the catalogue lacks is `.external` today.
- `forum1.php?config=hfr.inc` (no `cat`, a link of a newer capture: which list it opens);
- `forum1f.php?owntopic=0|2` (links of the favourites page, `forum1f.php?config=hfr.inc&owntopic=0&new=1`): meaning not captured; `profilebdd.php?pseudo=` redirect target; `/hfr/recherche/pseudo-<name>.htm`; the AQ RSS feed (LOT-028 still pending its capture): AQ links are tested only through the two topic shapes they are documented to use (`AQFeedItem.link`, `AQPlusView.swift:341-375`).

## Intentional differences from legacy
- Each shape goes to its own screen; legacy opened any `forum2.php` or `/hfr/…` link as a topic, including lists and profiles (`Common.swift:2473-2479`).
- A link with `numreponse` no longer opens page 1: its `page` is nil and the server decides (R25). Legacy read the `page=` of `…page=1&numreponse=M` (`Common.swift:2693-2727`) and the bookmark link has no page (`BookmarksPlusView.swift:143-146` sets page 1).
- An unusable `page` value is refused, not turned into page 1.
- Explicit ports and non-`https`/`http` schemes are refused; legacy only compared the host (`Common.swift:2474`), so `https://forum.hardware.fr:8443/…` was opened as a forum link.
- Print and single-message views are not opened as topic pages.

## Learnings
- A forum link's `page=` is not always the page: with `numreponse=M` the server picks the page (R25), and the topic list rows carry `page=1&numreponse=<last message>` links.
- Swift Testing `arguments:` arrays built from `+` concatenations of string literals can exceed the type-checker's time limit (it fails the whole test target): write the literals out in full.
