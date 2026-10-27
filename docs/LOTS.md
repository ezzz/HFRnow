# Migration lots

The **plan** of the migration: scope, module, dependencies and model routing of every lot. Rules: [AGENTS.md §5](../AGENTS.md#5-the-migration-loop-one-lot).
**Live state lives in GitHub issues**, one per open lot (label `type: lot`): claim, progress, blockers and discussion happen there. This file only links each lot to its issue and records the closing PR. Lots finished before the move to issues (2026-10-27) keep their historical owner and a bare `done`.
Lots come from the [Phase 1 audit](audit/README.md); the "Audit" column maps each lot to the audit proposals it merges.

- **Claim** a lot by commenting `/claim <session-id>` on its issue before writing code; the PR that completes it says `Closes #N` (a partial PR says `Refs #N` and what is left) and `Claim: <session-id>`, and CI checks both ([AGENTS.md §8](../AGENTS.md#8-git-and-pr-workflow)).
- **Status** column: `open` (see the issue) or `done (#PR)`. The PR that closes a lot sets its own row to `done (#PR)`; nothing else in this file changes during a lot.
- **New lot**: open its issue first (issue form "Task", type `lot`, starting with a Summary) and claim it; the PR that adds the row here links that issue.

Model column: author → reviewer ([AGENTS.md §6](../AGENTS.md#6-model-routing-which-agent-does-what)).
**Fixtures-free** lots (✱) can start before Phase 2; a lot that lists fixtures in its spec still cannot *close* without them.
**Critical path** (★): LOT-001 → 002 → 022 → 023 → 038 → 052 (longest chain). Highest-risk chain for reading topics: 003 → 030 → 034.

## Phase 1 — audit

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-000 | Audit the legacy engine, split into lots | docs | difficult | Opus → Fable | — | all | cloud/opus (2026-10-24) | done |

## Phase 2 — fixtures and oracle

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-001 ★ | Prerequisite: legacy app builds and runs on the Mac (Carthage, Xcode). Fixture capture kit + anonymizer that decodes obfuscated quote/edit/crypt-link payloads, redacts, re-encodes (test: no decoded fixture contains `hash_check=` or a real pseudo). One merged capture checklist in `docs/FIXTURES.md`, including the open points of HFR-PROTOCOL §7 and research/redface2-comparison §4.4 | tooling | medium | Sonnet → Fable | — | B6, C8, D9, review F7/F8 | mac/opus M1 (2026-10-26) | done (#42) |
| LOT-002 ★ | Oracle exporter: legacy list parsers → JSON | tooling (legacy app) | medium | Sonnet → Fable | 001 | B10 | mac/opus M1 (2026-10-26) | done (#37) |
| LOT-003 | Oracle exporter: legacy topic-page parsing (`LinkItem`, page metadata, actions, `toHTML`) → JSON | tooling (legacy app) | medium | Opus → Fable | 001 | C00 | mac/opus M1 (2026-10-26) | done (#39) |
| LOT-004 | Oracle exporter: forms, write responses, storage formats (synthetic keychain blob, plists, MPStorage JSON) | tooling (legacy app) | medium | Sonnet → Fable | 001 | D9, E fixtures | mac/opus M1 (2026-10-26) | done (#40) |
| LOT-005 | Oracle exporter: small parsers (search redirect, `editprofil` hash/avatar, smiley search, smiley wiki, poll, public profile) → JSON | tooling (legacy app) | medium | Sonnet → Fable | 001 | B8, C07, D9, review F4 | mac/opus M1 (2026-10-26) | done (#57) |

## Phase 3 — engine

### Models (`HFRModels`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-010 ✱ | List models: forums, topics, flags, pagination, search hits, favourites sections | HFRModels | easy | Sonnet → Opus | — | B1 | cloud/c1-sonnet (2026-10-25) | done |
| LOT-011 ✱ | Topic page & message models, `MessageContent` (normalized HTML, signature, typed images/smileys/links/embeds — the LOT-034 output), `MessageActions`, poll | HFRModels | easy | Sonnet → Opus | — | C01 | cloud/c1-sonnet (2026-10-25) | done |
| LOT-012 ✱ | Form & write models (`ForumForm`, `HopResponse`, `RehostedImage`, AQ items), bundled smiley catalogue resource | HFRModels | easy | Sonnet → Opus | — | D1, D2, D10 | cloud/c1-sonnet (2026-10-25) | done |
| LOT-013 ✱ | Account, `StoredCookie` (Codable, never `HTTPCookie`), settings enums, MPStorage document types | HFRModels | easy | Sonnet → Opus | — | E-3, E-6 | cloud/c1-sonnet (2026-10-25) | done |
| LOT-014 ✱ | Forum catalogue: category id table, URL aliases | HFRModels | trivial | Haiku → Sonnet | 010 | B2 | cloud/c1b-haiku (2026-10-25) | done |

### Parsing (`HFRParsing`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-020 ✱ | Parsing core: selector helpers, HFR dates (Europe/Paris), URL helpers, obfuscated-URL decoder, integer extraction, typed errors | HFRParsing | medium | Opus → Fable | 010, 011 | B3, C02, D4 | cloud/c4-opus (2026-10-25) | done |
| LOT-021 | Forum list (home page) parser (returns all categories; hiding Apple for reviewers is app policy, Q-7) | HFRParsing | medium | Sonnet → Opus | 010, 020, 002 | B4 | cloud/c6-sonnet (2026-10-26) | done (#53) |
| LOT-022 ★ | Topic list parser (forums, MP, search results) — critical path | HFRParsing | difficult | Opus → Fable | 010, 020, 002 | B5 | cloud/c7-opus (2026-10-26) | done (#55) |
| LOT-023 ★ | MP list specifics + unread badge (one parser for the 3 legacy variants) | HFRParsing | easy | Sonnet → Opus | 022 | B6, NET-13 | [#63](https://github.com/francoisgn/ios-app_SwiftHFR/issues/63) | open |
| LOT-024 | Favourites page parser | HFRParsing | medium | Sonnet → Opus | 022 | B7 | [#64](https://github.com/francoisgn/ios-app_SwiftHFR/issues/64) | open |
| LOT-025 | Small parsers: search redirect, `editprofil` page (hash, avatar), smiley search results, AQ listing and AQ RSS feed | HFRParsing | easy | Sonnet → Opus | 020, 005 | B8, NET-04, NET-12, D6, D9 | cloud/c5-sonnet (2026-10-26) | done (#45; AQ part pending Q-4, see LOT-055) |
| LOT-026 | Poll parser (vote / results / closed) | HFRParsing | medium | Sonnet → Opus | 011, 020, 005 | B9, C07, D11 | cloud/c5-sonnet (2026-10-26) | done (#46; multi-choice and plain "already voted" pending capture) |
| LOT-027 | User profile page parser (`/hfr/profil-NNN.htm`: fields, avatar, personal smileys) | HFRParsing | medium | Sonnet → Opus | 010, 020, 005 | review F4 | cloud/c10-sonnet (2026-10-26) | done (#59) |
| LOT-030 | Message block extraction — core of the topic page | HFRParsing | difficult | Fable → Opus | 011, 020, 003 | C03 | cloud/c8-fable (2026-10-26) | done (#54) |
| LOT-031 | Per-message action links (quote, edit, alert, profile, MP, flag, quoteJS) | HFRParsing | medium | Opus → Fable | 030 | C04 | [#65](https://github.com/francoisgn/ios-app_SwiftHFR/issues/65) | open |
| LOT-032 | Quote analysis (authors, nesting) | HFRParsing | medium | Sonnet → Opus | 030 | C05 | [#66](https://github.com/francoisgn/ios-app_SwiftHFR/issues/66) | open |
| LOT-033 | Topic page metadata (title, pagination, answer form, hidden fields) | HFRParsing | medium | Sonnet → Opus | 011, 020, 003 | C06 | cloud/c9-sonnet (2026-10-26) | done (#52) |
| LOT-034 | Content normalization (smileys, images, links, signature, code, spoilers) | HFRParsing | difficult | Fable → Opus | 030, ADR 0006 | C08 | [#67](https://github.com/francoisgn/ios-app_SwiftHFR/issues/67) | open |
| LOT-035 | Video embed detection (fixes the YouTube hour bug) | HFRParsing | easy | Sonnet → Opus | 034 | C09 | [#68](https://github.com/francoisgn/ios-app_SwiftHFR/issues/68) | open |
| LOT-036 | `hop` form parser (inputs, selects, `content_form` textarea incl. `[quotemsg]` prefill, entity decoding) | HFRParsing | medium | Sonnet → Opus | 012, 020, 004 | D1 | [#69](https://github.com/francoisgn/ios-app_SwiftHFR/issues/69) | open |
| LOT-037 | `hop` response classifier (success, rejected, logged out, already alerted) | HFRParsing | medium | Sonnet → Opus | 012, 004 | D2 | [#70](https://github.com/francoisgn/ios-app_SwiftHFR/issues/70) | open |
| LOT-038 ★ | MPStorage page parsing (locate the storage MP, read its JSON) | HFRParsing | medium | Sonnet → Opus | 023, 030 | D8 | [#71](https://github.com/francoisgn/ios-app_SwiftHFR/issues/71) | open |

### Network (`HFRNetwork`) — transport, endpoints, sessions, raw fetchers

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-040 ✱ | Transport: protocol + URLSession + mock, form encoding (fixes accent bug), charset decoding, timeouts, typed errors incl. HTTP status | HFRNetwork | easy | Sonnet → Opus | — | NET-01, NET-14 | cloud/c2-sonnet (2026-10-25) | done |
| LOT-041 ✱ | Endpoint catalogue (typed URL builders) | HFRNetwork | easy | Sonnet → Opus | 040, 014 | NET-02 | cloud/c2b-sonnet (2026-10-25) | done |
| LOT-042 ✱ | Per-account session: isolated cookie jar, `hash_check` with `updateHashCheck(_:)`, multi-quote cookie (exact id match), `StoredCookie` import/export | HFRNetwork | medium | Opus → Fable | 040, 013 | NET-03, C16, D4 | cloud/c2c-opus (2026-10-25) | done |
| LOT-045 ✱ | Page fetchers: lists and topic page (final URL after redirects); cookie-less client for prefetch and images, since authenticated topic GETs mark flags read | HFRNetwork | easy | Sonnet → Opus | 041, 042 | NET-08, NET-09 | cloud/c2d-sonnet (2026-10-26) | done |
| LOT-056 | Image hosts: rehost client (key and base URL injected; legacy key reused for now, ADR 0007) + host adapter table (Referer for reho.st, keyless hosts, http-only hosts) | HFRNetwork | easy | Sonnet → Opus | 012 | D10 | [#84](https://github.com/francoisgn/ios-app_SwiftHFR/issues/84) | open |

### Flows (`HFRClient`) — fetch → parse → submit → classify ([ADR 0008](adr/0008-hfrclient-orchestration-module.md))

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-043 | Login (validate before replacing cookies) | HFRClient | medium | Opus → Fable | 042, 025 | NET-04 | [#72](https://github.com/francoisgn/ios-app_SwiftHFR/issues/72) | open |
| LOT-044 | Session health & refresh (expiry detection, cookie merge) | HFRClient | medium | Opus → Fable | 042, 013 | NET-07 | [#73](https://github.com/francoisgn/ios-app_SwiftHFR/issues/73) | open |
| LOT-046 | Search: global (meta-refresh flow, banned-word list → refuse with a warning, Q-7) and intra-topic (no-redirect flow) | HFRClient | medium | Sonnet → Opus | 041, 025 | NET-10, NET-11 | [#74](https://github.com/francoisgn/ios-app_SwiftHFR/issues/74) | open |
| LOT-047 | MP unread count poll (scheduling stays in the app) | HFRClient | easy | Sonnet → Opus | 023, 045 | NET-13 | [#75](https://github.com/francoisgn/ios-app_SwiftHFR/issues/75) | open |
| LOT-048 | Post-form engine: reply, edit, delete (incl. first post = whole topic), new topic, new MP, MP reply — posts as the **selected** account (Q-8); `verifrequet`, browser checkbox semantics, refuses non-BMP characters (Q-3), per-flow success markers, never reports success unless HFR confirmed it | HFRClient | difficult | Opus → Fable | 036, 037, 042 | D3 | [#76](https://github.com/francoisgn/ios-app_SwiftHFR/issues/76) | open |
| LOT-049 | Quote engine: quote template GET, `[quotemsg]` selection formatter | HFRClient | medium | Opus → Fable | 048, 031 | D4 | [#77](https://github.com/francoisgn/ios-app_SwiftHFR/issues/77) | open |
| LOT-050 | Moderator alert | HFRClient | easy | Sonnet → Opus | 036, 037 | D5 | [#78](https://github.com/francoisgn/ios-app_SwiftHFR/issues/78) | open |
| LOT-051 | Topic flags & favourites writes | HFRClient | medium | Opus → Fable | 037, 042 | D7 | [#79](https://github.com/francoisgn/ios-app_SwiftHFR/issues/79) | open |
| LOT-052 ★ | MPStorage transport (find, read, create, update; conflict-aware) | HFRClient | difficult | Opus → Fable | 038, 048, 062 | D8 | [#80](https://github.com/francoisgn/ios-app_SwiftHFR/issues/80) | open |
| LOT-053 | Smileys: search, wiki | HFRClient | easy | Sonnet → Opus | 025 | NET-12, D9 | [#81](https://github.com/francoisgn/ios-app_SwiftHFR/issues/81) | open |
| LOT-054 | Poll vote | HFRClient | medium | Sonnet → Opus | 026, 037 | D11 | [#82](https://github.com/francoisgn/ios-app_SwiftHFR/issues/82) | open |
| LOT-055 | AQ client: per-topic check, create, RSS feed + "new since" badge; returns every item with its category (hiding Apple for reviewers is app policy, Q-7) | HFRClient | easy | Sonnet → Opus | 025, Q-4 | D6 | [#83](https://github.com/francoisgn/ios-app_SwiftHFR/issues/83) | open |
| LOT-057 | REST browsing client (`rest_api.php`: categories, topics, flag buckets) with HTML fallback | HFRClient | medium | Opus → Fable | 040, 041, 010, 021, 022, 024, 001 | redface2 E1 | [#85](https://github.com/francoisgn/ios-app_SwiftHFR/issues/85) | open |
| LOT-058 | MP actions: mark unread, group MP members, MP quote | HFRClient | easy | Sonnet → Opus | 042, 045, 036 | redface2 E6, E8, E9 | [#86](https://github.com/francoisgn/ios-app_SwiftHFR/issues/86) | open |

### Storage (`HFRStorage`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-060 ✱ | Settings catalogue & store (legacy key names kept) | HFRStorage | easy | Sonnet → Opus | 013 | E-1 | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-061 ✱ | Blacklist / whitelist store (never overwrite with empty) | HFRStorage | medium | Sonnet → Opus | 013 | E-2 | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-062 ✱ | MPStorage document codec & merge (incl. `mpFlags` for MP list decoration) — pure value logic, usable by `HFRClient` | HFRModels | medium | Opus → Fable | 013 | E-3 | cloud/c3b-opus (2026-10-26) | done |
| LOT-063 ✱ | Drafts per context | HFRStorage | easy | Sonnet → Opus | 013 | E-4, D12 | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-064 | Small stores: super-favourites, favourites layout, smiley favourites, histories | HFRStorage | medium | Sonnet → Opus | 013, 004 | E-5 | [#87](https://github.com/francoisgn/ios-app_SwiftHFR/issues/87) | open |
| LOT-065 ✱ | Account & credential store: protocol + in-memory/file (Linux) + Keychain under `#if canImport(Security)`, versioned envelope | HFRStorage | difficult | Opus → Fable | 013 | E-6, NET-05 | cloud/c3b-opus (2026-10-26) | done |
| LOT-066 ✱ | Caches: avatars, temporary files, eviction | HFRStorage | easy | Sonnet → Opus | — | E-8, C17 | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-067 | Legacy data import on update (accounts, lists, settings, drafts, smiley favourites, layout), idempotent, never deletes the source; also removes the legacy app caches on first launch (e.g. `Caches/cache/topic-*.htm`) | HFRStorage | difficult | Opus → Fable | 060, 061, 064, 065, 004, Q-1 | E-7, NET-06 | [#88](https://github.com/francoisgn/ios-app_SwiftHFR/issues/88) | open |
| LOT-068 | Offline reading: save topics/pages for reading without network, list and evict them (Q-5) | HFRStorage | medium | Sonnet → Opus | 011, 066 | E-8, `OfflineStorage.m` | [#89](https://github.com/francoisgn/ios-app_SwiftHFR/issues/89) | open |

### Gates

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-071 | Third-party services: inventory (image rehost, AQ, Giphy…), data sent, owner, first-use notices, configuration (Q-4, ADR 0007) | docs | easy | Opus → Fable | — | review Q-4 | [#91](https://github.com/francoisgn/ios-app_SwiftHFR/issues/91) | open |
| LOT-072 | Shared pseudo normaliser (ZWSP and format characters, case rules) used by blocklist, drafts and accounts; removes the three private copies | HFRStorage | easy | Sonnet → Opus | 061, 063, 065 | reviews of #30, #31, #34 | [#92](https://github.com/francoisgn/ios-app_SwiftHFR/issues/92) | open |
| LOT-073 | MPStorage JSON tokenizer that preserves number lexemes natively, replacing the private-use marker workaround of LOT-062 | HFRModels | medium | Opus → Fable | 062 | review of #33 | [#93](https://github.com/francoisgn/ios-app_SwiftHFR/issues/93) | open |
| LOT-070 | Parity gates: differential roll-up, persistence parity checklist, write chapter of HFR-PROTOCOL | docs/tests | medium | Opus → Fable | all parsing/network/storage lots | C18, E-9, D13 | [#90](https://github.com/francoisgn/ios-app_SwiftHFR/issues/90) | open |

## Phase 4 — app: first usable build

**First usable build** = LOT-080 to LOT-083 and their dependencies: log in, browse forums, topics and flags, read a topic (read-only).
Posting comes next (LOT-036, 037, 048, 031, 049). The app module is `App` (the Xcode target); it may use every `HFRKit` module.

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Issue / owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-080 | iOS app target: Xcode 27 project in `App/` (iOS 27), local package `HFRKit` linked, simulator and device build, app build job in CI, ADR on the project-file strategy | App | medium | Opus → Fable | — | ROADMAP Phase 4 | [#94](https://github.com/francoisgn/ios-app_SwiftHFR/issues/94) | open |
| LOT-081 | Accounts and login screen: add, select and remove an account, login through `HFRClient`, credentials in the account store, session restored at launch, typed errors shown | App | medium | Opus → Fable | 080, 043, 065 | E-6, NET-04 | [#95](https://github.com/francoisgn/ios-app_SwiftHFR/issues/95) | open |
| LOT-082 | Adaptive navigation: one `NavigationSplitView` app (iPhone, iPad, foldables) forums → topics → messages; forum list, topic list with pagination, flags/favourites; hiding the Apple category for reviewers is applied here (Q-7) | App | medium | Sonnet → Opus | 080, 021, 022, 024, 045 | B1-B7 | [#96](https://github.com/francoisgn/ios-app_SwiftHFR/issues/96) | open |
| LOT-083 | Topic reader: page shell and resources, message HTML builder from the normalized `MessageContent` (ADR 0006), WebView without remote scripts, page navigation, images through the cookie-less client | App | difficult | Opus → Fable | 080, 030, 033, 034, 045 | C12, C13 | [#97](https://github.com/francoisgn/ios-app_SwiftHFR/issues/97) | open |

## Phase 4 backlog — app side (not engine)

Pure Swift but app-side, kept here so nothing is lost: visibility policy (BL/WL/filters, C10) · filtered-posts use case (C11, candidate for `HFRClient`) · message HTML builder (C12) · page shell & resources (C13) · typed JS bridge (C14) · message action policy (C15) · image/GIF decoding (E-8) · background MP check scheduling (NET-13) · Giphy (E-10) · MP list decoration with `mpFlags` · account deletion mail and other hard-coded addresses (Q-10) · static pages, alternate icons, haptics, tab-bar settings UI · App Review policy: hide the Apple category (cat 25) when logged out or for the configured review account (Q-7) · inbound link router (forum links open the app) · Dynamic Type everywhere · iPad multi-window and favourites side panel · "posts quoting me" view (`quote_only=1`) · reply "+" carries selected quotes, classic post layout option (user feedback, docs/research/user-feedback-p450-510.md).

## Issues to open (backlog until Issues are enabled on ezzz/HFRnow)

Real legacy bugs found by Bybifok (`moust4ki`) in [ezzz/HFRnow#3](https://github.com/ezzz/HFRnow/pull/3), to check and fix in SwiftHFR. Each becomes an issue titled `[SwiftHFR] …` with labels `type: bug`, `moust4ki aka bybifok finding`, its area, priority, difficulty and status, then this section is deleted.

| # | Issue | Legacy commit | Area · priority · difficulty · status | SwiftHFR work |
|---|---|---|---|---|
| 1 | Topic-list pager: a link without `href` must not break the parser | `237db70` | parsing · medium · easy · ready | Non-regression test in LOT-022 (and LOT-021, later 024/MP lists): skip the entry, keep the rows |
| 2 | Topic-list page N must really load page N (`liste_sujet` paging) | `a817498` | network · high · easy · ready | LOT-041 builder never yields `liste_sujet-1.htm?page=N`; capture to settle HFR-PROTOCOL §7b B2 |
| 3 | Topic lists must not show a fake total page count | `dc93420` | parsing · high · medium · ready | LOT-022 `PageNavigation`: windowed pager = lower bound, not total (HFR-PROTOCOL §7b B1) |
| 4 | AQ RSS: decode HTML entities in titles, authors and comments | `a817498` | parsing · low · easy · blocked (Q-4) | Test in the AQ part of LOT-025; capture to settle HFR-PROTOCOL §7b B4 |
| 5 | Links to a post (AQ, bookmarks) must open its page and anchor, not page 1 | `246a9c7` | app · medium · easy · ready | Page and `#t<numreponse>` kept through LOT-020, 045, 083; tests on both URL shapes |
| 6 | Refresh must reload the current page, not page 1 | `246a9c7` | app · medium · easy · blocked (LOT-082/083) | Acceptance criteria of LOT-082/083: current page, content kept while loading, kept on failure |
| 7 | Topic loading: a cancelled request must never complete the next load | `be196f8` | app · medium · medium · blocked (LOT-083) | One task per load, cancelled one cannot deliver; show at `DOMContentLoaded`; test with a fake page driver |
