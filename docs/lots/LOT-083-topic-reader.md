# LOT-083 — Topic reader

- **Module:** App (`App/SwiftHFR/Reader/`)
- **Difficulty / model:** difficult (Opus 5.5 → Fable)
- **Issue:** [#101](https://github.com/ezzz/HFRnow/issues/101); also settles the app half of #106, #107 and #108 (LOTS "Issues to open" #5–#7, found by Bybifok)
- **Depends on:** LOT-080 (target), LOT-082 (navigation), LOT-030 (blocks), LOT-033 (page metadata), LOT-034 (normalizer, [#23](https://github.com/ezzz/HFRnow/pull/23)), LOT-045 (fetchers, cookie-less client), LOT-071 (policy C, D-071-1 and D-071-2)

## Legacy sources

Legacy app: `master` of ezzz/HFRnow (read-only), functional reference only; no legacy view or script is copied.

| Legacy | Replaced by |
|---|---|
| `HFRswift/Swift/MessagesView.swift:976` (page written to a file, loaded in a `WKWebView` with file read access, which fetches every `img src` itself) | `ReaderWebController`: page served from the app's `hfrreader:` scheme, CSP, content JavaScript off, images through the app |
| `SuperHFRplus/Assets/HTML/templatev2.htm` (message template, inline `onClick` handlers) | `TopicHTMLBuilder` (escaped values, no handler) + `reader.js` (user script in its own content world) |
| `SuperHFRplus/Assets/HTML/style-liste-light.css:62-132, 349-410` (quotes, spoilers, code, signature) | `Reader/Resources/reader.css` (same class names, Dynamic Type, dark mode) |
| `ObjCTopicHTMLRenderer.m:40`, `style-liste-light.css:130` (`swap_spoiler_states`, `div.masque { visibility: hidden }`) | spoiler toggle in `reader.js` (LOT-034 hand-off) |
| `Wrapped/LinkItem.m:169-226` (`display_images` modes, forced to `yes`) | policy C (`ImagePolicy`, `ImageAutoLoad`, `ImageDecision`) |
| `Wrapped/LinkItem.m:265` (`color:blue` → action colour on `olcode`) | `reader.css` rule on `ol.olcode span[style="color:blue"]` |
| `HFRswift/Swift/Common.swift:2593-2635` (`TopicOpenPolicy`: a flagged row opens at its flag, else at its link) | `ReaderTarget(opening:)` |
| `MessagesView.swift:2492` (external links in `SFSafariViewController`) | same, from `TopicReaderView` |

## Behaviour

**Opening.** Selecting a row in the middle column shows `TopicReaderView` in the detail column (replacing `MessagePlaceholderView`, which
stays for "nothing selected" and rows whose link names no topic page). `ReaderTarget(opening:)` takes the row's flag link (last read
position, with its `#t<numreponse>`) or else its own link (favourites rows already hold their resume link, LOT-024). A link with `cat`
and `post` becomes `forum2.php` through `PageFetcher.topicPage`; a canonical `…-sujet_<post>_<page>.htm` path without a category is
fetched as a path only (forum host, `https`, default port, query and fragment dropped, LESSONS 37/43), and the page's own `TopicID` is
used from then on. A page without any message is classified like a list page (LOT-022): maintenance and login walls are errors with
HFR's text, a `.hop` notice is shown in place of the messages.

**Fetching (E25).** The page the user opens is fetched **once, with the account session** (`.authenticated`): `NavigationModel` keeps
one `TopicReaderModel` per selected topic and `onAppear()` loads only when nothing is shown, loading or failed, so view updates,
rotation and column changes refetch nothing. Nothing is prefetched. Parsing (LOT-033 metadata, LOT-030 blocks, LOT-034 normalizer per
block) runs off the main actor.

**Loading rules (issues #107, #108).** One load at a time; a newer load or `cancel()` (the view disappears) supersedes the older one,
whose result is dropped. The page on screen stays while a load runs and after it fails (banner with "Réessayer", which asks again for the
failed page). Refresh (toolbar) reloads the page on screen, not page 1 nor the page first opened, and keeps the scroll position. Every
successful load makes a new `ReaderDocument` with a unique token; the web view reports "ready" with the token of the document that
reached DOMContentLoaded (user script at document end, after the images are routed), and only the current token counts. The first page
is shown at that moment, not blank before.

**Page navigation.** First / previous / next / last and "Page N / M" (asks a page number, clamped to `1…M`). HFR may serve another
page than the one asked (past the end, `R24`): the reader follows the page served.

**Links.** The web view never navigates: every link tap is cancelled and handed to the app. A forum topic link opens in the reader at
its page and post (issue #106). A link naming a message (`numreponse=M`: bookmarks, AQ, permalinks) names no page: the reader sends
LOT-095's `forum2.php?…&page=1&numreponse=M` and shows the page HFR redirects to (`R25`), at message M. A link to a post of the page
shown scrolls to it without refetching; any other `http(s)` link opens in
`SFSafariViewController` (LOT-071 T8); other schemes do nothing. New windows are refused; link previews (which would load the page) are
off.

**Document (`TopicHTMLBuilder`).** One `article` per message (`id="t<numreponse>"` on the original only, the continuation block repeats
the number), header (avatar, pseudo, date), `MessageContent.html` as body markup, video placeholders, `signatureHTML` when
`display_sig` is on (off by default, as legacy), trailers "Message édité par …" and "Message cité N fois". Context contract of LOT-034:
`html` and `signatureHTML` go into element content only; every other value is escaped (`& < > " '`) by the builder.

**Web view (`ReaderWebController`).** The page, `reader.css` and every image come from the `hfrreader:` scheme handler; the page is
served with the CSP header (repeated as `<meta>`): `default-src 'none'; img-src hfrreader:; style-src hfrreader: 'unsafe-inline';
style-src-elem hfrreader:; style-src-attr 'unsafe-inline'; script-src 'none'; frame-src 'none'; …; form-action 'none'; base-uri
'none'`, `Referrer-Policy: no-referrer`, DNS prefetch off.
Content JavaScript is off; `reader.js` runs as a user script in the app's own `WKContentWorld` and talks to the app through a message
channel registered in that world only. The data store is non-persistent. Style attributes stay allowed because LOT-034 keeps the
sanitized `color:` of user colours and code highlighting there; `<style>` elements are refused, and a CSS `url()` falls under
`img-src`, so it reaches the app's scheme and its policy like any image.

**Images (policy C, D-071-1).** `reader.js` sends the `src` of every image to the app, which answers `load`, `tap` or `block` per URL:

- **Blocked** (`ImagePolicy.classify`, by shape, before any request): non-`http(s)` or user info; any IPv6 literal (mapped, NAT64,
  6to4 and zone forms embed private addresses); a host whose labels are all numeric unless it is a canonical dotted quad (four decimal
  labels, no leading zero) outside `0/8, 10/8, 100.64/10, 127/8, 169.254/16, 172.16/12, 192.0.0/24, 192.168/16, 198.18/15, 224/4,
  240/4`; names without a dot; `.local`, `.localhost`, `.home.arpa`, `.internal`, `.lan`; hosts with percent-encoding or characters
  outside `[a-z0-9.-]`; `*.hardware.fr` URLs other than `forum-images.hardware.fr` unless the path ends in an image extension. Shown as
  their URL (a link the user may open, T8; plain text inside an existing link).
- **Forum images** (smileys, avatars, `forum-images.hardware.fr`): loaded.
- **Third-party images:** loaded when the image mode allows it, else a "toucher pour charger" placeholder; nothing is requested before
  the tap. Mode: `display_images` (`always`; `wifiOnly` = unmetered Wi-Fi or Ethernet, `NWPathMonitor` started at launch;
  `never` = tap), default `wifiOnly`. FEAT-011 adds the settings screen.

**Consent lives in the app.** A tap on a placeholder makes `reader.js` post `{type: "tap", token, url}`; the controller records
that exact third-party URL for the current document (cleared with every new document) and only then does the script ask for the image.
The scheme handler decides again for every image request and honours a tap only for a recorded URL: the page's own markup can name the
`hfrreader:` scheme (an `img`, a CSS `url()`), and WebKit's preload scanner requests it before `reader.js` runs, so nothing in an image
URL counts as consent. Downloads go through `ReaderImageFetcher`: `AnonymousTransport` (no cookie, no `Referer`, no cache), redirects
followed one hop at a time with the policy on each hop (a hop to a third party is allowed when the image was a third-party one the user
allowed, or when the mode loads third parties), at most 5 hops, `image/*` only, at most 6 downloads at once, 15 MB at most: the
transport stops reading past the cap or on a larger `Content-Length` (`HTTPRequest.maximumBodyBytes`, HFRNetwork). `http` is requested over `https` (see Decisions).

**Videos (D-071-2).** Each `MessageContent.embeds` entry is a placeholder button (provider name, no provider URL in the page). A tap
opens `VideoPlayerSheet`, a separate web view (JavaScript on, non-persistent store) that loads the embed URL only when it is `https` on
its provider's hosts and keeps its main frame there. The reader's web view never hosts a player frame. Until LOT-035 fills `embeds`,
no placeholder appears.

**Accessibility.** Text uses `-apple-system-body` (Dynamic Type), dark mode follows the system; each message is an `article` labelled
"Message de <pseudo>, <date>"; placeholders are buttons with a label; page controls have labels. iPhone and iPad share the view (the
split view collapses on compact widths).

## Decisions taken here

Confirmed by the orchestrator on 2026-10-28, consistent with the operator's decisions.

- **`http`-only image hosts** (the decision D-071-1 point 4 left to this lot): **no App Transport Security exception**. `http` images
  are requested over `https`; a host that does not answer there shows the image as its URL. Measuring which captured hosts upgrade
  stays a pending capture.
- **Blocked IPv6**: every IPv6 literal is refused, not only the ranges D-071-1 lists. Deliberately stricter: mapped, NAT64, 6to4 and
  zone forms embed private addresses, and no capture holds a public IPv6 image.
- **Default image mode** (operator decision): automatic on Wi-Fi or Ethernet, tap on cellular. `SettingKey.displayImages` now
  defaults to `wifiOnly` (it defaulted to `always`, legacy's forced value); a value stored by the user or imported from legacy is kept
  (`LegacySettingsNormalizer` does not force it). FEAT-011 adds the screen.

## Edge cases

- The view appears again (rotation, column change, reselecting the same row): same model, no refetch.
- A page beyond the last: HFR serves the last page; the reader shows it and its number.
- An anchor not on the page served: the document opens at the top.
- A huge page: one document per page (≈40 messages); the web content process can be killed under memory pressure, then the same
  document is served again from memory (the topic page is not refetched).
- An image request after the document changed: the scheme serves only the current document; stopped tasks are never answered.

## Fixtures

Captures `R20`, `R21`, `R22a`, `R26`, `R27`, `R27b`, `R28`, `R31` and `R08-1` (a `.hop` notice) through the real LOT-030/033/034 chain (read from `Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures/`) feed
`LiveTopicPageSourceTests`. Tests (`App/SwiftHFRTests/Reader/`): `ImagePolicyTests` (every host spelling of LOT-071 and its neighbours),
`ReaderImageFetcherTests` (cookie-less, redirects, types, size, https upgrade, setting), `ReaderTargetTests` (both URL shapes of #106,
message links and legacy bookmarks, flag rows), `TopicHTMLBuilderTests` (escaping, context, CSP, signature, anchors, video), `TopicReaderModelTests` (E25 once, #107, #108,
links, pages), `LiveTopicPageSourceTests` (session vs cookie-less transport; real pages render their normalized content as body markup in the content element only, signatures per `display_sig`, notices) and `ReaderWebControllerTests`, which drive a
real `WKWebView`: no page script or handler runs, only allowed images reach the client, a tap loads a third-party image, a link tap
leaves the page to the app, the stylesheet loads and a spoiler opens, only the latest document reports ready, markup cannot forge a
tap (preload and CSS `url()`), a tap consents to one URL in one document, a local server sees no request from remote `src`, `href`
or `url()`, `<style>` elements are refused while colour attributes apply, downloads are throttled, redirects follow the setting, and a
real page (`R28`) requests only forum images before a tap.

**Pending capture:** a logged-in topic page opened by the reader marks its flag read (E25 is from legacy code and HFR-PROTOCOL §7);
`http`-only image hosts over `https` (LOT-071 backlog row, shared with LOT-056).

## Intentional differences from legacy

1. No file URL and no file read access: the page and its resources come from the app's scheme, under a CSP; no remote script, no
   handler, no `javascript:` (legacy loaded jQuery and inline `onClick` handlers).
2. Images are fetched by the app without cookies or `Referer`, after policy C (legacy: WebKit fetched every `src`, private hosts included).
3. Videos are placeholders; the player opens on tap in its own view (legacy at `2440d79`: auto-loaded iframes).
4. A flagged topic opens at its flag with the anchor, refresh keeps the page on screen, a cancelled load never completes the next
   (Bybifok's findings #5–#7).
5. No prefetch: legacy loaded neighbouring pages with the shared jar and marked flags read.

## Learnings

- `WKWebpagePreferences.allowsContentJavaScript = false` keeps user scripts of another `WKContentWorld` and their message channel
  working: the page runs nothing while the app's adapter script still runs.
- Serving the page through a `WKURLSchemeHandler` lets the CSP arrive as a response header, before any markup (and before WebKit's
  preload scanner); `img-src <scheme>:` then confines every image to the handler.
- A reader test can drive a real `WKWebView` from the app-hosted Swift Testing bundle. On a cold CI simulator, host the web view in
  a `UIWindow`, serialize the suite and use long deadlines; otherwise the tests time out.
- A tap flag in a URL is not consent when the page can write URLs of that scheme: WebKit's preload scanner requests `img src`
  before any script runs. Keep consent in the app, keyed by the exact URL and the document.
