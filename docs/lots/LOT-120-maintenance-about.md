# LOT-120 — System-settings shortcut, version, static pages, About

- **Module:** App (`App/SwiftHFR/Settings/`, `App/SwiftHFR/Root/PlusView.swift`)
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** [#211](https://github.com/ezzz/HFRnow/issues/211)
- **Depends on:** LOT-119 (#210, settings screen), LOT-066 (#91), LOT-083 (#101, reader), LOT-095 (#187, link router), LOT-170 (#296, Plus tab)
- **Scope trimmed on 2026-11-09 (operator, [#655](https://github.com/ezzz/HFRnow/issues/655)):** the cache sizes are [LOT-179](LOT-179-cache-sizes.md) (#419, M4, waits on this lot), the cache clearing is LOT-187 (#689, M5). This lot builds the "Maintenance" section with its one row, the system-settings shortcut, and leaves the place for LOT-179 (below).

## Legacy sources
Legacy reference `legacy/duo-inner-cover` @ `87fe0d1c` (AGENTS.md §2; `git show 87fe0d1c:<path>`).

| Legacy @ `87fe0d1c` | Used for |
|---|---|
| `HFRswift/Swift/AppSettingsView.swift:299-302` (`openSystemSettings`) | "Ouvrir les réglages système": `UIApplication.openSettingsURLString` |
| `AppSettingsView.swift:547-577` (`maintenanceSection`) | section "Maintenance": the cache rows (LOT-179) and the shortcut button, in this order |
| `AppSettingsView.swift:180-184, 580-584` (`appVersion`, `aboutSection`) | section "À propos": row "Version" = `CFBundleShortVersionString (CFBundleVersion)`, `?` when a key is missing |
| `HFRswift/Swift/StaticInfoPageView.swift:11-47, 126-137` | the two static pages ("Crédits", "Charte du forum"): bundled HTML in a `WKWebView`; a tapped link is cancelled and handed to `HFRplusAppDelegate.openURL` (`Classes/HFRplusAppDelegate.m:764-777`: default browser when `open_links_in_default_browser`, else `SFSafariViewController`) |
| `HFRswift/Swift/PlusTab.swift:43-53` @ `2440d79` | the Plus rows "Crédits" and "Charte du forum" that open them (built by LOT-170; this lot builds their screens) |
| `SuperHFRplus/Assets/HTML/charte.html` | the charter text, ported **unchanged** (HardWare.fr's own text) |
| `SuperHFRplus/Assets/HTML/credits.html:12, 14-18` | the legal notice and contributors sections; the credited libraries are not used by SwiftHFR (CREDITS.md) |
| `Classes/AideViewController.m`, `SuperHFRplus/Assets/HTML/aide.html` | **not ported** (see Intentional differences) |
| `Classes/OfflineMessagesTableViewController.m:78` (comment) | the id form `forum2.php?config=hfr.inc&cat=25&post=1711&page=…` the operator chose for the topic links |
| `HFRswift/Swift/HTMLPageCacheManager.swift` | LOT-179's source, not read here |

## Legacy counterpart (app lots)
- `Settings/MaintenanceSection.swift` (`MaintenanceModel`, `MaintenanceSection`): `HFRswift/Swift/AppSettingsView.swift` (`maintenanceSection`, `openSystemSettings`).
- `Settings/AboutModel.swift`, `Settings/AboutView.swift`: `HFRswift/Swift/AppSettingsView.swift` (`aboutSection`, `appVersion`) and `HFRswift/Swift/StaticInfoPageView.swift` (`StaticInfoPageKind.credits`); the topic links and the changelog have no legacy counterpart (operator decision 2026-10-28).
- `Settings/StaticPage.swift`, `Settings/StaticPageView.swift`: `HFRswift/Swift/StaticInfoPageView.swift` (`StaticInfoPageKind`, `StaticInfoPageView`, `StaticHTMLWebView`).

## UX evolutions (app lots)
Same UX as legacy for the system-settings shortcut, the version row and the charter. Differences, all under **GAP-151** (row exists: "Crédits, Charte … About links to the app's topics, opened in the app"; no new row):
- **About (`b·operator`, 2026-10-28):** the "Crédits" Plus entry opens an About screen (version and build, the two HFR topic links, "Nouveautés", "Crédits") instead of the bare credits page. Legacy's version row stays in Réglages > À propos too.
- **Links by topic id, opened in the app** (`b·operator`, 2026-10-28): through `ReaderTarget(link:)`, i.e. LOT-095's router, never Safari (legacy `credits.html:12` carries a stale slug; HFR redirects it, `R298e`, so the change is only that the link opens in the app by id).
- **Static pages follow the app's light/dark appearance and Dynamic Type** (`b·needed`): legacy injected its theme CSS; SwiftHFR styles the pages with `color-scheme: light dark` and the system body font, with no theme store dependency.
- **Credits text is SwiftHFR's own** (`b·needed`): it reproduces CREDITS.md and the licence, not the legacy list of libraries SwiftHFR does not use.

## Behaviour
- **Plus > Réglages** gets two sections after the last one, as legacy: "Maintenance" and "À propos".
  - `MaintenanceSection`: one row, "Ouvrir les réglages système" (button), through `MaintenanceModel.openSystemSettings()`, which calls an injected `@MainActor () -> Void` (production: `UIApplication.open(UIApplication.openSettingsURLString)`; tests: a recorder). **Place for LOT-179:** the section is a `Section` whose content is the `cacheRows` slot (empty here) followed by the shortcut; LOT-179 fills `cacheRows` and the footer, and adds its snapshot property to `MaintenanceModel` without touching the shortcut. The footer is absent here (no rule shown before the sizes exist).
  - `À propos`: row "Version" (`AppVersion.display`, `1.0 (42)`), as legacy. The link to About is the Plus entry "Crédits" only: `SettingsView` has no topic page source to open a reader with.
- **Plus > Crédits** opens `AboutView` (`AboutModel`):
  - "Version": `AppVersion` from the main bundle's `CFBundleShortVersionString` and `CFBundleVersion`; a missing key shows `?` (legacy).
  - "Sujets HFR+": two rows, **[TU] Super HFR+** and **Beta**, whose URLs are exactly the operator's id-form links (issue #211, comment of 2026-10-28):
    - `https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=25&post=1711&page=1`
    - `https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=25&subcat=528&post=8811&page=1`
    A row sets `AboutModel.selected`; the screen pushes a `TopicReaderView` for `ReaderTarget(link:)` built from the URL (router: route = topic, category 25, post 1711 / 8811, page 1). No `UIApplication.open`, no Safari. If the router ever stops routing a link as a topic, the row shows nothing to open (a test pins both URLs to a topic route).
  - "Nouveautés": the legacy-fixes changelog, "Résumé (FR)" of [`CHANGELOG-LEGACY.md`](../CHANGELOG-LEGACY.md) as a list per section (UX, T), from the bundled `App/SwiftHFR/Resources/changelog-v1.json` generated by `tooling/docs/export-app-changelog.py` (`--check` reports a stale copy; regenerate after the steward folds rows and before a release; not in CI yet, so an app test does not compare it with the file: it would fail every app PR after a fold).
  - "Crédits": `StaticPageView(.credits)`.
- **Plus > Charte du forum** opens `StaticPageView(.charter)`.
- **`StaticPage`** (`credits`, `charter`): title, bundled resource name (`static-credits.html`, `static-charter.html`, `static-page.css` in `App/SwiftHFR/Resources/`, flat in the bundle), `html()` = the resource with `static-page.css` inserted before `</head>` and a viewport meta. `StaticPageView` hosts a `WKWebView`: JavaScript off (`allowsContentJavaScript = false`), the page loaded with `loadHTMLString(_, baseURL: nil)`, any link activation cancelled and handed to `StaticPage.action(forLink:defaultBrowser:)`: `http(s)` opens in Safari's view in the app, or in the system browser when "Navigateur par défaut" is on; any other scheme is ignored. A forum link in a page goes through the same browser rule as the reader's non-topic links (the pages hold none today).
- **Credits content** = CREDITS.md and LICENSE: lineage table (HFR+ / HFRnow / SwiftHFR with the repository links), app-icon and alternate-icon credits, contributors table, third-party software (SwiftSoup, MIT), licence (PolyForm Noncommercial 1.0.0 and its URL; documentation and fixtures CC BY 4.0), and the legal notice of legacy `credits.html:9-14` adapted to the app's name ("SwiftHFR n'est pas développé par l'équipe du site hardware.fr, mais de manière bénévole"). A test reads CREDITS.md, LICENSE and LICENSE-docs.md (`#filePath`) and checks that every absolute link, the contributor names and the licence names appear in the page. CREDITS.md's relative links (to `docs/`) are not carried: they lead nowhere in the app.
- **Charter content** = `charte.html` of legacy, body unchanged.

## Edge cases
- Missing Info.plist keys: `?` (legacy), never an empty row.
- Missing bundled resource: `StaticPage.html()` returns a "Page introuvable" body (legacy "Fichier introuvable"), never an empty web view. A test requires each resource to be present in the test host, so it cannot ship missing.
- The Apple category (cat 25) is hidden from the forum list for App Review (Q-7), yet the About links open: they go through the router and `TopicPageSource` like any link, not through the category list. Capture #298 (closed, `R298a`-`R298f`, `HFR-PROTOCOL.md` §6c "#298"): both id forms answer 301 to the canonical page then 200, logged out and logged in alike (`R298a`/`R298b` for `cat=25&post=1711`, `R298c`/`R298d` for `subcat=528&post=8811`), so the links open logged out. A stale slug is no risk either (`R298e`/`R298f`: 301 to the current page). Review #329 got a comment saying so.
- A second tap on a link while a reader is open does nothing new (selection is one value).
- Dynamic Type XL: rows wrap (`scaledFont`, no fixed heights); the pages use `font: -apple-system-body`.

## Fixtures
None: no HFR page is read by a parser. The two topic URLs come from the operator's comment; their routing is pinned by `AboutModelTests` through `HFRLinkRoute`, and the server answers are the captures `R298a`-`R298d` (#298).

## Intentional differences from legacy
- **Aide is not ported.** `AideViewController` is only reachable from the ObjC `InfosViewController.m:69` and `TopicsTableViewController.m:758`, neither routed in the SwiftUI app; no `PlusTab.swift` row opens it, and `aide.html` describes ObjC navigation ("Réglages > Mon Compte", long-press shortcuts) that no longer exists. The issue's scope line lists "help": a decision for the operator, reported on #368 (option: a help page written from SwiftHFR's own behaviour, a new lot).
- **Credits list**: legacy lists libraries SwiftHFR does not use (CREDITS.md says so); SwiftHFR lists what it uses.
- **No theme CSS injection** (see UX evolutions); the pages follow the system appearance.
- None for links: a tapped link follows the legacy rule (`HFRplusAppDelegate.openURL`, `Classes/HFRplusAppDelegate.m:764-777`): default browser or Safari's view, never the session.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
