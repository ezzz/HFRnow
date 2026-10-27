# LOT-071 — Third-party services: inventory, data sent, notices, configuration

- **Module:** docs
- **Difficulty / model:** easy · Opus → Fable (author → reviewer)
- **Issue:** old [francoisgn/ios-app_SwiftHFR#91](https://github.com/francoisgn/ios-app_SwiftHFR/issues/91) (frozen history)
- **Inputs:** [audit README](../audit/README.md) Q-4, Q-7, Q-10 · [ADR 0007](../adr/0007-third-party-api-keys.md) ·
  [HFR-PROTOCOL §8](../HFR-PROTOCOL.md#8-third-party-services) · audit [D](../audit/D-posting.md) §2.7, §3.2, §5 and
  [E](../audit/E-storage-vendors.md) §5–6 · LOT-034 image hand-off ([PR #23](https://github.com/ezzz/HFRnow/pull/23))

Every host outside `*.hardware.fr` that the legacy app contacts or that SwiftHFR will contact, what each one receives, who runs it,
how it is configured and what the user is told. The lots that implement each service (LOT-028, 055, 056, 083, Phase 4 GIFs) apply
the rules below; a PR that makes the app contact a new third-party host adds its row to the inventory first.

## Legacy sources

Legacy citations are `HFRswift/…` files of <https://github.com/francoisgn/hfrnow> @ `2440d79` (the live Swift app), unless the row says
`Classes/…` (Objective-C app, not compiled into HFRswift). Grep of every `http(s)://` literal of `HFRswift/`, `Classes/` and `Extensions/`.

| Service | Legacy code |
|---|---|
| AQ RSS badge, at launch | `Swift/MainWindow.swift:1178-1192` (3 s after the main window appears, once per process, logged out too; called from `:1422`, `:1448`), `Swift/AQPlusView.swift:39, 52-57, 69-90` |
| AQ "already reported" check | `Swift/MessagesView.swift:325-338` (`URLSession.shared`, body searched for the post id), called on the AQ action (`:2001`, `:3716`) |
| AQ create | `Swift/MessagesView.swift:340-399` (POST, 5 s, ASCII body with lossy conversion, response `"1"` = success) |
| AQ, older host | `Classes/OnlineMessagesTableViewController.m:2307, 2443` (`http://alerte-qualitay.toyonos.info/…php5`): not compiled into HFRswift, not carried over |
| Image rehost upload (Chevereto) | `Swift/ReplyService.swift:1970` (`img3.super-h.fr/api/1/upload/?key=…`), `:1984-1997` (JPEG quality 1.0, cookies off, file name `snapshot_<random>.jpg`), `:2045-2055` (multipart, constant `imageCaption`) |
| Rehost hosts in the viewer | `Swift/MessagesView.swift:2175, 2205-2210, 3301-3306` (`reho.st/thumb/` → full, `rehost.diberie.com/Picture/Get/t/` → `/f/`, `img3` thumbnails), `Wrapped/LinkItem.m:163` (`hfr-rehost.net` → `reho.st`); dead `reho.st/upload` code in `Classes/RehostImage.m:140-168` |
| Giphy | `Swift/HFRswiftApp.swift:9, 20` (SDK configured at launch with an embedded key; value deliberately not copied), `Swift/AnswerView.swift:533, 2305-2335` (picker, rating R, inserts `[img]<gif URL>[/img]`); binary `GiphyUISDK.xcframework` 2.1.7 (audit E §6) |
| Images in messages | `Wrapped/LinkItem.m:161-226` (`display_images` modes), forced to `yes` at every launch by `Classes/HFRplusAppDelegate.m:115-116` (audit C §1.3); topic page loaded from a file URL into a `WKWebView` that fetches every `img src` itself (`Swift/MessagesView.swift:976`) |
| Photo viewer | `Swift/MessagesView.swift:2444-2447, 5749-5762`: `URLSession.shared` (the jar that holds the forum cookies, domain `.hardware.fr`, audit A §4.1), `Referer: https://forum.hardware.fr` for `reho.st` only |
| Video embeds | `Wrapped/ParseMessagesOperation.m:238-300` (`embedded_videos` `yes`/`both`: YouTube, Vimeo, Streamable links become players; Dailymotion, Coub, Twitch commented out), `Wrapped/LinkItem.m:149-158` (`<iframe src=…>`); setting default `yes` (`Swift/AppSettingsView.swift:104`) |
| External links | `Swift/MessagesView.swift:2492`, `Swift/UserProfileView.swift:623` (`SFSafariViewController`, on tap) |
| Hard-coded mail address | `Swift/MessagesView.swift:3774` (illegal-content report fallback), `Swift/PlusTab.swift:119` (account deletion request), `Wrapped/MessagesTableViewController.m:2606` |
| Analytics, crash reporting | none: no Firebase, Crashlytics, Sentry, MetricKit or other SDK (audit E §6.2; grep of the three trees on 2026-10-27) |
| Legacy-only links | `Classes/PayViewController.m:77` (`apps.flkone.com` donation page), `HFRplus/HFRplus.plist:14` (ad-hoc IPA on `raw.githubusercontent.com`): not compiled into HFRswift, not carried over |

## Inventory

"Data" lists what the request carries beyond what every request reveals (IP address, time, `User-Agent`).
Owner = who runs the host; none of them is this project or HFR.

| # | Service | Hosts | Trigger (legacy) | Data sent | Owner | SwiftHFR lot | Status |
|---|---|---|---|---|---|---|---|
| T1 | AQ RSS feed (badge "new since") | `aq.super-h.fr` | automatic, at launch | nothing else | community operator of `super-h.fr` | LOT-028 (parser), LOT-055 (client), FEAT-001 | kept (Q-4), notice rule N3 |
| T2 | AQ per-topic check | `aq.super-h.fr` | user opens the AQ action | topic id (says which topic the user reads) | same | LOT-055 | kept (Q-4) |
| T3 | AQ create | `aq.super-h.fr` | user confirms an AQ | pseudo (lower case), topic id and title, post id and permalink, post author, free-text title, comment `post de <author>`; unauthenticated, so anyone can post as anyone | same | LOT-055 | kept (Q-4), notice N1 |
| T4 | Image rehost (Chevereto) | `img3.super-h.fr` | user uploads an image in the composer | the image (re-encoded JPEG, downscaled to the user setting), the API key in the query; no cookie. The uploaded image becomes public; no delete API is evidenced (HFR-PROTOCOL §7b B12). Whether the re-encode strips EXIF/GPS is unverified (audit D §10 Q9) | community operator of `super-h.fr` (also owns the key, ADR 0007) | LOT-056 | kept, notice N1 |
| T5 | GIF search (Giphy) | Giphy API and CDN | user opens the GIF picker | search terms; the closed SDK may send more (not audited). The chosen GIF URL is posted, so every reader then loads it from Giphy's CDN (T6) | Giphy | Phase 4 (E-10) | undecided (ADR 0007): no SDK without an ADR (AGENTS.md §3.3) |
| T6 | Images in messages and signatures | any host a poster chose | displaying a page | an image request per URL; `Referer` and cookies depend on who fetches (see rules R3, R4) | the host's operator, unknown | LOT-034 (lists `MessageImage`), LOT-045 (cookie-less client), LOT-056 (host table), LOT-083 (loading), FEAT-011 (setting) | **decided**: D-071-1 |
| T7 | Video players | `www.youtube.com`, `player.vimeo.com`, `streamable.com` (legacy active list) | displaying a page with a matching link (`embedded_videos`) | a player iframe: the provider's page, scripts and cookies, loaded without a tap | the provider | LOT-035 (detection), LOT-083 (display) | open: Q-071-1 |
| T8 | External links | any | user taps a link | normal browsing in `SFSafariViewController` (Safari's own data, not the app's) | the site | LOT-083 | unchanged, no notice (user-initiated navigation) |

Seen in the captures: the `img` elements of the topic captures `R20`–`R28`, `RA*`, `RU*` reference 24 third-party hosts (for example
`i.imgur.com`, `rehost.diberie.com`, `i85.servimg.com`, `media.tenor.com`, `i.redd.it`, `casimages.com`, `hostingpics.net`); 10 of them
are `http://` only (`hostingpics.net`, `casimages.com`, `free.fr`, `photorapide.com` and others, mostly in `R28`). No capture holds a
`reho.st` or `img3.super-h.fr` image.

Not third-party services of the app:

- **HFR's own page chrome**: every captured HTML page carries Google ad scripts (`securepubads.g.doubleclick.net`) and a tracking pixel
  (`tracking.groupe-ldlc.com`). SwiftHFR never renders the chrome: parsers read the page and fetch nothing, the reader renders only the
  normalized `MessageContent` without remote scripts (LOT-034, LOT-083). Legacy did the same.
- **`marc@hardware.fr`** (Q-10): an HFR address used through the system mail composer, so the user sends the mail. It stays out of source,
  as configuration, decided per feature (Phase 4).
- **Apple**: App Store crash reports and analytics are the device owner's choice in iOS settings; the app links no SDK for them.

## Rules for SwiftHFR

Decided before this lot (cited) and decided here (D-071-1). Each lot implementing a row of the inventory applies them and tests them.

- **R1 — No forum cookie leaves `*.hardware.fr`** (HFR-PROTOCOL §5 session isolation, LOT-042, LOT-045): account sessions contact only
  `*.hardware.fr`; every third-party request (T1–T6) goes through a cookie-less transport (`AnonymousTransport`). Legacy sent AQ and
  viewer requests through `URLSession.shared`, so a `*.hardware.fr` URL opened in the photo viewer carried the session cookies.
- **R2 — Keys and base URLs are configuration** (ADR 0007, Q-10): engine clients take them as parameters; a build without a key disables
  the feature with a clear message. The configuration names are set by the first lot that needs each one (LOT-055, LOT-056), in the
  untracked key file of ADR 0007 / ADR 0012, and listed in that lot's spec. AQ's base URL is configuration too.
- **R3 — No `Referer` to third parties**, except for a host that needs it in the LOT-056 host table (`reho.st`, reported by redface2,
  HFR-PROTOCOL §7 E26: **pending capture**). The reader document must not leak its own URL either (LOT-083: a `no-referrer` policy or
  images fetched by the cookie-less client).
- **R4 — Image loading** follows D-071-1.
- **R5 — No analytics or crash-reporting SDK.** Adding one is a new dependency: ADR, maintainer approval (AGENTS.md §3.3) and a row here.
- **R6 — The inventory is the allow-list**: the app contacts no third-party host for a feature that is not in it. Images (T6) and links
  (T8) are open by nature and governed by R4 and the user's tap.

### First-use notices

Q-4 decided: AQ is kept with a first-use notice. The same rule applies to every service that sends user data (proposed here, applied by
LOT-055, LOT-056 and the Phase 4 GIF lot):

- **N1 — Before the first request** that sends user data (T3, T4, T5), a notice says: the host and who runs it (not HFR, not this app),
  what is sent (the "Data sent" cell above, in plain words), that the result is public when it is (AQ, uploaded images), and that the
  operator's terms apply. Two choices: continue, or cancel (nothing is sent). Accepted once per service and per device; the choice is
  stored in the settings store (LOT-060) and can be reset in Settings.
- **N2 — Read-only checks** (T2) are covered by the AQ notice: the check runs only after the user accepted it.
- **N3 — Automatic contacts** (T1, the launch-time RSS badge) start only once the AQ notice was accepted; before that the badge and the AQ
  feed (FEAT-001) show an entry that leads to the notice. Legacy contacted `aq.super-h.fr` at every launch, logged out included.
- **N4 — Wording** stays factual and short; it is written in the app lot that shows it, and reviewed against this table.

## Decision D-071-1 — Image loading in the topic reader

**Decided by the operator (francoisgn), 2026-10-27:** option **C**.

Context: the parser (LOT-034) treats any `http(s)` `src` as an image, as legacy did, and leaves the policy to the reader. Legacy loaded
every image as soon as the page was shown (`display_images` forced to `yes`), so each reader's device requested any host a poster chose:
third parties learn the reader's IP and reading time, and a post can make every reader request a private address
(`http://192.168.1.1/…`, router or LAN pages) or a non-image forum URL (`https://forum.hardware.fr/user/logout.php`).

Options considered:

| Option | Rule | Outcome |
|---|---|---|
| A | Keep legacy: auto-load every `http(s)` image | rejected: private/LAN requests and IP leak to any host |
| B | Block private/LAN hosts and non-image `*.hardware.fr` paths; auto-load third-party images | rejected (was the orchestrator's recommendation) |
| C | B, and third-party images load only on tap or according to the image-loading setting (FEAT-011) | **chosen** |

A relay or image proxy run by the project was not offered, for the same reason ADR 0007 set aside an operated relay.

What C means, for LOT-083 (which applies it) and FEAT-011:

1. **Never loaded**, whatever the setting or a tap: hosts that are IP literals or names in private, loopback, link-local or
   unique-local ranges (IPv4 `10/8`, `172.16/12`, `192.168/16`, `127/8`, `169.254/16`, `100.64/10`; IPv6 `::1`, `fc00::/7`,
   `fe80::/10`), names without a dot and `.local` names; and `*.hardware.fr` URLs that are not an image path (the
   `forum-images.hardware.fr` smiley and avatar paths are images). The image shows as a link, which the user may still open in the browser
   (T8). The block happens before any request, in the reader, not in the parser.
2. **Third-party images** load on tap, unless the image-loading setting (`display_images`, `ImageDisplayMode`, FEAT-011) allows
   automatic loading (`always`, or `wifiOnly` on Wi-Fi). Legacy's "never" mode becomes the tap-to-load placeholder. The setting's
   default for SwiftHFR is FEAT-011's decision; until FEAT-011 ships, the reader behaves as tap-to-load.
3. **HFR images** (smileys, avatars, `forum-images.hardware.fr` paths) are first-party and load normally.
4. Every image request follows R1 and R3: cookie-less, no `Referer` unless the host table says so. `http://`-only hosts (10 of 24 in
   the captures) need an App Transport Security decision in LOT-083 (exception for images vs. https upgrade vs. broken image); measure it
   on the Mac.

## Open question for the operator

- **Q-071-1 — Video players (T7).** Legacy turns YouTube, Vimeo and Streamable links into player iframes that load without a tap
  (`embedded_videos=yes` by default), which loads the provider's scripts and cookies, against the "no remote scripts" line of LOT-083.
  Options: (a) keep legacy auto-players; (b) a placeholder that loads the player on tap (same spirit as D-071-1); (c) links only, opened
  in the browser. Decided in LOT-083 or LOT-035 once the operator chooses; not decided here.

Already open elsewhere, not reopened here: whether to keep GIF search and how (ADR 0007, audit E-10, Phase 4).

## Edge cases

- A poster's image URL that redirects: the block rules of D-071-1 apply to every hop (a public host redirecting to a private address),
  as LESSONS 30 and 37 apply to sessions.
- An image inside a link: blocking the image does not follow the link; the link stays a tap-only navigation (T8).
- Hosts given as decimal or hex IPv4 (`http://3232235777/`) or IPv4-mapped IPv6 are IP literals: they are parsed by the URL type before
  the range check, not matched as text.
- A user who accepted a notice and then switches account: notices are per device, not per account (the data sent includes the pseudo, so
  the notice names "your pseudo", not a specific one).

## Fixtures

No new fixture. Facts come from the legacy code above and from the topic captures `R20`–`R28`, `RA*`, `RU*` (image hosts, page chrome).

**Pending capture** (added to the Capture backlog in [LOTS.md](../LOTS.md)): a `reho.st` image fetched cookie-less with and without
`Referer: https://forum.hardware.fr/` (settles HFR-PROTOCOL §7 E26 for the LOT-056 host table), and one `http://`-only image host of
`R28` requested over `https` (does it upgrade?). Plain GETs, no account, no upload. The AQ captures are already in the backlog (LOT-028).

## Intentional differences from legacy

- AQ, check and badge contact `aq.super-h.fr` only after the AQ notice is accepted (legacy: at every launch, no notice).
- No forum cookie on any image or third-party request (legacy viewer used the shared jar).
- Images: D-071-1 replaces automatic loading of every host.
- Third-party keys and base URLs out of source (ADR 0007).
- Giphy SDK not carried over (AGENTS.md §3.3); GIF search is a Phase 4 decision.

## Learnings

- The legacy app contacts a third party with no user action (AQ RSS at launch): an inventory must list triggers, not only endpoints.
- HFR's own pages embed ad and tracking scripts; rendering only normalized content is what keeps them out of the app.
