# Gap report: legacy app vs SwiftHFR (final form)

**Role of this file:** the feature-by-feature gap between the legacy app and SwiftHFR **as its specs define it once every lot of M1 to M4 is delivered** (directive G.3, issue [#368](https://github.com/ezzz/HFRnow/issues/368)). It is the input of the convergence work H.1 (separating the port of ezzz's Swift layer from the UX changes). It is a snapshot: it changes only when a spec or a convergence decision changes a row.

- **Legacy** = `master` of ezzz/HFRnow at commit `2440d79`. A bare `Name.swift` is `HFRswift/Swift/Name.swift`; a bare `Name.m` is `Classes/Name.m`; `HTML/` is `SuperHFRplus/Assets/HTML/`. Every line was checked at `2440d79` (not at `origin/master`, which has drifted: LOT-119 and LOT-170 cite `master` lines, e.g. `usesSidebarRoot` is `MainWindow.swift:1353` there and `:1132` here).
- **SwiftHFR final** = `docs/LOTS.md` scope, the lot spec under `docs/lots/` when it exists, the lot issue otherwise, and [FEATURES.md](../FEATURES.md) with its UX principles. Not the current `App/` code.
- **Gap**: `same` · `ported with changes` (same feature, different details, no visible UX change) · `UX change` (user-visible difference) · `new` (not in legacy) · `dropped` (removed on purpose by a spec) · `not planned` (legacy feature no lot covers).
- **Source**: `port: ezzz Swift layer` (the behaviour comes from `HFRswift/Swift`) · `port: legacy ObjC` · `new UX: operator` · `new UX: Bybifok (FEAT-xxx)` · `new UX: spec` (a lot spec decided it) · `—` (not planned).
- **H.1** (convergence classification, directive H.1):
  - `a`: a port of ezzz's Swift layer at `2440d79`, or of the ObjC app where the Swift layer had nothing. Technical changes only (new engine, iOS 27 APIs, robustness, added themes with unchanged defaults).
  - `a·master`: a port of ezzz's later Swift layer on `master`, absent at `2440d79` (UXD-01).
  - `b`: a UX evolution, in M5 ([#379](https://github.com/ezzz/HFRnow/issues/379), decided 2026-11-02) unless a decision keeps it in M1–M4.
  - `b·needed`: an evolution that parity needs (security, privacy, App Review, an HFR fact).
  - `b·operator`: an evolution the operator already decided.
  - `—`: not planned or dropped.
  - The decision of each UXD row is in [UX decisions of 2026-11-02](#ux-decisions-of-2026-11-02).
- Row ids `GAP-NNN` are stable: a later revision edits a row in place or appends a new id, never renumbers. Rows were extracted per area by Sonnet sub-agents and merged; duplicates across areas keep one row. A second Sonnet agent checked a sample of 20 legacy citations: 10 exact, 9 imprecise ranges and 1 wrong (all 10 corrected). Expect line ranges elsewhere to be approximate: check a ref before quoting it in a spec.

Visual comparison (mock-ups, not captures): [iPhone 16 and 18 Pro Max](../assets/gap-legacy-vs-swift-1-iphone.png) · [iPhone Duo](../assets/gap-legacy-vs-swift-2-duo.png), source [`docs/assets/gap/`](../assets/gap/gap.html) (`node docs/assets/gap/render.js`).

## Navigation

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-001 | Root tab bar (iPhone) | TabView Catégories (folder.fill), Favoris (star.fill), Messages (envelope), Plus (ellipsis). | MainWindow.swift:1268-1298 | Same four tabs, same order and symbols. | LOT-170 | same | port: ezzz Swift layer | a |
| GAP-002 | Start tab | Favoris hard-coded at launch; no start-screen setting at this commit. | MainWindow.swift:1110-1112 | Start-screen setting, default Favoris (values from `master`'s `HFRswiftStartupScreen`). | LOT-119, LOT-170 | ported with changes | port: ezzz Swift layer | a·master |
| GAP-003 | Tab bar minimize on scroll | `.onScrollDown` driven by `tabbar_minimize_on_scroll`, default on. | MainWindow.swift:1264; Common.swift:208-210 | Same key and behaviour, refreshed live without relaunch. | LOT-170 | same | port: ezzz Swift layer | a |
| GAP-004 | MP badge on Messages tab | Badge from the `nb_mp` counter when `mp_badge_enabled`. | MainWindow.swift:1290 | Badge from the home-page MP count, no `nb_mp` counter. | LOT-170, LOT-126 | ported with changes | port: ezzz Swift layer | a |
| GAP-005 | AQ badge on Plus tab | Plus badge shows the unread AQ count, checked 3 s after launch. | MainWindow.swift:1297, 1178-1196 | Plus badge once the AQ feed lands. | LOT-133 | same | port: ezzz Swift layer | a |
| GAP-006 | Plus menu | Seven rows: Réglages, Rechercher, Bookmarks, Alertes Qualitay, Crédits, Charte, Supprimer mon compte. | PlusTab.swift:16-64 | Same seven rows in the same order, filled by their lots. | LOT-170 | same | port: ezzz Swift layer | a |
| GAP-007 | Tab reselect refreshes | Reselecting a root tab reloads its list with a haptic. | MainWindow.swift:1399-1416 | Not specified by LOT-082 or LOT-170. | — | not planned | — | — |
| GAP-008 | Tab bar in the reader | The reader hides the tab bar in three paths: the favourites post-filter reader, `openInternalTopic` and `handleSearchResult`. | Favorites.swift:807; MessagesView.swift:3256, 3909 | Hidden while a topic is open (UXD-02, #424, decided 2026-11-02). **Kept despite the HIG** (Tab bars: "Make sure the tab bar is visible…"), by the operator's decision of 2026-11-07. | LOT-083, LOT-170 | UX change | new UX: spec | b |
| GAP-009 | Account menu | Leading avatar menu in list toolbars: switch, add pseudo, logout. | MainWindow.swift:235-262; MainToolbar.swift:57-64 | Account menu in the Plus and Catégories toolbars only. | LOT-170, LOT-081 | UX change | new UX: spec | b |
| GAP-010 | Home-screen quick actions | Declared in the ObjC target's Info.plist; the handler body is commented out. | SuperHFRplus-Info.plist:235-275; HFRplusAppDelegate.m:311-345 | Follow-up named by LOT-170, no lot. | — | not planned | — | — |
| GAP-011 | MP notification tap | Opens the Messages tab and force-refreshes it. | Common.swift:32-48; MainWindow.swift:1218-1221 | Notification flow kept; tap destination not specified. | LOT-140, LOT-091 | ported with changes | port: ezzz Swift layer | a |
| GAP-012 | Universal links | `continueUserActivity` is an empty stub. | HFRplusAppDelegate.m:844-853 | Share, clipboard and universal links open in the app. | LOT-138, FEAT-020 | new | new UX: Bybifok (FEAT-020) | b |
| GAP-013 | State restoration | Only the selected tab, in a static var lost on relaunch. | MainWindow.swift:1110-1112 | Per-scene restore of forum, topic, page and position. | LOT-145, FEAT-015 | new | new UX: Bybifok (FEAT-015) | b·operator |
| GAP-014 | Keyboard shortcuts | None (no `keyboardShortcut` or `UIKeyCommand`). | — | J, K, Q, R, ⌘F on iPad. | LOT-149, FEAT-021 | new | new UX: Bybifok (FEAT-021) | b |
| GAP-015 | Spotlight | None. | — | Read topics indexed in Spotlight. | LOT-150, FEAT-021 | new | new UX: Bybifok (FEAT-021) | b |
| GAP-016 | Home "À suivre" | None; start tab is Favoris. | — | Opt-in Home (resume, MPs, super favourites, flags, AQ), never the default. | LOT-143, LOT-144, FEAT-001 | new | new UX: Bybifok (FEAT-001) | b·operator |

## Lists

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-020 | Catégories list | Flat list of categories with icon and "N sous-forums", each pushing a topic list. | MainWindow.swift:129-232 | Collapsible sections: "Tous les sujets" then the sub-forums. | LOT-082, LOT-168 | UX change | new UX: spec | b |
| GAP-021 | Category icons | 28 pt template image per forum, `folder.fill` fallback. | MainWindow.swift:895-922 | Not specified. | — | not planned | — | — |
| GAP-022 | Sub-forum choice | Menu picker at the top of the topic list. | MainWindow.swift:596-611 | Sub-forums are rows of the Catégories sections. | LOT-082 | UX change | new UX: spec | b |
| GAP-023 | Topic filter Tous / Favoris / Suivis / Lus | Segmented control on forum lists, persisted. | MainWindow.swift:613-640 | No per-forum filter; a Favoris / Drapeaux picker in the Favoris tab. | LOT-082, LOT-170 | not planned | — | — |
| GAP-024 | Forum list paging | Pager first / previous / "N / last" / next / last plus a page sheet. | MainWindow.swift:926-1000 | "Page N" without a fake total; last page only when the count is exact. | LOT-082, LOT-167, FEAT-003 | UX change | new UX: Bybifok (FEAT-003) | b·needed |
| GAP-025 | Refresh | Pull and toolbar refresh reload the list. | MainWindow.swift:712-723 | Reloads the page on screen, rows kept, retry banner on failure. | LOT-082 | ported with changes | new UX: spec | a |
| GAP-026 | Topic row layout | Title 14.3 pt, unread capsule, footer "⚑ cur / max" and "author - date". | Favorites.swift:988-1006, 1014; Common.swift:3095-3160 | Legacy Favoris density is the reference, but the LOT-082 row shows "author · replies · relative date". | LOT-082, LOT-169 | UX change | new UX: spec | b |
| GAP-027 | Flag row tint | Row tinted by flag colour (yellow, blue, red). | MainWindow.swift:408-424; Common.swift:702-722 | Not specified. | — | not planned | — | — |
| GAP-028 | Topic context menu | Première page, Dernière page, Dernière réponse, Page numéro…, Copier le lien. | Common.swift:3050-3093 | Uniform swipes and menus; only Lu, Dernière page, Super favori, Retirer are named. | LOT-125, FEAT-008 | ported with changes | port: ezzz Swift layer | b |
| GAP-029 | Swipes | Leading "Lu", trailing "Supprimer"; super favourite in the menu only. | Favorites.swift:1073-1097 | One set in every list: Lu with "Annuler", Dernière page, Super favori, Retirer. | LOT-125, FEAT-008 | UX change | new UX: Bybifok (FEAT-008) | b |
| GAP-030 | Favourites grouping | Grouped by forum with a count, or flat by last post. | Favorites.swift:293-396 | Grouped by category, sort by last post kept as an option. | LOT-124, LOT-082 | same | port: ezzz Swift layer | a |
| GAP-031 | Collapsible sections | Chevron per section, persisted; toolbar toggle. | Favorites.swift:139-155, 725-735 | Collapsed sections kept. | LOT-124 | same | port: ezzz Swift layer | a |
| GAP-032 | Flags and favourites together | Mode "Drapeaux & Favoris" or "Favoris uniquement". | AppSettingsView.swift:121-124 | Picker Favoris / Drapeaux, merged mode back with LOT-124. | LOT-170, LOT-124 | ported with changes | port: ezzz Swift layer | a |
| GAP-033 | Super favourites | Local set, orange-tinted row. | Favorites.swift:112-137; Common.swift:686-689 | Section, tint and swipe; set synced by iCloud KVS. | LOT-124, LOT-125, LOT-172 | ported with changes | port: ezzz Swift layer | a |
| GAP-034 | Mark read (Lu) | Local only, nothing sent to HFR. | Favorites.swift:841-848 | Lu with "Annuler", kept until refresh. | LOT-125 | UX change | new UX: Bybifok (FEAT-008) | b |
| GAP-035 | Remove favourite | Menu and trailing swipe remove the flag. | Favorites.swift:848-872 | "Retirer" through confirmed flag writes. | LOT-125, LOT-051 | same | port: ezzz Swift layer | a |
| GAP-036 | Filter posts from favourites | Menu "Filtrer les posts" with a progress banner. | Favorites.swift:743-780 | Filtered-posts flow and its view. | LOT-093, LOT-114 | same | port: ezzz Swift layer | a |
| GAP-037 | Logged-out lists | Inline sign-in prompt on Favoris and Messages. | Favorites.swift:600-612 | "Connexion requise" screen; Catégories works logged out. | LOT-082, LOT-081 | same | port: ezzz Swift layer | a |
| GAP-038 | Apple category for App Review | Hidden in the ObjC era (audit Q-7). | — | Category 25 hidden logged out and for the review account. | LOT-082 | ported with changes | new UX: spec | a |
| GAP-039 | AQ list | Plus entry: initiator, relative date, refresh. | AQPlusView.swift:405-441 | AQ feed and badge. | LOT-133 | same | port: ezzz Swift layer | a |
| GAP-040 | Bookmarks list | Label, author, date; swipe to delete. | BookmarksPlusView.swift:175-218 | Bookmarks synced through MPStorage. | LOT-132 | same | port: ezzz Swift layer | a |

## Reader

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-050 | Page rendering | WKWebView with per-message HTML template, CSS and jQuery. | MessagesView.swift:646; HTML/templatev2.htm:1-17 | WKWebView from an app scheme, strict CSP, no page script, one `article` per message. | LOT-083 | ported with changes | port: ezzz Swift layer | a |
| GAP-051 | Message header | Grey band: 30 px avatar, 13 px bold pseudo, 9 px date, "+" actions button. | HTML/templatev2.htm:2-8; HTML/style-liste-light.css:165-168, 199-243 | Avatar, pseudo and date on one line, actions in a menu. | LOT-083, LOT-087 | UX change | new UX: spec | b |
| GAP-052 | Classic / modern message style | "Style des messages" setting switches header and padding. | AppSettingsView.swift:402-406; MessagesView.swift:1363 | Layout setting of the reader display settings. | LOT-106 | same | port: ezzz Swift layer | a |
| GAP-053 | Body text size | 15 pt injected over the 13 px stylesheet, scaled by the text-size picker only. | MessagesView.swift:1455-1460; HTML/style-liste.css:304-309 | `-apple-system-body`: Dynamic Type plus the app offset. | LOT-083, LOT-169 | UX change | new UX: operator | b·operator |
| GAP-054 | Signatures | Hidden unless `display_sig` is on. | OnlineMessagesTableViewController.m:1608-1613 | Same setting, off by default. | LOT-083, LOT-106 | same | port: legacy ObjC | a |
| GAP-055 | Quote blocks | 2 px silver left border; "me" and whitelist variants tinted. | HTML/style-liste.css:329-356 | Sanitised quote markup, 3 px border and tint; "Message cité N fois" trailer. | LOT-034, LOT-083 | ported with changes | port: ezzz Swift layer | a |
| GAP-056 | Image loading | WebKit loads every image with the default (shared) cookie store, always. | MessagesView.swift:907-908, 5547 | Policy C: cookie-less, no private hosts, Wi-Fi auto / cellular on tap, setting never / Wi-Fi / always. | LOT-083, LOT-107, FEAT-011 | UX change | new UX: operator | b·needed |
| GAP-057 | Image viewer | Full-screen zoom of one image; save, copy link. | Common.swift:2161; MessagesView.swift:1255-1275 | Viewer plus HD gallery with swipe between images. | LOT-109, FEAT-014 | UX change | new UX: Bybifok (FEAT-014) | b |
| GAP-058 | Videos | Embeds become auto-loaded iframes. | Wrapped/LinkItem.m:148-155 | Placeholder per embed, player opens on tap. | LOT-108, LOT-035 | UX change | new UX: spec | b·needed |
| GAP-059 | Polls | Toolbar button when a poll exists; sheet with results and "Voter". | MessagesView.swift:4675-4680; PollView.swift:82-106 | Poll display and vote. | LOT-136 | same | port: ezzz Swift layer | a |
| GAP-060 | Page controls | Bottom bar ‹ ›, "…" menu with page 1, last pages, "Page…". | MessagesView.swift:4184-4235, 4756-4760 | Page bar first / previous / "Page N / M" / next / last; HFR's served page is followed. | LOT-083, LOT-167 | ported with changes | port: ezzz Swift layer | b |
| GAP-061 | Page navigator | "Page…" asks for a number in a sheet. | MessagesView.swift:4143-4146 | Navigator from the page number in the title: go to, first/last, ±5, blocks of 50. | LOT-110, FEAT-002 | UX change | new UX: Bybifok (FEAT-002) | b |
| GAP-062 | Page scrubber | None. | — | Right-edge scrubber, "p. N" bubble, first-unread snap, haptics. | LOT-112, FEAT-004 | new | new UX: Bybifok (FEAT-004) | b |
| GAP-063 | First unread | Separator inserted after the flag message (dashed in the base stylesheet). | ObjCTopicMessageContentBuilder.m:25-33; HTML/style-liste.css:124-125 | "Nouveau" banner, position stable while images load. | LOT-111, FEAT-007 | UX change | new UX: Bybifok (FEAT-007) | b |
| GAP-064 | Message actions | "+" menu: Citer, multi-quote, Éditer, Profil, MP, BL/WL, Lien, Alerter, AQ, Bookmark, Supprimer. | MessagesView.swift:111-135, 196-307 | Same actions through a typed JS bridge. | LOT-087 | ported with changes | port: ezzz Swift layer | a |
| GAP-065 | Link handling | Every forum URL opened as a topic; other links in Safari view. | Common.swift:2044-2090 | Router sends each HFR URL to its screen in the app; others in Safari view. | LOT-095, LOT-137 | UX change | new UX: operator | b·operator |
| GAP-066 | Blacklist / whitelist in reader | Blacklisted collapsed or hidden, whitelisted highlighted. | MessagesView.swift:3652-3690 | Visibility policy in the reader. | LOT-117 | same | port: ezzz Swift layer | a |
| GAP-067 | Filter posts | Posts quoted N times, own or whitelisted authors; "Résultats suivants". | MessagesView.swift:3946-3990; FavoritePostFilterService.swift:10-49 | Filtered-posts flow (keeps page 1's first message) and view. | LOT-093, LOT-114 | ported with changes | port: ezzz Swift layer | a |
| GAP-068 | Bookmark from a message | Alert with a title field, duplicates refused. | MessagesView.swift:2059-2085 | Bookmark from the actions menu. | LOT-132, LOT-087 | same | port: ezzz Swift layer | a |
| GAP-069 | AQ from a message | Checks "already signaled", then creation alert. | MessagesView.swift:1993-2030 | AQ check and creation. | LOT-134 | same | port: ezzz Swift layer | a |
| GAP-070 | Moderator alert | Sheet with the prepared alert form. | MessagesView.swift:6265 | Moderator alert screen. | LOT-135, LOT-050 | same | port: ezzz Swift layer | a |
| GAP-071 | Swipe between pages | Horizontal drag ≥ 120 pt changes page, hard-coded. | MessagesView.swift:4510-4534 | "Swipe pages" reader setting. | LOT-106 | ported with changes | port: ezzz Swift layer | a |
| GAP-072 | Continuous scrolling | None. | — | Option, off by default, haptic per page. | LOT-148, FEAT-017 | new | new UX: Bybifok (FEAT-017) | b |
| GAP-073 | Quick-reply bar and quote tray | None. | — | Bottom bar with the count of checked quotes and a quick reply. | LOT-153, FEAT-006 | new | new UX: Bybifok (FEAT-006) | b |

## Composer

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-080 | Reply | "Répondre" sheet from the topic, posting the page's form. | MessagesView.swift:3840-3848; AnswerView.swift:678-705 | Sheet; form fetched at send; success only on HFR's own sentence. | LOT-084, LOT-048 | ported with changes | port: ezzz Swift layer | a |
| GAP-081 | Quote | Fetches the quote template and replaces the composer text. | MessagesView.swift:3486-3492, 3549-3560 | Quote inserted through the quote engine. | LOT-086, LOT-049 | ported with changes | port: ezzz Swift layer | a |
| GAP-082 | Quote a selection | "Citer extrait" and "Citer gras" on selected text. | MessagesView.swift:554-555, 574-575 | `[quotemsg]` selection formatter; the reader entry is not named. | LOT-049, LOT-086 | ported with changes | port: ezzz Swift layer | a |
| GAP-083 | Multi-quote | Per-message toggle (cookie), no count, no tray. | MessagesView.swift:1637-1644, 1852-1877 | Tray with a count; reply takes quotes in topic order; emptied after a confirmed send. | LOT-086, LOT-153, FEAT-006 | UX change | new UX: Bybifok (FEAT-006) | b |
| GAP-084 | Quote splitting | "Fractionner la citation" cuts at the cursor. | ReplyComposer.swift:141-175 | LOT-085: engine ported and tested, no button yet. | LOT-085 | ported with changes (engine only) | port: ezzz Swift layer | a |
| GAP-085 | Formatting | Edit-menu BBCode actions (b, i, u, s, spoiler, quote, url, img, fixed). | ReplyComposer.swift:59-70, 99-139 | Formatting toolbar and insertion engine. | LOT-085 | UX change | port: ezzz Swift layer | b |
| GAP-086 | Clear / undo / redo | Three toolbar buttons. | AnswerView.swift:500-511 | Not in any lot scope. | — | not planned | — | — |
| GAP-087 | Smileys | Panel: default, forum favourites, app favourites. | AnswerView.swift:1061-1064; ReplySmileyCatalog.swift:110-153 | Catalogue, favourites (synced) and insert. | LOT-104, LOT-064 | ported with changes | port: ezzz Swift layer | a |
| GAP-088 | Smiley search | HFR search, "all keywords" toggle, recent and top chips. | AnswerView.swift:1280-1317; SmileySearchService.swift:88-135 | Search, history and wiki keywords. | LOT-105, LOT-053 | same | port: ezzz Swift layer | a |
| GAP-089 | GIFs | Giphy panel, rating R, recents. | AnswerView.swift:2294-2340 | Giphy client (injected key) and GIF picker. | LOT-098, LOT-155 | same | port: ezzz Swift layer | a |
| GAP-090 | Image upload | Rehost with resize cap and three BBCode modes. | ReplyService.swift:1735-1810 | Rehost client with a host table, upload and insertion panel. | LOT-056, LOT-102 | ported with changes | port: ezzz Swift layer | a |
| GAP-091 | Upload history | Local history, re-insert in four sizes; "Supprimer" removes an entry silently, which suggests the image is deleted. | ReplyService.swift:1812-1918; AnswerView.swift:1909 | Local upload history; removal asks first and says the image stays online on the host. | LOT-103, FEAT-019 | UX change | new UX: Bybifok (FEAT-019) | b·operator |
| GAP-092 | Drafts | One global draft (`composerDraftText`) for replies, saved on dismiss. | MessagesView.swift:2668; AnswerView.swift:30-37 | Draft per topic and account, autosaved, 30-day expiry; swipe-down blocked with text. | LOT-084, LOT-063 | UX change | new UX: spec | b |
| GAP-093 | Archived drafts | None at `2440d79`. | — | Picker in LOT-101, but LOT-084 says not ported (conflict). | LOT-101 | new | new UX: spec | b |
| GAP-094 | Preview before send | None. | — | Exact BBCode rendering before send. | LOT-152, LOT-097, FEAT-013 | new | new UX: Bybifok (FEAT-013) | b |
| GAP-095 | Emoji | Keyboard emoji silently blocked while typing. | AnswerView.swift:2236-2240, 2277-2281 | Free typing; non-BMP refused at send with a smiley suggestion. | LOT-084, LOT-151, FEAT-012 | UX change | new UX: Bybifok (FEAT-012) | b |
| GAP-096 | Edit own message | Prefilled composer, no draft. | MessagesView.swift:3526-3532 | Edit with a draft per topic and post. | LOT-088, LOT-063 | ported with changes | port: ezzz Swift layer | a |
| GAP-097 | Delete own message | Confirmation; not offered on the first post. | MessagesView.swift:255, 3805-3819 | Allowed on the first post too (deletes the topic), always confirmed. | LOT-088, LOT-175 | UX change | new UX: spec | b |
| GAP-098 | New topic | "+" in the forum toolbar: subject (70 chars), sub-category; draft lost on relaunch. | MainWindow.swift:746-754, 818-833 | New topic composer with a persistent draft. | LOT-089, LOT-063 | ported with changes | port: ezzz Swift layer | a |
| GAP-099 | Poll creation | None in the Swift layer; only the `have_sondage` flag passes. | AddMessageViewController.m:521 | Poll creation in a new topic. | LOT-100 | new | new UX: spec | b |
| GAP-100 | Send errors | Toast with the error text ("Hooray" / "Ooops"); text kept. | AnswerView.swift:704, 719-726 | Each failure says whether something may have been posted; never auto-resent. | LOT-084, LOT-048 | UX change | new UX: spec | a |
| GAP-101 | Session expiry while composing | Toast "Session expirée"; text kept. | ReplyService.swift:12, 22 | Expiry sheet; resent after re-login only when HFR confirmed nothing was posted. | LOT-142, FEAT-009 | UX change | new UX: Bybifok (FEAT-009) | b |
| GAP-102 | "+" button modes | No modes found at `2440d79`; "+" means new topic. | MainWindow.swift:748-752 | Listed in FEATURES "Not to lose"; no lot. | — | not planned | — | — |

## Private messages

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-110 | MP list | Page 1 only, tap opens the last post, pull to refresh. | MPListView.swift:316 | Paged list in the Messages tab, opens the latest message. | LOT-126 | ported with changes | port: ezzz Swift layer | a |
| GAP-111 | Unread state | "[non lu]" prefix or not viewed; opening decrements the count. | MPListView.swift:12-37, 276-282 | Member's icon state only; read once the last page is fetched. | LOT-126, LOT-023 | ported with changes | port: ezzz Swift layer | a |
| GAP-112 | One-to-one vs group MPs | One list; group rows labelled "Interlocuteurs multiples". | MPListView.swift:171-173, 440-450 | One list by default; setting for two lists "MP / MP multiples". | LOT-171 | UX change | new UX: operator | b·operator |
| GAP-113 | Group MP reading | Opened like any MP; flag "⚑ page/max" with MPStorage. | MPListView.swift:154-165 | Read and answered like topics. | LOT-171, LOT-130 | UX change | new UX: operator | b |
| GAP-114 | New MP | From a message's menu: one read-only recipient, subject, no draft. | MessagesView.swift:3533-3547 | One or several recipients, from the list and profiles, draft per recipient. | LOT-128, LOT-063 | UX change | new UX: spec | b |
| GAP-115 | MP reply | No separate entry in the Swift layer. | — | MP reply composer through the post engine. | LOT-128 | ported with changes | port: legacy ObjC | a |
| GAP-116 | Mark unread | "Marquer comme non lu" in the thread's message menu (ObjC, shared by MP threads); not in the MP list. | OnlineMessagesTableViewController.m:807, 888 | Same entry in the reader's secondary menu, back to the list on HFR's confirmation; not in the MP list (the link is on the thread page). | LOT-058, LOT-127 | ported with changes | port: legacy ObjC | a |
| GAP-117 | Delete MP thread | None found. | — | Thread delete. | LOT-094, LOT-127 | new | new UX: spec | b |
| GAP-118 | Group members | Only the tooltip names in the HTML. | MPListView.swift:171-173 | Members action. | LOT-058, LOT-127 | new | new UX: spec | b |
| GAP-119 | MPStorage flags on MP rows | Group rows show the stored flag page. | MPListView.swift:150-165 | `mpFlags` decoration, per-account sync. | LOT-062, LOT-130 | ported with changes | port: ezzz Swift layer | a |
| GAP-120 | MP list logged out | "Connectez-vous pour accéder aux MP". | MPListView.swift:289-296 | "Connexion requise", no request sent. | LOT-126 | same | port: ezzz Swift layer | a |

## Search

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-130 | Entry points | "Rechercher sur le forum" in Plus; topic search in the reader menu. | PlusTab.swift:26-28; MessagesView.swift:4710-4716 | Same entries. | LOT-170, LOT-115, LOT-113 | same | port: ezzz Swift layer | a |
| GAP-131 | Forum search form | Keywords, category, type, scope, period. | ForumSearchView.swift:167-200 | Forum search screen. | LOT-115, LOT-046 | same | port: ezzz Swift layer | a |
| GAP-132 | Search options | All / any / advanced; title / content; since / 5 years / 1 year. | ForumSearchService.swift:11-75 | Same options, field order fixed by the protocol. | LOT-046, LOT-115 | same | port: ezzz Swift layer | a |
| GAP-133 | Banned words | "jailbreak", "cydia"… silently replace the query. | ObjCForumSearchWorker.m:150-156 | Search refused with a warning. | LOT-046 | UX change | new UX: operator | b·needed |
| GAP-134 | Results paging | Meta-refresh then first / previous / next / last URLs. | ForumSearchService.swift:129-135 | Cookie-less result GETs, paging per LOT-046. | LOT-046, LOT-115 | ported with changes | port: ezzz Swift layer | a |
| GAP-135 | Search in a topic | Sheet: words, pseudo, filter, from the start. | TopicSearchSheetView.swift:96-141; TopicSearchService.swift:1-45 | No-redirect flow; only HFR's "no answer" is "no result". | LOT-113, LOT-046 | ported with changes | port: ezzz Swift layer | a |
| GAP-136 | Next results in a topic | "Résultats suivants" at the end of the page. | ObjCTopicToolbarHTMLBuilder.m:12 | Not detailed in LOT-113's scope. | LOT-113 | ported with changes | port: legacy ObjC | a |

## Settings and appearance

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-140 | Settings screen | One form: Général, Thème, Sujets, Filtrer, Notifications MP, Stockage MP, Maintenance, À propos. | AppSettingsView.swift:494-503 | Same Réglages shell, sections owned by their lots. | LOT-119, LOT-170 | same | port: ezzz Swift layer | a |
| GAP-141 | Where settings live | `@AppStorage` keys, device only. | AppSettingsView.swift:86-109 | Same keys; synced ones mirrored to iCloud KVS. | LOT-060, LOT-172 | ported with changes | new UX: spec | b·operator |
| GAP-142 | Light / dark / auto | "Automatique (iOS)" or manual Clair / Sombre. | AppSettingsView.swift:127-134 | Same options for native UI and reader. **Kept despite the HIG** (Dark Mode: "Avoid offering an app-specific appearance setting"), by the operator's decision of 2026-11-07. | LOT-121 | same | port: ezzz Swift layer | a |
| GAP-143 | Time-based auto theme | Day / night time cells, hidden. | PlusSettingsViewController.m:84-85 | Not in any spec. | — | not planned | — | — |
| GAP-144 | Dark brightness | `theme_night_brightness` scales dark colours. | ThemeColors.m:116-118 | Kept. | LOT-121 | same | port: legacy ObjC | a |
| GAP-145 | Darker dark and OLED | No OLED theme (Light and Dark only); dark is #17181A. | Constants.h:52-55; ThemeColors.m:164 | Darker dark #0B0B0C, OLED black, 1 pt separators. | LOT-122, FEAT-010 | new | new UX: Bybifok (FEAT-010) | a |
| GAP-146 | Accent colour | Hue slider (default 190°), day and night tints derived from one hue. | AppSettingsView.swift:307-312, 391-398; Common.swift:461-466 | Legacy accent kept; FEAT-010 asks a single accent with live preview. | LOT-121, LOT-122 | UX change | new UX: Bybifok (FEAT-010) | b |
| GAP-147 | Seasonal theme | Christmas red accent and images unless disabled. | ThemeManager.m:213-244; Common.swift:469-473 | Seasonal themes and assets. | LOT-166, FEAT-010 | ported with changes | new UX: Bybifok (FEAT-010) | a |
| GAP-148 | Alternate icons | Picker of 8 icons. | AppSettingsView.swift:31-82, 360-367 | Same picker. | LOT-123 | same | port: ezzz Swift layer | a |
| GAP-149 | Haptics | "Retours haptiques" toggle, on. | AppSettingsView.swift:357 | Same toggle. | LOT-123 | same | port: ezzz Swift layer | a |
| GAP-150 | Open links in default browser | Absent at `2440d79` (exists on `master`). | — | "Navigateur par défaut" toggle; HFR links stay in the app. | LOT-119, LOT-137 | new | port: ezzz Swift layer | a·master |
| GAP-151 | Crédits, Charte | Bundled HTML pages from Plus. | StaticInfoPageView.swift:10-47 | Static pages; About links to the app's topics, opened in the app. | LOT-120 | ported with changes | port: ezzz Swift layer | a |
| GAP-152 | Maintenance | System-settings shortcut; "Vider le cache" commented out. | AppSettingsView.swift:264-280, 476-486 | Cache sizes and the system-settings shortcut. | LOT-120, LOT-066 | UX change | new UX: spec | b |
| GAP-153 | Smiley size, video rows | Rows commented out, no effect. | AppSettingsView.swift:422-432 | Not ported. | LOT-119 | dropped | new UX: spec | — |

## Accounts

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-160 | Multi-account store | `AccountsStore` over ObjC `MultisManager`. | AccountsStore.swift:28-87 | `AccountsModel` over a versioned credential store. | LOT-081, LOT-065 | ported with changes | port: ezzz Swift layer | a |
| GAP-161 | Add account | Sheet "Ajouter un pseudo", new account becomes main. | AddAccountView.swift:10-97 | Same sheet, login validated in a fresh session, AutoFill. | LOT-081, LOT-043 | same | port: ezzz Swift layer | a |
| GAP-162 | Switch account | Toolbar menu with avatars. | AccountMenuViews.swift:11-48 | Same menu plus a manage screen. | LOT-081 | same | port: ezzz Swift layer | a |
| GAP-163 | Remove / log out | "Déconnexion" removes the current account; no server logout. | Favorites.swift:781-786, 815-822 | Remove from the manage list after confirmation. | LOT-081 | UX change | new UX: spec | b |
| GAP-164 | Credentials storage | Keychain archive holding cookies. | MultisManager.m:44-46, 70-82 | Keychain `ThisDeviceOnly` versioned envelope. | LOT-065 | ported with changes | port: legacy ObjC | a |
| GAP-165 | Session at launch | One profile GET per account, no failure feedback. | HFRplusAppDelegate.m:147 | Session checked at launch and on foreground, typed errors. | LOT-081, LOT-044 | ported with changes | port: legacy ObjC | a |
| GAP-166 | Account deletion | "Supprimer mon compte" opens a mail composer. | PlusTab.swift:55-74 | HFR procedure screen and local data wipe. | LOT-157 | UX change | new UX: spec | b |
| GAP-167 | Profile screen | Member profile view. | UserProfileView.swift:492 | Profile screen. | LOT-116 | same | port: ezzz Swift layer | a |
| GAP-168 | iCloud keychain sync | None. | — | Opt-in account sync through the iCloud keychain. | LOT-173 | new | new UX: operator | b·operator |
| GAP-169 | App lock | None. | — | Optional Face ID / code lock with grace delay. | LOT-173 | new | new UX: operator | b·operator |
| GAP-170 | Legacy data import | Not applicable (in-place update). | — | Idempotent import of accounts, lists, settings and drafts. | LOT-067, LOT-158 | new | new UX: spec | a |

## Offline and sync

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-180 | Offline topics | Topic pages and images saved for offline reading. | OfflineStorage.m:41-60, 88-103 | Save, list and evict offline pages. | LOT-068, LOT-139 | ported with changes | port: legacy ObjC | a |
| GAP-181 | MPStorage switch | App-wide `mpstorage_active`, "Resynchroniser". | AppSettingsView.swift:225-262 | Per-account state unasked / on / declined / off; merge, never replace. | LOT-130 | UX change | new UX: operator | b·needed |
| GAP-182 | Blacklist sync | Through the MPStorage thread. | MPStorage.m:202, 230, 271 | Three-way merge, never overwritten by an empty list. | LOT-131, LOT-062 | ported with changes | port: legacy ObjC | a |
| GAP-183 | Bookmarks sync | Written synchronously to MPStorage. | MPStorage.m:313, 359 | Local first, merged on next sync. | LOT-132, LOT-062 | ported with changes | port: legacy ObjC | a |
| GAP-184 | iCloud KVS | None. | — | Super favourites, smiley favourites and synced settings follow the Apple ID. | LOT-172 | new | new UX: operator | b·operator |
| GAP-185 | Reading position | Scroll position in memory only. | MessagesView.swift:796-801 | Per-topic store, mirrored to iCloud KVS. | LOT-090, LOT-145 | new | new UX: Bybifok (FEAT-015) | b·operator |
| GAP-186 | Caches | Image and smiley caches; clear action commented out. | AppSettingsView.swift:264-280 | Caches with eviction; legacy caches removed at first launch. | LOT-066, LOT-067 | ported with changes | port: ezzz Swift layer | a |

## Notifications

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-190 | Background MP check | BGAppRefresh `com.hfrplus.refresh_mp` polls the home page. | MPBackgroundService.swift:21-46, 70-110 | Same task id; no notification on an unknown or expired answer. | LOT-140, LOT-047 | ported with changes | port: ezzz Swift layer | a |
| GAP-191 | Local notification | "Vous avez un nouveau message privé" when the count rises. | MPBackgroundService.swift:98-101, 140-157 | Same, driven by a per-account ledger. | LOT-140, LOT-091 | ported with changes | port: ezzz Swift layer | a |
| GAP-192 | App icon badge | Synced with the MP count when `mp_badge_enabled`. | MPBackgroundService.swift:60-66 | Badge per setting. | LOT-140 | same | port: ezzz Swift layer | a |
| GAP-193 | "Vérifier HFR" App Intent | None. | — | Shortcuts check of MPs and flags, minimum interval. | LOT-141, LOT-092, FEAT-005 | new | new UX: Bybifok (FEAT-005) | b |
| GAP-194 | Flag news notification | Flags never notified. | — | Ledger notifies flagged topics with a newer post. | LOT-091, LOT-092 | new | new UX: Bybifok (FEAT-005) | b |
| GAP-195 | "On t'a cité" | None. | — | Quote notice in Home and notifications, if the capture proves it feasible. | LOT-154, FEAT-018 | new | new UX: Bybifok (FEAT-018) | b |

## Accessibility

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-200 | Text size | Picker 100 / 110 / 120 / 130 %. | Common.swift:212-243; AppSettingsView.swift:351-355 | Slider below and above the default, offset on Dynamic Type, every screen. | LOT-169 | UX change | new UX: operator | b·operator |
| GAP-201 | Compact density | "Mode compact" on lists and settings. | AppSettingsView.swift:348; Common.swift:204-206 | Compact density everywhere, legacy Favoris as reference. | LOT-169 | ported with changes | new UX: operator | a |
| GAP-202 | VoiceOver | A few toolbar labels; message markup unlabelled. | MessagesView.swift:4689, 4770, 4787 | Each message labelled "Message de <pseudo>, <date>"; controls labelled. | LOT-083, LOT-163 | UX change | new UX: spec | b |
| GAP-203 | Accessibility pass | No audit. | AnswerView.swift:2181 | Passes on lists, navigation, accounts, settings, reader and composer. | LOT-162, LOT-163 | new | new UX: spec | b |
| GAP-204 | Scrubber adjustable action | None. | — | VoiceOver adjustable action. | LOT-112, FEAT-004 | new | new UX: Bybifok (FEAT-004) | b |

## Large and foldable screens

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-210 | Sidebar condition | Sidebar root only for an iPad in regular width. | MainWindow.swift:1132-1134, 1255-1260 | Same condition, one selection shared by both layouts. | LOT-170 | same | port: ezzz Swift layer | a |
| GAP-211 | iPad sidebar content | Four plain tabs, title "HFRnow", balanced split. | MainWindow.swift:1301-1314 | Sections [Catégories, Favoris, Messages] / [Bookmarks, AQ] / [Réglages…]. | LOT-170 | UX change | port: ezzz Swift layer | a·master |
| GAP-212 | Reader on wide screens | Pushed full width in the tab's stack. | Common.swift:3183-3197 | Detail column next to the list (`NavigationSplitView` per tab). | LOT-082, LOT-170 | UX change | new UX: spec | b |
| GAP-213 | iPhone orientation | Portrait unless `landscape_mode`; portrait forced while composing. | Common.swift:144-172 | Same policy, applied live. | LOT-119 | same | port: ezzz Swift layer | a |
| GAP-214 | Large iPhone landscape | Same single column, stretched. | Common.swift:164-172 | Regular width shows list and reader side by side. | LOT-082, LOT-170 | UX change | new UX: spec | b |
| GAP-215 | iPhone Duo inner screen | `.phone` idiom: tab bar and stretched iPhone stack, rotation not locked. | MainWindow.swift:1132-1134 | Two columns unfolded, tabs in a rail, sidebar pinned or on demand. | LOT-147, FEAT-016 | new | new UX: Bybifok (FEAT-016) | b |
| GAP-216 | iPhone Duo cover screen | iPhone layout with a black band (reported in #368 G.1). | — | Compact layout filling the screen. | LOT-147 | UX change | new UX: Bybifok (FEAT-016) | a |
| GAP-217 | Fold / unfold continuity | No handling; PR #4 (not merged) proposes one hierarchy. | — | Topic and position kept across fold and unfold. | LOT-145, LOT-147 | new | new UX: Bybifok (FEAT-015) | b |
| GAP-218 | iPad Plus entries | Plus is a sidebar entry showing its list. | MainWindow.swift:1337-1345 | Entries in a two-column split; Plus opens Réglages. | LOT-170 | UX change | new UX: spec | b |
| GAP-219 | Multi-window | `UIApplicationSupportsMultipleScenes` false. | HFRswift/Info.plist:206-208 | iPad multi-window. | LOT-146 | new | new UX: spec | b |

## Liquid Glass and the iOS 27 HIG (decided 2026-11-07, #545)

Operator decision of 2026-11-07 on [#545](https://github.com/ezzz/HFRnow/issues/545): Liquid Glass is part of M4 parity, and **where the HIG and legacy differ, the HIG wins**. Each divergence is a row here, never a silent change. Two existing rows keep a decision that conflicts with the HIG: GAP-008 (reader tab bar) and GAP-142 (appearance setting).

- **Legacy reference**: `HFRswift/Swift/LiquidGlass.swift` at `2440d79` (`git show 2440d79:HFRswift/Swift/LiquidGlass.swift`). Used by 8 files, 27 lines besides the helper file. Quoted from `git grep -c 'glassEffect\|hfrGlass' 2440d79 -- HFRswift` (one line per file): 9 files and 33 lines in total, `LiquidGlass.swift:6` included; without it, 8 files and 27 lines.
- **HIG pages read on 2026-11-07**: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), [Tab bars](https://developer.apple.com/design/human-interface-guidelines/tab-bars), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode), [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo).
- **Ported by**: LOT-185 (#548) outside the reader, LOT-186 (#549) for the reader chrome, which absorbs #428.
- **Not in these rows**: the M5 items (the composer bar, LOT-174; the Duo and iPad layouts with the iOS 27.1 APIs, LOT-147; `Tab(role: .search)`; `tabViewBottomAccessory`) and the layered app icon (LOT-123).

| Id | Feature | Legacy behaviour | Legacy ref | SwiftHFR final | Lot/Feat | Gap | Source | H.1 |
|---|---|---|---|---|---|---|---|---|
| GAP-220 | Liquid Glass helpers | `liquidGlassIfAvailable`, `hfrGlassSurface`, `hfrGlassButton`, `hfrToastSurface`, `hfrLoadingPanel` and `presentationGlassBackground`, each with a fallback below iOS 26 (materials, strokes). | LiquidGlass.swift:12-77 | Native `glassEffect` and `.buttonStyle(.glass)` in iOS 27 code. The minimum target is iOS 27, so the fallbacks go. | LOT-185, LOT-186 | ported with changes | port: ezzz Swift layer | a |
| GAP-221 | Glass on floating elements | Glass on the toasts, the list pager, the reader page bar, the favourites filter banner and the reader loading overlay. | AnswerView.swift:2360; MessagesView.swift:6393, 4476; MainWindow.swift:981; MessagesView.swift:4728-4800, 6222-6236; Favorites.swift:1137 | Glass on the floating toasts, the list pagers, the reader page bar, the favourites filter banner (LOT-185 `FilteredPostsBanner`) and the reader loading overlay (HIG Materials: glass for floating elements). | LOT-185, LOT-186 | ported with changes | port: ezzz Swift layer | a |
| GAP-222 | Glass on content cards | Glass panels (`hfrGlassSurface`, `hfrLoadingPanel`) on cards in the content layer: the add-account card, a search card and the poll loading panel. | AddAccountView.swift:70; ForumSearchView.swift:379; PollView.swift:162 | Materials stay on cards in the content layer. HIG Materials: "Don't use Liquid Glass in the content layer". Glass only where a card floats over scrolling content, justified in the lot spec. | LOT-185 | UX change | new UX: operator | b·operator |
| GAP-223 | Sheet backgrounds | `presentationGlassBackground()` forces `.thinMaterial` on five sheets. | AnswerView.swift:1162, 1951; MessagesView.swift:4356, 4849, 5061 | System sheet background, no forced material. Attributed to the operator decision of 2026-11-07 (#545), not to a HIG rule. SwiftHFR never ported the forced background, so no code changes. | — | dropped | new UX: operator | — |
| GAP-224 | Circled ellipsis symbols | Plain `ellipsis` on the Plus tab. | MainWindow.swift:1295 | Plain symbols. The circled ones of SwiftHFR (image viewer, root tabs, reader) become plain: HIG Toolbars says borders such as outlined circles are not necessary. | LOT-185, LOT-186 | same | port: ezzz Swift layer | a |
| GAP-225 | Reader "…" page menu | A page menu behind a plain `ellipsis` in the reader. | MessagesView.swift:4722, 4970 | The "…" becomes the system overflow menu or another symbol, because the Duo HIG reserves the ellipsis for overflow (Designing for iPhone Duo). The page controls follow the legacy layout (#428). | LOT-186 (absorbs #428) | UX change | new UX: operator | b·operator |
| GAP-226 | Glass buttons on floating controls | Glass buttons (`.buttonStyle(.glass)`, `.glassProminent`) through `hfrGlassButton`, 17 call sites; the submit button inside the add-account card (AddAccountView.swift:67). | LiquidGlass.swift:54-68; AddAccountView.swift:67 | Glass buttons on floating controls only (HIG Buttons: one or two prominent buttons per view). The card button loses its glass: a UX change, kept because the HIG wins. This reverses LOT-115:49, which dropped the glass buttons. | LOT-185, LOT-186 (reverses LOT-115) | UX change | port: ezzz Swift layer | b·operator |

## Counts

| Gap | Rows |
|---|---|
| same | 36 |
| ported with changes | 44 |
| ported with changes (engine only) | 1 |
| UX change | 43 |
| new | 28 |
| dropped | 2 |
| not planned | 8 |
| **Total** | **162** |

## Convergence notes

Decisions the UX review (H.1) has to make; each names its rows.

1. **Oracle revision.** Specs LOT-119 and LOT-170 cite `origin/master`, which has features `2440d79` lacks (start screen, default browser, sectioned iPad sidebar). Pick one revision as the legacy oracle (GAP-002, 150, 211).
2. **Topic row.** LOT-169 makes the legacy Favoris row the density reference, but LOT-082's row drops the "⚑ cur / max" footer, the unread-pages capsule and the flag tints (GAP-026, 027).
3. **Catégories.** A flat list with a sub-forum picker becomes collapsible sections; check it against the "preserve what works" principle (GAP-020, 022, 023).
4. **Reader message header.** The grey band with a "+" button becomes a one-line header with a menu; decide whether the legacy band stays the default and the new one an option (GAP-051, 064).
5. **Reader chrome.** Legacy hides the tab bar in three paths (GAP-008) and has ‹ › Actualiser New; the final reader hides the tab bar while a topic is open (UXD-02), adds a page bar, a scrubber and a quick-reply bar. Decide what is default and what is opt-in (GAP-008, 060, 062, 073).
6. **Swipes and "Lu".** One uniform swipe set, a local "Lu" turned into one with "Annuler"; the legacy context-menu page jumps are not named (GAP-028, 029, 034).
7. **Images and videos.** Image policy C (Wi-Fi auto, cellular on tap) and tap-to-play videos replace "always load" (GAP-056, 058).
8. **Text size and Dynamic Type.** A 4-step picker becomes a slider on Dynamic Type; map the legacy values (GAP-053, 200).
9. **Composer behaviour.** Per-topic drafts that block swipe-down, emoji refused at send rather than at typing, first-post delete, a quote tray (GAP-083, 092, 095, 097).
10. **Duo and wide layouts.** The rail, the column widths and the portrait behaviour on the Duo inner screen wait for the Phase 5 design document; LOT-147 cannot start before it (GAP-212, 214, 215, 216).
11. **Uncovered legacy features.** Tab reselect to refresh, quick actions, clear / undo / redo, "+" modes, time-based theme: keep (new lot) or drop on record (GAP-007, 010, 084, 086, 102, 143).
12. **"Legacy parity" labels that are new.** MP mark unread, delete, members, poll creation, multi-window and archived drafts are not in `2440d79`; relabel or find their legacy source (GAP-093, 099, 116-118, 219).

### Open questions

- LOT-084 says archived drafts are not ported; LOT-101 plans the picker. Which holds (GAP-093)?
- Background MP check: every account or only the selected one (GAP-190)?
- LOT-083 says legacy prefetched neighbouring pages with the shared jar; no prefetch was found in the Swift layer. Check before relying on it.
- Does LOT-171 ("group MPs like topics") include the quote tray and quick reply (GAP-113)?
- Is the HD gallery per message or per page (GAP-057)?

## Convergence classification (H.1)

Directive H.1 of [#368](https://github.com/ezzz/HFRnow/issues/368), `cloud/ui-convergence`, 2026-11-01. Four Sonnet agents classified the rows, one per group of screens, with legacy symbols checked at `2440d79`; Opus consolidated them. The per-row class is the `H.1` column above.

### GAP rows of type `ported with changes`, `UX change` or `new` (115)

| H.1 | Rows | Count |
|---|---|---|
| a | 004, 011, 025, 032, 033, 038, 050, 055, 064, 067, 071, 080, 081, 082, 087, 090, 096, 098, 100, 110, 111, 115, 116, 119, 134, 135, 136, 145, 147, 151, 160, 164, 165, 170, 180, 182, 183, 186, 190, 191, 201, 216, 220, 221 | 44 |
| a·master | 002, 150, 211 | 3 |
| b·needed | 024, 056, 058, 133, 181 | 5 |
| b·operator | 013, 016, 053, 065, 091, 112, 141, 168, 169, 184, 185, 200, 222, 225, 226 | 15 |
| b | 008, 009, 012, 014, 015, 020, 022, 026, 028, 029, 034, 051, 057, 060, 061, 062, 063, 072, 073, 083, 085, 092, 093, 094, 095, 097, 099, 101, 113, 114, 117, 118, 146, 152, 163, 166, 193, 194, 195, 202, 203, 204, 212, 214, 215, 217, 218, 219 | 48 |

The (b) rows include the ones the merged code already ships: 009, 020, 022, 026, 051, 060, 092, 163, 212, 214 (008 joins once #540 merges). The `same` rows are (a).

- The Source column says where a behaviour comes from; H.1 says whether the user sees a difference. So a row can be `b` with source `port: ezzz Swift layer`: GAP-060 and GAP-085 port the feature but change its controls.
- Rows that are `a` although their source says "new UX" are invisible or robustness changes:
  - refresh keeps the page on screen (025);
  - App Review rule (038);
  - errors that say whether anything was posted (100);
  - extra themes with defaults unchanged (145, 147);
  - legacy data import (170);
  - compact density on more screens (201);
  - the cover-screen fix (216). Its lot, LOT-147, is in M5, so the fix is a small M4 item ([#432](https://github.com/ezzz/HFRnow/issues/432), UXD-25).

### App lots (80) and features

| Class | Lots | Count |
|---|---|---|
| (a) port | 080, 086, 089, 102, 104, 105, 113, 114, 116, 117, 118, 121, 123, 124, 126, 131, 132, 133, 135, 136, 139, 140, 155, 156, 158, 160, 161, 162, 163, 164, 165, 166 | 32 |
| mixed | 081, 082, 083, 084, 085, 087, 088, 103, 106, 109, 111, 115, 119, 120, 122, 125, 127, 128, 130, 134, 137, 157, 159, 169, 170, 171 | 26 |
| (b) evolution | 100, 101, 107, 108, 110, 112, 138, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151, 152, 153, 154, 173 | 22 |

- **Mixed lots whose (b) part stays in M1–M4.**
  - Needed: LOT-083 (policy C), LOT-115 (banned words refused), LOT-130 (per-account MPStorage, merge), LOT-159 (App Review).
  - Decided by the operator: LOT-103 (removal says the image stays online), LOT-137 (HFR links routed in the app), LOT-169 (slider), LOT-171 (two MP lists as an option).
  - Decided 2026-11-02 (recommendation of each UXD row, table below): LOT-081, 082, 083, 084, 087, 106, 119, 170 (UXD-01 to 10, 15, 21, 24), and LOT-157 (UXD-21: the legacy mail composer stays unless App Review asks).
- **Mixed lots with a (b) part in M5:** LOT-085, 088, 109, 111, 120, 122, 125, 127, 128, 134 (splits in [LOTS.md](../LOTS.md#m5--ux-evolutions), new lots 174 to 183).
- **(b) lots that stay:**
  - needed: LOT-107 (the setting that gates policy C), LOT-108 (players on tap, LOT-071 D-071-2);
  - decided by the operator: LOT-173.
- **(b) lots in M5:** LOT-100, 101, 110, 112, 138, 141, 142, 143, 144, 145, 146, 147, 148, 149, 150, 151 (UXD-16 picked A), 152, 153, 154 ([#379](https://github.com/ezzz/HFRnow/issues/379)).
- **Features:**
  - All FEAT items are (b) by origin.
  - FEAT-003 (honest paging) is (b) needed.
  - FEAT-011 is the policy C setting.
  - FEAT-010 is themes (a-compatible) plus a single accent, live preview and a one-line header (b).
  - FEAT-019 is a local history (a) plus a confirmed removal that says the image stays online (b, LOT-103); no app-side delete is evidenced for a guest upload (`HFR-PROTOCOL` §7b B12).
- **"legacy parity" labels with no source at `2440d79`:**
  - LOT-100 (poll creation; legacy only reads `have_sondage`);
  - LOT-101 (archived drafts: `master` only);
  - LOT-146 (multi-window: `UIApplicationSupportsMultipleScenes` false);
  - LOT-108 (legacy loads iframes at once; the placeholder is new);
  - the delete and members parts of LOT-127 (mark unread has an ObjC source: `OnlineMessagesTableViewController.m` `markUnread`).
  - `LOTS.md` now says so in their Audit cell.
- **Legacy features in no lot**, a parity loss unless decided: tab reselect (GAP-007, UXD-04), quote splitting and clear / undo / redo (GAP-084, 086, UXD-18), category icons, filter and flag tints (GAP-021, 023, 027, UXD-05 to 07), quick actions and time-based theme (GAP-010, 143, UXD-23).

## Assumptions of the image

- Device sizes in points, scale @3x: iPhone 16 393 × 852 pt; iPhone 18 Pro Max 440 × 956 pt (Apple: 6.9 in, 2868 × 1320 px, 460 ppi).
- **iPhone Duo** (neither LOT-147 / #237 nor PR #4 gives a size; PR #4 only says the inner screen is regular / regular with a `.phone` idiom): inner screen 7.6 in, 2670 × 1878 px at 430 ppi; cover screen 5.4 in, 1398 × 2034 px (published specs as reported by the press, September 2026). Assumed scale @3x, so inner **890 × 626 pt** (unfolded, hinge vertical) or 626 × 890 pt rotated, cover **466 × 678 pt**. Camera as a punch hole; hinge crease drawn faintly. To check against Apple's developer device sizes.
- Legacy cover screen: the black band of #368 G.1 is drawn at the bottom; its real position is not captured.
- Legacy iPhone landscape is shown with "Rotation d'écran" on (off by default: portrait lock).
- SwiftHFR Duo layouts follow FEAT-016's one-line summary (two columns, tab rail); the Phase 5 design document does not exist yet.
- Fonts: Inter stands in for SF Pro, drawn icons for SF Symbols. Light theme on both sides; pseudos `user1`…`user6`; topic titles are illustrative.

## UX decisions of 2026-11-02

Operator decisions on [#379](https://github.com/ezzz/HFRnow/issues/379): **every UXD row takes its recommendation**; M4 is the validated legacy parity and M5 gathers the evolutions ([LOTS.md](../LOTS.md#m5--ux-evolutions)). The file that listed the open choices is deleted. A decision is recorded where it acts: the lot spec when the lot has one, else the lot issue, plus the follow-up issue of an (a) item. Tracked on [#413](https://github.com/ezzz/HFRnow/issues/413). The recommendations gave no milestone for the small (a) follow-ups of UXD-10, 15, 21 and 24: they are set to M2 by `cloud/docs-steward` (not by the operator), and the orchestrator can move them to M1.

| UXD | Decision | Recorded in |
|---|---|---|
| 01 | B for start screen, browser and sidebar (`master` counts as ezzz's Swift layer, defaults unchanged); archived drafts go to M5 | LOT-119 and LOT-170 specs; LOT-101 (#192) in M5 |
| 02 | A: tab bar hidden while a topic is open (M1) | [#424](https://github.com/ezzz/HFRnow/issues/424); LOT-083 and LOT-170 specs |
| 03 | A: avatar menu in every list toolbar (M2) | [#425](https://github.com/ezzz/HFRnow/issues/425); LOT-170 spec |
| 04 | A: reselecting a tab refreshes it, with a haptic (M2) | [#426](https://github.com/ezzz/HFRnow/issues/426); LOT-170 spec |
| 05, 06 | A: legacy Catégories list and Tous / Favoris / Suivis / Lus filter (restore lot, M2; M1 if TestFlight testers must find their list there, the orchestrator decides) | [#427](https://github.com/ezzz/HFRnow/issues/427); LOT-082 spec |
| 07 | A: legacy topic row | LOT-169 (#295) and LOT-169 spec |
| 08 | A in M2; the uniform swipe set (FEAT-008) goes to M5 | LOT-177 ([#417](https://github.com/ezzz/HFRnow/issues/417)); LOT-125 (#216) |
| 09 | A by default; B as a value of "Style des messages" | LOT-106 (#197), LOT-087 (#179); LOT-083 spec |
| 10 | A layout keeping "follow HFR's served page" (M4, absorbed by LOT-186: operator decision of 2026-11-07 on #545); the navigator goes to M5 | [#428](https://github.com/ezzz/HFRnow/issues/428); LOT-186 (#549); LOT-110 (#201) in M5 |
| 11 | A in M2; the "Nouveau" banner goes to M5 | LOT-178 ([#418](https://github.com/ezzz/HFRnow/issues/418)); LOT-111 (#202) |
| 12 | B: policy C, decided 2026-10-27 (default Wi-Fi) | LOT-083 spec "Decisions taken here" |
| 13 | B: slider; 100 / 110 / 120 / 130 % map to the same percentages | LOT-169 spec |
| 14 | A; deleting the first post goes to M5 | LOT-175 ([#415](https://github.com/ezzz/HFRnow/issues/415)); LOT-088 (#180) |
| 15 | Per-topic drafts kept (exception); A for swipe-down: dismiss saves the draft (M2) | [#429](https://github.com/ezzz/HFRnow/issues/429); LOT-084 spec |
| 16 | A (silently blocked while typing) in M2 ([#437](https://github.com/ezzz/HFRnow/issues/437)); the refusal at send with a suggestion goes to M5 | LOT-151 (#241) moved to M5; LOT-084 spec |
| 17 | A (per-message toggle) in M2; the tray goes to M5 | LOT-153 (#243) moved to M5; LOT-086 (#178) keeps the toggle |
| 18 | A: clear / undo / redo and "Fractionner la citation" join LOT-085; the toolbar goes to M5 | LOT-174 ([#414](https://github.com/ezzz/HFRnow/issues/414)); LOT-085 (#177) |
| 19 | A in M2 (toast, text kept, never auto-resent); the sheet goes to M5 | LOT-142 (#232) moved to M5; LOT-084 spec |
| 20 | Mark unread and one recipient kept; the "Nouveau message" list button kept (legacy, #398); the rest to M5 | LOT-181 ([#421](https://github.com/ezzz/HFRnow/issues/421)), LOT-182 ([#422](https://github.com/ezzz/HFRnow/issues/422)); LOT-128 spec |
| 21 | A: restore "Déconnexion"; deletion by mail composer unless App Review asks (M2) | [#430](https://github.com/ezzz/HFRnow/issues/430); LOT-157 (#247) shrinks; LOT-081 spec |
| 22 | A (LOT-121); the single accent goes to M5 | LOT-180 ([#420](https://github.com/ezzz/HFRnow/issues/420)); LOT-122 (#213) |
| 23 | Dropped on record: neither works in legacy | GAP-010 and GAP-143 stay `—` |
| 24 | B on iPad, A on a large iPhone in landscape (M2) | [#431](https://github.com/ezzz/HFRnow/issues/431); LOT-082 spec |
| 25 | Layouts and continuity go to M5; filling the cover screen is an (a) fix in M4 | LOT-147 (#237) and LOT-145 (#235) in M5; [#432](https://github.com/ezzz/HFRnow/issues/432); legacy #372, #373 |
