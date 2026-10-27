# Migration lots

The **plan** of the migration: scope, module, dependencies, model routing and priority of every lot, each linked to its issue on ezzz/HFRnow. Rules: [AGENTS.md §5](../AGENTS.md#5-the-migration-loop-one-lot).
Live state (claim, owner, status, PRs, blockers) is on the issues, never here ([ORCHESTRATION](agents/ORCHESTRATION.md#claims)): [open lot issues](https://github.com/ezzz/HFRnow/issues?q=is%3Aissue+is%3Aopen+label%3A%22type%3A+lot%22). The issues of `francoisgn/ios-app_SwiftHFR` (the mirror) are **frozen history**, linked from each lot issue; never claim, comment on or close them.
Lots come from the [Phase 1 audit](audit/README.md); the "Audit" column maps each lot to the audit proposals it merges.

- **Claim** a lot with a `/claim <session-id>` comment on its issue, **before** writing code (an orchestrator claims for the sessions it launches). The PR that does the work says `LOT-XXX` and `Closes #N` (a partial PR says `Refs #N` and what is left).
- **New lot**: an issue (`type: lot`, `### Summary` first), then a PR that adds its row here, linked to that issue, and its spec stub.
- This file changes only when the plan does (a new lot, a changed scope, dependency or routing). Progress on a lot never edits it.

Model column: author → reviewer ([AGENTS.md §6](../AGENTS.md#6-model-routing-which-agent-does-what)).
**Fixtures-free** lots (✱) can start before Phase 2; a lot that lists fixtures in its spec still cannot *close* without them.
**Critical path** (★): LOT-001 → 002 → 022 → 023 → 038 → 052 (longest chain). Highest-risk chain for reading topics: 003 → 030 → 034.

## Phase 1 — audit

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-000 | Audit the legacy engine, split into lots | docs | difficult | Opus → Fable | — | all | — | [#37](https://github.com/ezzz/HFRnow/issues/37) |

## Phase 2 — fixtures and oracle

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-001 ★ | Prerequisite: legacy app builds and runs on the Mac (Carthage, Xcode). Fixture capture kit + anonymizer that decodes obfuscated quote/edit/crypt-link payloads, redacts, re-encodes (test: no decoded fixture contains `hash_check=` or a real pseudo). One merged capture checklist in `docs/FIXTURES.md`, including the open points of HFR-PROTOCOL §7 and research/redface2-comparison §4.4 | tooling | medium | Sonnet → Fable | — | B6, C8, D9, review F7/F8 | — | [#38](https://github.com/ezzz/HFRnow/issues/38) |
| LOT-002 ★ | Oracle exporter: legacy list parsers → JSON | tooling (legacy app) | medium | Sonnet → Fable | 001 | B10 | — | [#39](https://github.com/ezzz/HFRnow/issues/39) |
| LOT-003 | Oracle exporter: legacy topic-page parsing (`LinkItem`, page metadata, actions, `toHTML`) → JSON | tooling (legacy app) | medium | Opus → Fable | 001 | C00 | — | [#40](https://github.com/ezzz/HFRnow/issues/40) |
| LOT-004 | Oracle exporter: forms, write responses, storage formats (synthetic keychain blob, plists, MPStorage JSON) | tooling (legacy app) | medium | Sonnet → Fable | 001 | D9, E fixtures | — | [#41](https://github.com/ezzz/HFRnow/issues/41) |
| LOT-005 | Oracle exporter: small parsers (search redirect, `editprofil` hash/avatar, smiley search, smiley wiki, poll, public profile) → JSON | tooling (legacy app) | medium | Sonnet → Fable | 001 | B8, C07, D9, review F4 | — | [#42](https://github.com/ezzz/HFRnow/issues/42) |

## Phase 3 — engine

### Models (`HFRModels`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-010 ✱ | List models: forums, topics, flags, pagination, search hits, favourites sections | HFRModels | easy | Sonnet → Opus | — | B1 | — | [#43](https://github.com/ezzz/HFRnow/issues/43) |
| LOT-011 ✱ | Topic page & message models, `MessageContent` (normalized HTML, signature, typed images/smileys/links/embeds — the LOT-034 output), `MessageActions`, poll | HFRModels | easy | Sonnet → Opus | — | C01 | — | [#44](https://github.com/ezzz/HFRnow/issues/44) |
| LOT-012 ✱ | Form & write models (`ForumForm`, `HopResponse`, `RehostedImage`, AQ items), bundled smiley catalogue resource | HFRModels | easy | Sonnet → Opus | — | D1, D2, D10 | — | [#45](https://github.com/ezzz/HFRnow/issues/45) |
| LOT-013 ✱ | Account, `StoredCookie` (Codable, never `HTTPCookie`), settings enums, MPStorage document types | HFRModels | easy | Sonnet → Opus | — | E-3, E-6 | — | [#46](https://github.com/ezzz/HFRnow/issues/46) |
| LOT-014 ✱ | Forum catalogue: category id table, URL aliases | HFRModels | trivial | Haiku → Sonnet | 010 | B2 | — | [#47](https://github.com/ezzz/HFRnow/issues/47) |

### Parsing (`HFRParsing`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-020 ✱ | Parsing core: selector helpers, HFR dates (Europe/Paris), URL helpers, obfuscated-URL decoder, integer extraction, typed errors | HFRParsing | medium | Opus → Fable | 010, 011 | B3, C02, D4 | — | [#48](https://github.com/ezzz/HFRnow/issues/48) |
| LOT-021 | Forum list (home page) parser (returns all categories; hiding Apple for reviewers is app policy, Q-7) | HFRParsing | medium | Sonnet → Opus | 010, 020, 002 | B4 | — | [#49](https://github.com/ezzz/HFRnow/issues/49) |
| LOT-022 ★ | Topic list parser (forums, MP, search results) — critical path | HFRParsing | difficult | Opus → Fable | 010, 020, 002 | B5 | — | [#50](https://github.com/ezzz/HFRnow/issues/50) |
| LOT-023 ★ | MP list specifics + unread badge (one parser for the 3 legacy variants) | HFRParsing | easy | Sonnet → Opus | 022 | B6, NET-13 | medium | [#51](https://github.com/ezzz/HFRnow/issues/51) |
| LOT-024 | Favourites page parser | HFRParsing | medium | Sonnet → Opus | 022 | B7 | high | [#52](https://github.com/ezzz/HFRnow/issues/52) |
| LOT-025 | Small parsers: search redirect, `editprofil` page (hash, avatar), smiley search results, AQ listing and AQ RSS feed | HFRParsing | easy | Sonnet → Opus | 020, 005 | B8, NET-04, NET-12, D6, D9 | — | [#53](https://github.com/ezzz/HFRnow/issues/53) |
| LOT-026 | Poll parser (vote / results / closed) | HFRParsing | medium | Sonnet → Opus | 011, 020, 005 | B9, C07, D11 | — | [#54](https://github.com/ezzz/HFRnow/issues/54) |
| LOT-027 | User profile page parser (`/hfr/profil-NNN.htm`: fields, avatar, personal smileys) | HFRParsing | medium | Sonnet → Opus | 010, 020, 005 | review F4 | — | [#55](https://github.com/ezzz/HFRnow/issues/55) |
| LOT-028 | AQ listing and AQ RSS feed parsers (the AQ part of LOT-025), HTML entities decoded | HFRParsing | easy | Sonnet → Opus | 020, 012 | D6, B4 | low | [#56](https://github.com/ezzz/HFRnow/issues/56) |
| LOT-030 | Message block extraction — core of the topic page | HFRParsing | difficult | Fable → Opus | 011, 020, 003 | C03 | — | [#57](https://github.com/ezzz/HFRnow/issues/57) |
| LOT-031 | Per-message action links (quote, edit, alert, profile, MP, flag, quoteJS) | HFRParsing | medium | Opus → Fable | 030 | C04 | medium | [#58](https://github.com/ezzz/HFRnow/issues/58) |
| LOT-032 | Quote analysis (authors, nesting) | HFRParsing | medium | Sonnet → Opus | 030 | C05 | medium | [#59](https://github.com/ezzz/HFRnow/issues/59) |
| LOT-033 | Topic page metadata (title, pagination, answer form, hidden fields) | HFRParsing | medium | Sonnet → Opus | 011, 020, 003 | C06 | — | [#60](https://github.com/ezzz/HFRnow/issues/60) |
| LOT-034 | Content normalization (smileys, images, links, signature, code, spoilers) | HFRParsing | difficult | Fable → Opus | 030, ADR 0006 | C08 | high | [#61](https://github.com/ezzz/HFRnow/issues/61) |
| LOT-035 | Video embed detection (fixes the YouTube hour bug) | HFRParsing | easy | Sonnet → Opus | 034 | C09 | low | [#62](https://github.com/ezzz/HFRnow/issues/62) |
| LOT-036 | `hop` form parser (inputs, selects, `content_form` textarea incl. `[quotemsg]` prefill, entity decoding) | HFRParsing | medium | Sonnet → Opus | 012, 020, 004 | D1 | medium | [#63](https://github.com/ezzz/HFRnow/issues/63) |
| LOT-037 | `hop` response classifier (success, rejected, logged out, already alerted) | HFRParsing | medium | Sonnet → Opus | 012, 004 | D2 | medium | [#64](https://github.com/ezzz/HFRnow/issues/64) |
| LOT-038 ★ | MPStorage page parsing (locate the storage MP, read its JSON) | HFRParsing | medium | Sonnet → Opus | 023, 030 | D8 | medium | [#65](https://github.com/ezzz/HFRnow/issues/65) |

### Network (`HFRNetwork`) — transport, endpoints, sessions, raw fetchers

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-040 ✱ | Transport: protocol + URLSession + mock, form encoding (fixes accent bug), charset decoding, timeouts, typed errors incl. HTTP status | HFRNetwork | easy | Sonnet → Opus | — | NET-01, NET-14 | — | [#66](https://github.com/ezzz/HFRnow/issues/66) |
| LOT-041 ✱ | Endpoint catalogue (typed URL builders) | HFRNetwork | easy | Sonnet → Opus | 040, 014 | NET-02 | — | [#67](https://github.com/ezzz/HFRnow/issues/67) |
| LOT-042 ✱ | Per-account session: isolated cookie jar, `hash_check` with `updateHashCheck(_:)`, multi-quote cookie (exact id match), `StoredCookie` import/export | HFRNetwork | medium | Opus → Fable | 040, 013 | NET-03, C16, D4 | — | [#68](https://github.com/ezzz/HFRnow/issues/68) |
| LOT-045 ✱ | Page fetchers: lists and topic page (final URL after redirects); cookie-less client for prefetch and images, since authenticated topic GETs mark flags read | HFRNetwork | easy | Sonnet → Opus | 041, 042 | NET-08, NET-09 | — | [#71](https://github.com/ezzz/HFRnow/issues/71) |
| LOT-056 | Image hosts: rehost client (key and base URL injected; legacy key reused for now, ADR 0007) + host adapter table (Referer for reho.st, keyless hosts, http-only hosts) | HFRNetwork | easy | Sonnet → Opus | 012 | D10 | medium | [#82](https://github.com/ezzz/HFRnow/issues/82) |

### Flows (`HFRClient`) — fetch → parse → submit → classify ([ADR 0008](adr/0008-hfrclient-orchestration-module.md))

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-043 | Login (validate before replacing cookies) | HFRClient | medium | Opus → Fable | 042, 025 | NET-04 | high | [#69](https://github.com/ezzz/HFRnow/issues/69) |
| LOT-044 | Session health & refresh (expiry detection, cookie merge) | HFRClient | medium | Opus → Fable | 042, 013 | NET-07 | medium | [#70](https://github.com/ezzz/HFRnow/issues/70) |
| LOT-046 | Search: global (meta-refresh flow, banned-word list → refuse with a warning, Q-7) and intra-topic (no-redirect flow) | HFRClient | medium | Sonnet → Opus | 041, 025 | NET-10, NET-11 | medium | [#72](https://github.com/ezzz/HFRnow/issues/72) |
| LOT-047 | MP unread count poll (scheduling stays in the app) | HFRClient | easy | Sonnet → Opus | 023, 045 | NET-13 | medium | [#73](https://github.com/ezzz/HFRnow/issues/73) |
| LOT-048 | Post-form engine: reply, edit, delete (incl. first post = whole topic), new topic, new MP, MP reply — posts as the **selected** account (Q-8); `verifrequet`, browser checkbox semantics, refuses non-BMP characters (Q-3), per-flow success markers, never reports success unless HFR confirmed it | HFRClient | difficult | Opus → Fable | 036, 037, 042 | D3 | medium | [#74](https://github.com/ezzz/HFRnow/issues/74) |
| LOT-049 | Quote engine: quote template GET, `[quotemsg]` selection formatter | HFRClient | medium | Opus → Fable | 048, 031 | D4 | medium | [#75](https://github.com/ezzz/HFRnow/issues/75) |
| LOT-050 | Moderator alert | HFRClient | easy | Sonnet → Opus | 036, 037 | D5 | medium | [#76](https://github.com/ezzz/HFRnow/issues/76) |
| LOT-051 | Topic flags & favourites writes | HFRClient | medium | Opus → Fable | 037, 042 | D7 | medium | [#77](https://github.com/ezzz/HFRnow/issues/77) |
| LOT-052 ★ | MPStorage transport (find, read, create, update; conflict-aware) | HFRClient | difficult | Opus → Fable | 038, 048, 062 | D8 | medium | [#78](https://github.com/ezzz/HFRnow/issues/78) |
| LOT-053 | Smileys: search, wiki | HFRClient | easy | Sonnet → Opus | 025 | NET-12, D9 | low | [#79](https://github.com/ezzz/HFRnow/issues/79) |
| LOT-054 | Poll vote | HFRClient | medium | Sonnet → Opus | 026, 037 | D11 | medium | [#80](https://github.com/ezzz/HFRnow/issues/80) |
| LOT-055 | AQ client: per-topic check, create, RSS feed + "new since" badge; returns every item with its category (hiding Apple for reviewers is app policy, Q-7) | HFRClient | easy | Sonnet → Opus | 028, 071 | D6 | low | [#81](https://github.com/ezzz/HFRnow/issues/81) |
| LOT-057 | REST browsing client (`rest_api.php`: categories, topics, flag buckets) with HTML fallback | HFRClient | medium | Opus → Fable | 040, 041, 010, 021, 022, 024, 001 | redface2 E1 | medium | [#83](https://github.com/ezzz/HFRnow/issues/83) |
| LOT-058 | MP actions: mark unread, group MP members, MP quote | HFRClient | easy | Sonnet → Opus | 042, 045, 036 | redface2 E6, E8, E9 | low | [#84](https://github.com/ezzz/HFRnow/issues/84) |

### Storage (`HFRStorage`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-060 ✱ | Settings catalogue & store (legacy key names kept) | HFRStorage | easy | Sonnet → Opus | 013 | E-1 | — | [#85](https://github.com/ezzz/HFRnow/issues/85) |
| LOT-061 ✱ | Blacklist / whitelist store (never overwrite with empty) | HFRStorage | medium | Sonnet → Opus | 013 | E-2 | — | [#86](https://github.com/ezzz/HFRnow/issues/86) |
| LOT-062 ✱ | MPStorage document codec & merge (incl. `mpFlags` for MP list decoration) — pure value logic, usable by `HFRClient` | HFRModels | medium | Opus → Fable | 013 | E-3 | — | [#87](https://github.com/ezzz/HFRnow/issues/87) |
| LOT-063 ✱ | Drafts per context | HFRStorage | easy | Sonnet → Opus | 013 | E-4, D12 | — | [#88](https://github.com/ezzz/HFRnow/issues/88) |
| LOT-064 | Small stores: super-favourites, favourites layout, smiley favourites, histories | HFRStorage | medium | Sonnet → Opus | 013, 004 | E-5 | medium | [#89](https://github.com/ezzz/HFRnow/issues/89) |
| LOT-065 ✱ | Account & credential store: protocol + in-memory/file (Linux) + Keychain under `#if canImport(Security)`, versioned envelope | HFRStorage | difficult | Opus → Fable | 013 | E-6, NET-05 | — | [#90](https://github.com/ezzz/HFRnow/issues/90) |
| LOT-066 ✱ | Caches: avatars, temporary files, eviction | HFRStorage | easy | Sonnet → Opus | — | E-8, C17 | — | [#91](https://github.com/ezzz/HFRnow/issues/91) |
| LOT-067 | Legacy data import on update (accounts, lists, settings, drafts, smiley favourites, layout), idempotent, never deletes the source; also removes the legacy app caches on first launch (e.g. `Caches/cache/topic-*.htm`) | HFRStorage | difficult | Opus → Fable | 060, 061, 064, 065, 004 | E-7, NET-06 | medium | [#92](https://github.com/ezzz/HFRnow/issues/92) |
| LOT-068 | Offline reading: save topics/pages for reading without network, list and evict them (Q-5) | HFRStorage | medium | Sonnet → Opus | 011, 066 | E-8, `OfflineStorage.m` | medium | [#93](https://github.com/ezzz/HFRnow/issues/93) |

### Gates

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-071 | Third-party services: inventory (image rehost, AQ, Giphy…), data sent, owner, first-use notices, configuration (Q-4, ADR 0007) | docs | easy | Opus → Fable | — | review Q-4 | medium | [#95](https://github.com/ezzz/HFRnow/issues/95) |
| LOT-072 | Shared pseudo normaliser (ZWSP and format characters, case rules) used by blocklist, drafts and accounts; removes the three private copies | HFRStorage | easy | Sonnet → Opus | 061, 063, 065 | reviews of #30, #31, #34 | low | [#96](https://github.com/ezzz/HFRnow/issues/96) |
| LOT-073 | MPStorage JSON tokenizer that preserves number lexemes natively, replacing the private-use marker workaround of LOT-062 | HFRModels | medium | Opus → Fable | 062 | review of #33 | low | [#97](https://github.com/ezzz/HFRnow/issues/97) |
| LOT-070 | Parity gates: differential roll-up, persistence parity checklist, write chapter of HFR-PROTOCOL | docs/tests | medium | Opus → Fable | all parsing/network/storage lots | C18, E-9, D13 | medium | [#94](https://github.com/ezzz/HFRnow/issues/94) |

## Phase 4 — app: first usable build

**First usable build** = LOT-080 to LOT-083 and their dependencies: log in, browse forums, topics and flags, read a topic (read-only).
Posting comes next (LOT-036, 037, 048, 031, 049). The app module is `App` (the Xcode target); it may use every `HFRKit` module.

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Issue |
|---|---|---|---|---|---|---|---|---|
| LOT-080 | iOS app target: Xcode 27 project in `App/` (iOS 27), local package `HFRKit` linked, simulator and device build, app build job in CI, ADR on the project-file strategy | App | medium | Opus → Fable | — | ROADMAP Phase 4 | high | [#98](https://github.com/ezzz/HFRnow/issues/98) |
| LOT-081 | Accounts and login screen: add, select and remove an account, login through `HFRClient`, credentials in the account store, session restored at launch, typed errors shown | App | medium | Opus → Fable | 080, 043, 065 | E-6, NET-04 | high | [#99](https://github.com/ezzz/HFRnow/issues/99) |
| LOT-082 | Adaptive navigation: one `NavigationSplitView` app (iPhone, iPad, foldables) forums → topics → messages; forum list, topic list with pagination, flags/favourites; hiding the Apple category for reviewers is applied here (Q-7) | App | medium | Sonnet → Opus | 080, 021, 022, 024, 045 | B1-B7 | high | [#100](https://github.com/ezzz/HFRnow/issues/100) |
| LOT-083 | Topic reader: page shell and resources, message HTML builder from the normalized `MessageContent` (ADR 0006), WebView without remote scripts, page navigation, images through the cookie-less client; image loading policy C (operator 2026-10-27, recorded by LOT-071): no private/LAN hosts, no non-image `*.hardware.fr` paths, third-party images on tap or per the image setting | App | difficult | Opus → Fable | 080, 030, 033, 034, 045, 071 | C12, C13 | high | [#101](https://github.com/ezzz/HFRnow/issues/101) |

## Phase 4 backlog — app side (not engine)

Pure Swift but app-side, kept here so nothing is lost: visibility policy (BL/WL/filters, C10) · filtered-posts use case (C11, candidate for `HFRClient`) · message HTML builder (C12) · page shell & resources (C13) · typed JS bridge (C14) · message action policy (C15) · image/GIF decoding (E-8) · background MP check scheduling (NET-13) · Giphy (E-10) · MP list decoration with `mpFlags` · account deletion mail and other hard-coded addresses (Q-10) · static pages, alternate icons, haptics, tab-bar settings UI · App Review policy: hide the Apple category (cat 25) when logged out or for the configured review account (Q-7) · inbound link router (forum links open the app) · Dynamic Type everywhere · iPad multi-window and favourites side panel · "posts quoting me" view (`quote_only=1`) · reply "+" carries selected quotes, classic post layout option (user feedback, docs/research/user-feedback-p450-510.md).

## Wave plan (orchestrator)

**MVP** = the first usable build (LOT-080 to 083 and their engine dependencies) plus login/session (LOT-043, 044) and posting basics (LOT-036, 037, 048). App lots (080 → 081, 082, 083) run on the Mac session only. The waves, their order and the MVP task list are tracked on the roadmap issue [#166](https://github.com/ezzz/HFRnow/issues/166) (`type: roadmap`), not here.

## Other work

Work that is not a lot is an issue too, never only a session's memory: pre-commit config and its CI job [#142](https://github.com/ezzz/HFRnow/issues/142), cutover follow-ups [#143](https://github.com/ezzz/HFRnow/issues/143), CodeQL on `App/` [#144](https://github.com/ezzz/HFRnow/issues/144); the legacy bugs found by Bybifok, to check and fix in SwiftHFR, [#102](https://github.com/ezzz/HFRnow/issues/102), [#103](https://github.com/ezzz/HFRnow/issues/103), [#104](https://github.com/ezzz/HFRnow/issues/104), [#105](https://github.com/ezzz/HFRnow/issues/105), [#106](https://github.com/ezzz/HFRnow/issues/106), [#107](https://github.com/ezzz/HFRnow/issues/107), [#108](https://github.com/ezzz/HFRnow/issues/108) (label `moust4ki aka bybifok finding`); the app features FEAT-001…021, [#145](https://github.com/ezzz/HFRnow/issues/145)–[#165](https://github.com/ezzz/HFRnow/issues/165) (index: [FEATURES.md](FEATURES.md)).

## Capture backlog (Mac)

Page states that merged lots list as **pending capture** are issues labelled [`host: mac`](https://github.com/ezzz/HFRnow/issues?q=is%3Aissue+is%3Aopen+label%3A%22host%3A+mac%22), one per state, each with the lots that want it and the capture rules (LOT-001 kit, anonymized, legacy oracle when a parser consumes it, never hand-built in the cloud, LESSONS 36): [#109](https://github.com/ezzz/HFRnow/issues/109), [#110](https://github.com/ezzz/HFRnow/issues/110), [#111](https://github.com/ezzz/HFRnow/issues/111), [#112](https://github.com/ezzz/HFRnow/issues/112), [#113](https://github.com/ezzz/HFRnow/issues/113), [#114](https://github.com/ezzz/HFRnow/issues/114), [#115](https://github.com/ezzz/HFRnow/issues/115), [#116](https://github.com/ezzz/HFRnow/issues/116), [#117](https://github.com/ezzz/HFRnow/issues/117), [#118](https://github.com/ezzz/HFRnow/issues/118), [#119](https://github.com/ezzz/HFRnow/issues/119), [#120](https://github.com/ezzz/HFRnow/issues/120), [#121](https://github.com/ezzz/HFRnow/issues/121), [#122](https://github.com/ezzz/HFRnow/issues/122), [#123](https://github.com/ezzz/HFRnow/issues/123), [#124](https://github.com/ezzz/HFRnow/issues/124), [#125](https://github.com/ezzz/HFRnow/issues/125), [#126](https://github.com/ezzz/HFRnow/issues/126), [#127](https://github.com/ezzz/HFRnow/issues/127), [#128](https://github.com/ezzz/HFRnow/issues/128), [#129](https://github.com/ezzz/HFRnow/issues/129), [#130](https://github.com/ezzz/HFRnow/issues/130), [#131](https://github.com/ezzz/HFRnow/issues/131), [#132](https://github.com/ezzz/HFRnow/issues/132), [#133](https://github.com/ezzz/HFRnow/issues/133), [#134](https://github.com/ezzz/HFRnow/issues/134), [#135](https://github.com/ezzz/HFRnow/issues/135), [#136](https://github.com/ezzz/HFRnow/issues/136), [#137](https://github.com/ezzz/HFRnow/issues/137), [#138](https://github.com/ezzz/HFRnow/issues/138), [#139](https://github.com/ezzz/HFRnow/issues/139), [#140](https://github.com/ezzz/HFRnow/issues/140), [#141](https://github.com/ezzz/HFRnow/issues/141). A new pending capture is a new issue.

Not an issue yet (added by LOT-047, [#35](https://github.com/ezzz/HFRnow/pull/35), after the issues were created): open one, then remove this table.

| State | Wanted by | Note |
|---|---|---|
| Home page (`/`) answered to a logged-in session with expired cookies: logged-out home or `.hop` page? | LOT-047 | the poll reads both as nil (no information, never proof of expiry); the capture identifies the response shape |
