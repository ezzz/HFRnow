# Review of the LOT-000 synthesis (lot split, protocol, ADR 0006/0007)

Reviewer: Fable 5.1 — 2026-10-24. Scope: `docs/LOTS.md`, `docs/HFR-PROTOCOL.md`, `docs/audit/README.md`, ADR 0006/0007, against the five audit reports and the legacy code at `2440d79`.

## Summary verdict: **rework** (one blocker, then approve with changes)

The split is complete (every proposal of the five reports maps to exactly one lot or to the Phase 4 backlog; 51 lots and 14 ✱ lots recount correctly; the dependency graph is acyclic) and the protocol facts I spot-checked are accurate. The plan fails on one structural point: **ten `HFRNetwork` lots depend on `HFRParsing` lots**, which ADR 0001 and `Package.swift` forbid. As written, the post engine, login, search, MPStorage transport and poll vote cannot be built in the module the plan assigns them to. Fixing this needs an ADR (a fifth, orchestration target) and a relabel of those lots — not a redo of the audit.

## Findings

| Id | Sev | Where | Finding | Evidence | Proposed fix |
|---|---|---|---|---|---|
| F1 | **blocker** | LOTS.md 043, 046, 047, 048, 049, 050, 051, 052, 054 (module `HFRNetwork`) | These lots depend on parsing lots (025, 023, 036, 037, 031, 038, 026) and their scope is "GET → parse → POST → classify". `HFRNetwork` may not import `HFRParsing` (ARCHITECTURE rule 2, `Package.swift` target deps), so none of them can be implemented where the table says. Pushing the flows into the App makes the riskiest logic (post engine) untestable on Linux CI (AGENTS §10). Audit D itself placed `ForumWriter` in HFRNetwork with D1/D2 (parsing) as inputs — the synthesis copied the contradiction. | `docs/LOTS.md:66-77`; `Packages/HFRKit/Package.swift` (`HFRNetwork` depends on `HFRModels` only); ADR 0001 "The app orchestrates" | ADR 0008: add a Foundation-only `HFRClient` (or `HFRFlows`) target depending on Models+Parsing+Network (not Storage), Linux-testable with mock transport, owning multi-step flows. Keep in `HFRNetwork` only transport, endpoints, session/cookies, raw page fetchers (040–042, 045, 053 search/wiki GETs). Relabel 043/046/047/048/049/050/051/052/054 to `HFRClient`, update ARCHITECTURE and the README graph. |
| F2 | major | LOTS.md 044 "depends on 042, **065**"; README graph `S065 --> N044` | A network lot depending on a storage lot encodes the forbidden Network→Storage direction. Session refresh needs only `Account`/`StoredCookie` value types (LOT-013). | `docs/LOTS.md:67`; `docs/audit/README.md:68` | Depend on 042 and 013; the app (or HFRClient) passes stored cookies in and persists the merged result. Same for 065 "depends on 042": a value-type cookie model in 013 removes it. |
| F3 | major | LOTS.md 065 (HFRStorage, Keychain); AGENTS §10 | `Security`/Keychain does not exist on Linux, yet `swift test` on HFRKit must pass there; nothing in the lot, ARCHITECTURE or E-6 says how. Also `HTTPCookie`/`URLSession` live in `FoundationNetworking` on Linux (needs `#if canImport(FoundationNetworking)`), relevant to 040/042 and to any cookie type crossing into Storage. | E §8 E-6 "verified on Mac/device" only; `docs/ARCHITECTURE.md:22` | In 065: `CredentialStore` protocol + in-memory + file-backed (Linux) + `KeychainCredentialStore` under `#if canImport(Security)`; cookies stored as a Codable `StoredCookie` (013), never `HTTPCookie`. Add a "Linux rules" paragraph to ARCHITECTURE. |
| F4 | major | LOTS.md (coverage) | **User profile page** (`/hfr/profil-NNN.htm`: `table.main` rows `profilCase2/3`, avatar, "smilies persos", quick actions) is a live feature with its own regex parser and no lot. LOT-025 covers only `editprofil.php` (hash/avatar). | `HFRnow/HFRswift/Swift/UserProfileView.swift:113-430` (`UserProfileHTMLParser`), `:961` | New lot `LOT-027 Profile page parser` (HFRParsing, medium, Sonnet→Opus, needs fixture) + client fetch; add to HFR-PROTOCOL §1. |
| F5 | major | LOTS.md 055; HFR-PROTOCOL §7 | **AQ RSS feed** (`https://aq.super-h.fr/rss.php`, `XMLParser`, `nb_aq` badge, `last_check_aq`, filter of category 25 unless pseudo == `applereview`) is a live "Plus" tab feature; LOT-055 lists only `getAlertesByTopic`/`addAlerte`. The `applereview` hack is a third App-Review workaround not listed in the decisions. | `HFRnow/HFRswift/Swift/AQPlusView.swift:38-57, 60-87, 248-300`; `PlusTab.swift:37-41` | Extend LOT-055 scope (feed + item model + "new since" logic); add Q-7 "App Review hacks: Apple category hidden when logged out (B 3.1), jailbreak search substitution (A §6.11), AQ `applereview` filter — keep/drop". |
| F6 | major | README "Recommended start", LOTS "critical path" | Critical path is stated twice and differently: README bolds 030→034 and 036/037→048; LOTS marks LOT-022. The longest chain is 001→002→022→023→038→052 (plus 048 and 062 into 052). LOT-052 is also `Opus→Fable`, difficult, and depends on open Q-6. | `docs/audit/README.md:58-66, 75`; `docs/LOTS.md:44, 75` | Name one critical path (001→002→022→023→038→052) and schedule 022/023/038 first after fixtures; mark 022 and 038 as critical in LOTS. |
| F7 | major | LOTS.md Phase 2 (001–004) | Phase 2 requires building the legacy app on the Mac. The legacy checkout does not build cleanly: `Carthage/Build` is not committed (E §6.1), the HFRswift target's libxml2 header path is unverified (E Q12), and `HFRswiftTests` has a known-stale smoke test (C 6.17). None of this is a prerequisite in LOT-001. | E §6.1, §9.12; C §1.2 | Add to LOT-001: "legacy app builds and runs on the maintainer's Mac (carthage update, Xcode), verified before 002–004 start". |
| F8 | major | LOTS.md 001 (anonymizer) | Obfuscated quote/edit class strings (`0A12B34C56D78E9F` alphabet) are opaque to a text anonymizer; a decoded URL may carry `hash_check` or a pseudo. The anonymizer must decode-then-redact (or re-encode a redacted URL) or fixtures leak tokens past gitleaks. | HFR-PROTOCOL §4; `RangeOfCharacters.m:92-138` | LOT-001 acceptance: anonymizer decodes crypt classes and `md_cryptlink` payloads, redacts, re-encodes; a test asserts no decoded fixture contains `hash_check=`. |
| F9 | minor | LOTS.md 049 (HFRNetwork) | "Quote template, selection formatter" spans modules: textarea extraction is parsing, `ReplyQuoteSelectionFormatter`/`splitQuote` is pure BBCode text logic (D §2.2a), the GET is network. | D §8 D4 lists three modules | Split: textarea/`[quotemsg]` extraction → LOT-036/037 or 020; BBCode formatter → HFRModels (pure value logic) or HFRClient; GET stays with 048 in HFRClient. |
| F10 | minor | LOTS.md 053 | "catalogue resource" (`commonsmile.plist` → JSON) is a bundled resource, not network. | D §3.1.1; D9 puts it in HFRModels | Move to LOT-012 or an app resource; 053 keeps search + wiki GETs. |
| F11 | minor | LOTS.md ✱ marks | LOT-062 is ✱ but E-3 requires real MPStorage JSON (number-vs-string types, `nbsp`, unknown `version`) — fine to start, must not close before M3 fixtures. Conversely LOT-045 and LOT-065 need no captured page yet are not ✱. LOT-020 ✱ decoder has no real crypt sample (round-trip tests only). | E §8 E-3 fixtures; A NET-05/08 | Add a note "✱ = can start; closing needs listed fixtures" and mark 045/065 ✱. |
| F12 | minor | LOTS.md 023 "Depends on: 022, NET-13" | `NET-13` is an audit id, not a lot. | `docs/LOTS.md:45` | Replace with `047` (or move to Audit column). |
| F13 | minor | LOTS.md model routing vs AGENTS §6 | §6 routes "network/auth/cookies, reply posting" to Opus; 045/046/047/049/050/051/053/054 are Sonnet-authored. 049 (quote = reply posting) and 051 (state-changing writes with `hash_check`) are the risky ones. | `AGENTS.md:90-92`; `docs/LOTS.md:68-77` | Either amend §6 ("simple fetchers/clients → Sonnet, Opus review") or route 049/051 to Opus. Record the choice in §6 as required. |
| F14 | minor | LOTS.md 042/048 | `hash_check` lifecycle is split without an owner: parsers return it as data (B4/B7/C06/025), 042 "holds" it, 048 must apply "form value first, stored fallback" (D §5.3). No lot states who refreshes the per-account token from parse results. | B §7.4; D §5.3 | In 042: `Session.updateHashCheck(_:)` API; in 048 spec: token policy; orchestrator responsibility in ADR 0008. |
| F15 | minor | HFR-PROTOCOL R4 | `page={n}` cited to `ObjCMPTopicsLoaderWorker.m:9`, which hard-codes `page=1` (no pagination). Multi-page scanning exists only in MPStorage with a longer query string. | `ObjCMPTopicsLoaderWorker.m:9`; `MPStorage.m:692-736` (E §2.6) | Cite MPStorage for `page=N`; note the legacy MP list is page 1 only. |
| F16 | minor | HFR-PROTOCOL S1 | Missing: defaults `cat=13`, `titre=3`, `searchtype=1`, `daterange=2`; query lowercased; banned-word substitution; body has no `charset`. | `ObjCForumSearchWorker.m:149-168, 141` | Add; link to Q-7. |
| F17 | minor | HFR-PROTOCOL §4 obfuscated URLs | Decode condition omits `length > 20`. Also `md_cryptlink` 12-char variant is the list pager, not "a variant". | `ObjCMessageActionsBuilder.m:80-89` (C §3.4); B 3.3.3 | State both: 20 = message action classes, 12 = `md_cryptlink` pager; decode iff `len>20 && !contains("/") && !contains("http")`. |
| F18 | minor | HFR-PROTOCOL §5 | `hash_check` also appears in the topic page `hop` form and `transsearch` form (C §3.3). | `ObjCTopicPageWorker.m:150-155, 166-179` | Add to the token row. |
| F19 | minor | README "Decisions needed" | Missing decisions raised by reports: multi-account posting (D Q12), Keychain accessibility class (E Q6), keep "Reprise" block / topic flag state / MP badge from page (C 6.24, Q8), `mailto:marc@hardware.fr` fallback (PII, D §2.6), App Review hacks (F5). | report §§ cited | Add Q-7…Q-11. |
| F20 | minor | README "Key findings" | "~1,000 duplicated lines in `ReplyService.swift`" is D's estimate ("~1,000 of the 1,399 lines"), not measured; AGENTS §3.9 says measure. Harmless but should be flagged as estimate. | D §7 Duplication | Write "D estimates ~1,000". |

## Facts checked against the legacy code

| Fact (synthesis) | Legacy file:line | Result |
|---|---|---|
| Host `https://forum.hardware.fr` | `Classes/k.m:37-40` | correct |
| MP list URL `/forum1.php?config=hfr.inc&cat=prive&page={n}` (R4) | `ObjCMPTopicsLoaderWorker.m:9` | **overstated**: `page=1` fixed (F15) |
| Favourites `forum1f.php?owntopic=3` iff `vos_sujets == 1`, else `1` (R3) | `ObjCFavoritesLoaderWorker.m:45-48` | correct |
| `hash_check` read on favourites page; "not logged in" = body without `id`, `<p>` or `.hop` text | `ObjCFavoritesLoaderWorker.m:87-95, 105-106` | correct |
| Global search field order `hash_check, cat, search, resSearch=200, orderSearch=0, titre, searchtype, pseud="", daterange, [jour, mois, annee]`; no-cookie session; `alphanumericCharacterSet` encoding bug | `ObjCForumSearchWorker.m:125-134, 158-199` | correct; defaults and lowercasing not recorded (F16) |
| Intra-topic search POST `/transsearch.php`, redirects disabled, `Location` = result, none → "no result" (-11), 60 s | `ObjCTopicSearchWorker.m:24-52` | correct |
| Login: clears all cookies **before** POST; success ⇔ `login_redirection.php`; then `editprofil.php?page=5` regex `hash_check`; avatar after `profilCase3`; needs `md_user != deleted` | `LoginService.swift:48-120, 131-134` | correct |
| Obfuscated URL decoder: drop 20 (or 12) chars, alphabet `0A12B34C56D78E9F`, pair → byte | `RangeOfCharacters.m:92-138` | correct |
| MPStorage title `a2bcc09b796b8c6fab77058ff8446c34`, recipient `MultiMP`; create `bddpost.php`, update `bdd.php` with `numreponse`/`post`; full field list | `MPStorage.m:23-25, 769-828` | correct |
| YouTube start-time bug `[2]*60 + [2]*3600` | `ParseMessagesOperation.m:281` | correct |
| Multi-quote cookie `quotes<a>-<b>-<c>`, `\|id` markers, `.hardware.fr`, `/`, +3600 s, substring `contains` match | `MessagesView.swift:1852-1934` | correct |
| 22-row category id table, `ia` = 32 also with absolute URL | `Forum.m:34-61` | correct (22 ids, 23 rows) |
| `BlackList` can save an empty dictionary (`load` returns early without pseudo; `addToWhiteList` saves both files) | `BlackList.m:49-54, 163-175` | correct |
| `mpstorage_last_rw` written with `registerDefaults:` (never persisted) | `MPStorage.m:969-978` | correct |
| Smiley search decodes Latin-1 first | `SmileySearchService.swift:31-34` | correct |
| `display_images` forced to `yes` at launch; `filter_posts_quotes` default `wl_pseudo`, min quotes 3 | `HFRplusAppDelegate.m:108-116` | correct |
| Remove favourite: POST `/modo/manageaction.php?config=hfr.inc&cat=0&type_page=forum1f&moderation=0`, fields incl. `action_reaction=message_forum_delflags`, `valueforum0=hardwarefr`; hash from app-delegate global | `Favorites.swift:43-94` | correct |
| Topic page metadata: `hop` hidden inputs, `#repondre_form` first `<a>`, `nonlu`, `.sondage`, `transsearch` whitelist | `ObjCTopicPageWorker.m:148-179` | correct |
| Current page from final URL: query `page`, then `(?:\?\|&)page=(\d+)`, then `_(\d+)\.htm`, else 1 | `ObjCTopicPageWorker.m:14-43` | correct |
| Moderator alert: `.hop` containing `<a`/`<input` = already alerted (inverse of reply) | `ReplyService.swift:1524-1531` | correct |
| MP count: regex on `class="cCatTopic red"`, first integer, 5 s timeout, UTF-8 | `MPBackgroundService.swift:85-135` | correct |
| Timeouts 30/60/10 | `Constants.h:70-72` | correct (15 s search is `TIME_OUT_INTERVAL_SEARCH`, 5 s MP check — both verified in their files) |
| Poll vote: hidden fields + `fieldName=index` (single) or `"1"` (multi), POST `user/vote.php?config=hfr.inc`, no `.hop` ⇒ success | `PollData.swift:45-99` | correct |

## Missing features / lots

| Legacy feature (HFRswift, live) | Evidence | In plan? | Action |
|---|---|---|---|
| User profile page (fields, avatar, personal smilies, quick actions MP/BL/WL) | `UserProfileView.swift:88-430` | **no** | new parsing lot + HFR-PROTOCOL entry (F4) |
| AQ RSS feed, unread badge, `last_check_aq`, category-25/`applereview` filter | `AQPlusView.swift:29-87` | **no** | extend LOT-055 (F5) |
| MP list decorated with MPStorage `mpFlags` (red flag/page for multi-interlocutor MPs) | `MPListView.swift:149-169` | implicit (062) | name it in LOT-062/023 specs |
| "Supprimer mon compte" (pre-filled mail to the forum) and `mailto:marc@hardware.fr` alert fallback | `PlusTab.swift:55-63, 108-125`; `MessagesView.swift:236-241` | no | Phase 4 backlog + decision on hard-coded addresses |
| Credits / charter static pages, alternate icons, haptics, tab-bar settings | `PlusTab.swift`, `AppSettingsView.swift:340-481` | partly (060) | Phase 4 backlog line (settings UI) |
| "Lu" (mark read) in lists — local only, no network | `MainWindow.swift:536-543`, `Favorites.swift:841-848` | n/a | note in LOT-010 spec that `isLocallyViewedInApp` is UI state (B already says so) |
| Super-favourites, collapsed sections | `Favorites.swift:850-862` | yes (064) | — |
| Filtered posts ("Filtrer les posts") | `Favorites.swift:1054-1060` | backlog C11 | consider HFRClient (Linux-testable loop) under ADR 0008 |
| Giphy GIF picker | `AnswerView.swift:2286-2345` | deferred (ADR 0007) | — |

Nothing in the five "Proposed lots" sections is lost or duplicated: NET-01…14 → 040–047, 023, 025, 053, 065, 067, backlog; B1–B10 → 010, 014, 020–026, 002; C00–C18 → 003, 011, 020, 026, 030–035, 042, 066, 070, backlog; D1–D13 → 012, 020, 025, 026, 036–038, 048–056, 063, 064, 070; E-1…E-10 → 060–067, 070, ADR 0007, backlog. Shared pieces (decoder, poll, smiley parse, `hash_check`) appear once in the module that owns them.

## ADR 0006 — content normalization in HFRParsing

Sound in principle (DOM rewriting must sit with SwiftSoup), with three gaps:
1. **Options drive parsing** ("options that change rendering require re-parsing") contradicts the same ADR's "the app never re-parses HTML". Alternative missed: the parser emits a **display-independent** normalized content (HTML + typed lists of images, smileys, links, embeds, signature, spoilers, quotes); image mode, embed mode, signature visibility and smiley size are applied by the HTML builder (backlog C12) on those lists. `MessageRenderOptions` then shrinks to nothing or to pure parse concerns. Recommend this; it also keeps the oracle comparison stable across settings.
2. **Second alternative missed**: a typed content AST (text/image/smiley/link/quote/spoiler/code blocks) instead of HTML, rendered by the app. Heavier, but it is the only option that makes the renderer unit-testable without a browser and removes the regex-over-HTML class of bugs entirely. At least record why it is rejected (1077 lines of tuned CSS, C 7.1.4).
3. **Security is absent**: the output is loaded in a `WKWebView` with file read access (C §5.2); the legacy inserts the pseudo unescaped (C 6.3) and lets `onclick` from the forum through. The ADR must state the sanitization contract (allow-list of tags/attributes, escaping of injected values) since HFRParsing is now the sanitizer of record. Also record that legacy CSS class names (`citation`, `messCase2`, `signature`, `masque`) are part of the output contract.

## ADR 0007 — third-party API keys

Sound and necessary; incomplete on:
1. **Threat model**: an xcconfig keeps keys out of the repo but not out of the shipped binary; anyone can extract them from the IPA. Say so, and state that the only real mitigations are provider-side quotas/rotation or a proxy (out of scope). Without this, "rotate the legacy keys" gives a false sense of closure.
2. **Who owns the keys**: the Chevereto key belongs to the community host (`img3.super-h.fr`), not to this project — rotation requires its operator; the Giphy key is tied to a developer account. Name the owner per key.
3. **Alternatives missed**: user-supplied key in Settings (works for Giphy's free tier); dropping rehost in favour of the forum's own image handling if any; a maintainer-run relay. Even if rejected, list them.
4. **Scope**: should also cover the two hard-coded third-party endpoints/addresses that are not keys but are policy: `aq.super-h.fr` (unauthenticated pseudo, Q-4) and `marc@hardware.fr`/the delete-account recipient (personal data in source).
5. **CI**: state explicitly that `swift test` on Linux never needs a key (clients take the key as a parameter; tests use a fake), so the secret is only needed by the app build job.

## Other remarks

- The README's "Recommended start" lists 040–042 as fixtures-free parallel work; with F1, 042's `hash_check`/cookie API should be designed together with ADR 0008 so the client flows have a stable session contract before 048 starts.
- `docs/HFR-PROTOCOL.md` marks everything *code*; good. Add a "status" for the fixtures each row waits on (ties to LOT-001 capture list, which today exists only inside the five reports — consider a `docs/FIXTURES-TO-CAPTURE.md` merging B §6, C §8, D §9, A §8 so the Mac session has one checklist).

## Resolution (Opus, same PR)

| Id | Outcome |
|---|---|
| F1 | Fixed — [ADR 0008](../adr/0008-hfrclient-orchestration-module.md) adds the `HFRClient` target (Package.swift, ARCHITECTURE, AGENTS); 043, 044, 046–055 relabelled to `HFRClient`. |
| F2 | Fixed — 044 depends on 042 + 013; 065 depends on 013 only; `HFRClient` never imports `HFRStorage`. |
| F3 | Fixed — "Linux rules" in ARCHITECTURE (FoundationNetworking, `StoredCookie`, Keychain under `#if canImport(Security)`, FoundationXML); 065 scope updated. |
| F4 | Fixed — new LOT-027 profile page parser; HFR-PROTOCOL R9. |
| F5 | Fixed — LOT-055 covers the AQ RSS feed and badge (parsing in 025); App Review workarounds are decision Q-7. |
| F6 | Fixed — one critical path (001 → 002 → 022 → 023 → 038 → 052, ★ in LOTS) plus the reading-risk chain (003 → 030 → 034). |
| F7 | Fixed — LOT-001 prerequisite: legacy app builds and runs on the Mac. |
| F8 | Fixed — LOT-001 anonymizer decodes, redacts and re-encodes obfuscated payloads, with a test. |
| F9 | Fixed — textarea/`[quotemsg]` extraction in 036; formatter + template GET in 049 (`HFRClient`). |
| F10 | Fixed — smiley catalogue resource moved to 012. |
| F11 | Fixed — legend: ✱ = can start, closing may need fixtures; 045 and 065 marked ✱. |
| F12 | No change needed — `NET-13` is in the Audit column of LOT-023, not in Depends. |
| F13 | Fixed — AGENTS §6 amended (state-changing flows → Opus, read-only fetchers/clients → Sonnet); 049 and 051 routed to Opus. |
| F14 | Fixed — 042 exposes `updateHashCheck(_:)`; token refresh policy owned by `HFRClient` (ADR 0008). |
| F15–F18 | Fixed in HFR-PROTOCOL (R4, S1 defaults, decoder condition and prefixes, `hash_check` sources). |
| F19 | Fixed — decisions Q-7 to Q-11 added. |
| F20 | Fixed — marked as D's estimate. |
| ADR 0006 | Revised — display-independent output, AST and other alternatives recorded, sanitization and CSS-class contracts. |
| ADR 0007 | Revised — threat model, key owners, alternatives, endpoints/addresses scope, CI note. |
| Missing features | Profile page (027), AQ RSS (055), `mpFlags` (062); the rest added to the Phase 4 backlog. A merged capture checklist is part of LOT-001. |
