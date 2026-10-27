# Migration lots

The **single tracker** of the migration: scope, module, dependencies, model routing, owner and status of every lot. Rules: [AGENTS.md §5](../AGENTS.md#5-the-migration-loop-one-lot).
Until Issues are enabled on ezzz/HFRnow ([ADR 0010](adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md)), this file is the only place where work is claimed and tracked. The issues of `francoisgn/ios-app_SwiftHFR` (the mirror) are **frozen history**: each open lot links its old issue ("old #N") for context only; never claim, comment on or close them.
Lots come from the [Phase 1 audit](audit/README.md); the "Audit" column maps each lot to the audit proposals it merges.

- **Claim** a lot by setting yourself as owner (`<host>/<name> (date)`) and status `in-progress` in a PR on `dev-swift`, merged **before** writing code (or, for an orchestrator, its claim PR for the lots it hands out). The PR that does the work says `LOT-XXX` (a partial PR says what is left).
- **Statuses**: `todo` (dependencies done, inputs available) · `blocked` · `in-progress` · `review` · `done (#PR)` · `dropped`. Statuses of open lots were taken from their old issues on 2026-10-27. The PR that finishes a lot sets its own row to `done (#PR)`; nothing else in this file changes during a lot. Lots finished on the old repository keep their historical owner and a bare `done` or `done (#PR)` (old PR numbers, `francoisgn/ios-app_SwiftHFR`).
- **New lot**: a PR that adds its row (owner `—`, status `todo` or `blocked`) and its spec stub.
- **Target process** (once ezzz enables Issues, ADR 0010 "Later, owner's decision"): one issue per lot, claimed with `/claim <session-id>`, PRs checked by **Issue and claim** ([ORCHESTRATION](agents/ORCHESTRATION.md#target-process-once-ezzz-enables-issues)); this file then goes back to being the plan.

Model column: author → reviewer ([AGENTS.md §6](../AGENTS.md#6-model-routing-which-agent-does-what)).
**Fixtures-free** lots (✱) can start before Phase 2; a lot that lists fixtures in its spec still cannot *close* without them.
**Critical path** (★): LOT-001 → 002 → 022 → 023 → 038 → 052 (longest chain). Highest-risk chain for reading topics: 003 → 030 → 034.

## Phase 1 — audit

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-000 | Audit the legacy engine, split into lots | docs | difficult | Opus → Fable | — | all | — | cloud/opus (2026-10-24) | done |

## Phase 2 — fixtures and oracle

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-001 ★ | Prerequisite: legacy app builds and runs on the Mac (Carthage, Xcode). Fixture capture kit + anonymizer that decodes obfuscated quote/edit/crypt-link payloads, redacts, re-encodes (test: no decoded fixture contains `hash_check=` or a real pseudo). One merged capture checklist in `docs/FIXTURES.md`, including the open points of HFR-PROTOCOL §7 and research/redface2-comparison §4.4 | tooling | medium | Sonnet → Fable | — | B6, C8, D9, review F7/F8 | — | mac/opus M1 (2026-10-26) | done (#42) |
| LOT-002 ★ | Oracle exporter: legacy list parsers → JSON | tooling (legacy app) | medium | Sonnet → Fable | 001 | B10 | — | mac/opus M1 (2026-10-26) | done (#37) |
| LOT-003 | Oracle exporter: legacy topic-page parsing (`LinkItem`, page metadata, actions, `toHTML`) → JSON | tooling (legacy app) | medium | Opus → Fable | 001 | C00 | — | mac/opus M1 (2026-10-26) | done (#39) |
| LOT-004 | Oracle exporter: forms, write responses, storage formats (synthetic keychain blob, plists, MPStorage JSON) | tooling (legacy app) | medium | Sonnet → Fable | 001 | D9, E fixtures | — | mac/opus M1 (2026-10-26) | done (#40) |
| LOT-005 | Oracle exporter: small parsers (search redirect, `editprofil` hash/avatar, smiley search, smiley wiki, poll, public profile) → JSON | tooling (legacy app) | medium | Sonnet → Fable | 001 | B8, C07, D9, review F4 | — | mac/opus M1 (2026-10-26) | done (#57) |

## Phase 3 — engine

### Models (`HFRModels`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-010 ✱ | List models: forums, topics, flags, pagination, search hits, favourites sections | HFRModels | easy | Sonnet → Opus | — | B1 | — | cloud/c1-sonnet (2026-10-25) | done |
| LOT-011 ✱ | Topic page & message models, `MessageContent` (normalized HTML, signature, typed images/smileys/links/embeds — the LOT-034 output), `MessageActions`, poll | HFRModels | easy | Sonnet → Opus | — | C01 | — | cloud/c1-sonnet (2026-10-25) | done |
| LOT-012 ✱ | Form & write models (`ForumForm`, `HopResponse`, `RehostedImage`, AQ items), bundled smiley catalogue resource | HFRModels | easy | Sonnet → Opus | — | D1, D2, D10 | — | cloud/c1-sonnet (2026-10-25) | done |
| LOT-013 ✱ | Account, `StoredCookie` (Codable, never `HTTPCookie`), settings enums, MPStorage document types | HFRModels | easy | Sonnet → Opus | — | E-3, E-6 | — | cloud/c1-sonnet (2026-10-25) | done |
| LOT-014 ✱ | Forum catalogue: category id table, URL aliases | HFRModels | trivial | Haiku → Sonnet | 010 | B2 | — | cloud/c1b-haiku (2026-10-25) | done |

### Parsing (`HFRParsing`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-020 ✱ | Parsing core: selector helpers, HFR dates (Europe/Paris), URL helpers, obfuscated-URL decoder, integer extraction, typed errors | HFRParsing | medium | Opus → Fable | 010, 011 | B3, C02, D4 | — | cloud/c4-opus (2026-10-25) | done |
| LOT-021 | Forum list (home page) parser (returns all categories; hiding Apple for reviewers is app policy, Q-7) | HFRParsing | medium | Sonnet → Opus | 010, 020, 002 | B4 | — | cloud/c6-sonnet (2026-10-26) | done (#53) |
| LOT-022 ★ | Topic list parser (forums, MP, search results) — critical path | HFRParsing | difficult | Opus → Fable | 010, 020, 002 | B5 | — | cloud/c7-opus (2026-10-26) | done (#55) |
| LOT-023 ★ | MP list specifics + unread badge (one parser for the 3 legacy variants) | HFRParsing | easy | Sonnet → Opus | 022 | B6, NET-13 | medium | mac/w1-023-sonnet (2026-10-27) · old [#63](https://github.com/francoisgn/ios-app_SwiftHFR/issues/63) | in-progress |
| LOT-024 | Favourites page parser | HFRParsing | medium | Sonnet → Opus | 022 | B7 | high | mac/w1-024-sonnet (2026-10-27) · old [#64](https://github.com/francoisgn/ios-app_SwiftHFR/issues/64) | done (#20) |
| LOT-025 | Small parsers: search redirect, `editprofil` page (hash, avatar), smiley search results, AQ listing and AQ RSS feed | HFRParsing | easy | Sonnet → Opus | 020, 005 | B8, NET-04, NET-12, D6, D9 | — | cloud/c5-sonnet (2026-10-26) | done (#45; AQ part split to LOT-028) |
| LOT-026 | Poll parser (vote / results / closed) | HFRParsing | medium | Sonnet → Opus | 011, 020, 005 | B9, C07, D11 | — | cloud/c5-sonnet (2026-10-26) | done (#46; multi-choice and plain "already voted" pending capture) |
| LOT-027 | User profile page parser (`/hfr/profil-NNN.htm`: fields, avatar, personal smileys) | HFRParsing | medium | Sonnet → Opus | 010, 020, 005 | review F4 | — | cloud/c10-sonnet (2026-10-26) | done (#59) |
| LOT-028 | AQ listing and AQ RSS feed parsers (the AQ part of LOT-025), HTML entities decoded | HFRParsing | easy | Sonnet → Opus | 020, 012 | D6, B4 | low | — | blocked (AQ capture) |
| LOT-030 | Message block extraction — core of the topic page | HFRParsing | difficult | Fable → Opus | 011, 020, 003 | C03 | — | cloud/c8-fable (2026-10-26) | done (#54) |
| LOT-031 | Per-message action links (quote, edit, alert, profile, MP, flag, quoteJS) | HFRParsing | medium | Opus → Fable | 030 | C04 | medium | mac/w2-031-opus (2026-10-27) · old [#65](https://github.com/francoisgn/ios-app_SwiftHFR/issues/65) | done (#28) |
| LOT-032 | Quote analysis (authors, nesting) | HFRParsing | medium | Sonnet → Opus | 030 | C05 | medium | — · old [#66](https://github.com/francoisgn/ios-app_SwiftHFR/issues/66) | todo |
| LOT-033 | Topic page metadata (title, pagination, answer form, hidden fields) | HFRParsing | medium | Sonnet → Opus | 011, 020, 003 | C06 | — | cloud/c9-sonnet (2026-10-26) | done (#52) |
| LOT-034 | Content normalization (smileys, images, links, signature, code, spoilers) | HFRParsing | difficult | Fable → Opus | 030, ADR 0006 | C08 | high | mac/w1-034-fable (2026-10-27) · old [#67](https://github.com/francoisgn/ios-app_SwiftHFR/issues/67) | in-progress |
| LOT-035 | Video embed detection (fixes the YouTube hour bug) | HFRParsing | easy | Sonnet → Opus | 034 | C09 | low | — · old [#68](https://github.com/francoisgn/ios-app_SwiftHFR/issues/68) | blocked |
| LOT-036 | `hop` form parser (inputs, selects, `content_form` textarea incl. `[quotemsg]` prefill, entity decoding) | HFRParsing | medium | Sonnet → Opus | 012, 020, 004 | D1 | medium | mac/w1-036-sonnet (2026-10-27) · old [#69](https://github.com/francoisgn/ios-app_SwiftHFR/issues/69) | in-progress |
| LOT-037 | `hop` response classifier (success, rejected, logged out, already alerted) | HFRParsing | medium | Sonnet → Opus | 012, 004 | D2 | medium | mac/w1-037-sonnet (2026-10-27) · old [#70](https://github.com/francoisgn/ios-app_SwiftHFR/issues/70) | done (#18) |
| LOT-038 ★ | MPStorage page parsing (locate the storage MP, read its JSON) | HFRParsing | medium | Sonnet → Opus | 023, 030 | D8 | medium | — · old [#71](https://github.com/francoisgn/ios-app_SwiftHFR/issues/71) | blocked |

### Network (`HFRNetwork`) — transport, endpoints, sessions, raw fetchers

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-040 ✱ | Transport: protocol + URLSession + mock, form encoding (fixes accent bug), charset decoding, timeouts, typed errors incl. HTTP status | HFRNetwork | easy | Sonnet → Opus | — | NET-01, NET-14 | — | cloud/c2-sonnet (2026-10-25) | done |
| LOT-041 ✱ | Endpoint catalogue (typed URL builders) | HFRNetwork | easy | Sonnet → Opus | 040, 014 | NET-02 | — | cloud/c2b-sonnet (2026-10-25) | done |
| LOT-042 ✱ | Per-account session: isolated cookie jar, `hash_check` with `updateHashCheck(_:)`, multi-quote cookie (exact id match), `StoredCookie` import/export | HFRNetwork | medium | Opus → Fable | 040, 013 | NET-03, C16, D4 | — | cloud/c2c-opus (2026-10-25) | done |
| LOT-045 ✱ | Page fetchers: lists and topic page (final URL after redirects); cookie-less client for prefetch and images, since authenticated topic GETs mark flags read | HFRNetwork | easy | Sonnet → Opus | 041, 042 | NET-08, NET-09 | — | cloud/c2d-sonnet (2026-10-26) | done |
| LOT-056 | Image hosts: rehost client (key and base URL injected; legacy key reused for now, ADR 0007) + host adapter table (Referer for reho.st, keyless hosts, http-only hosts) | HFRNetwork | easy | Sonnet → Opus | 012 | D10 | medium | — · old [#84](https://github.com/francoisgn/ios-app_SwiftHFR/issues/84) | todo |

### Flows (`HFRClient`) — fetch → parse → submit → classify ([ADR 0008](adr/0008-hfrclient-orchestration-module.md))

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-043 | Login (validate before replacing cookies) | HFRClient | medium | Opus → Fable | 042, 025 | NET-04 | high | mac/w1-043-opus (2026-10-27) · old [#72](https://github.com/francoisgn/ios-app_SwiftHFR/issues/72) | done (#21) |
| LOT-044 | Session health & refresh (expiry detection, cookie merge) | HFRClient | medium | Opus → Fable | 042, 013 | NET-07 | medium | mac/w2-044-opus (2026-10-27) · old [#73](https://github.com/francoisgn/ios-app_SwiftHFR/issues/73) | in-progress |
| LOT-046 | Search: global (meta-refresh flow, banned-word list → refuse with a warning, Q-7) and intra-topic (no-redirect flow) | HFRClient | medium | Sonnet → Opus | 041, 025 | NET-10, NET-11 | medium | — · old [#74](https://github.com/francoisgn/ios-app_SwiftHFR/issues/74) | todo |
| LOT-047 | MP unread count poll (scheduling stays in the app) | HFRClient | easy | Sonnet → Opus | 023, 045 | NET-13 | medium | — · old [#75](https://github.com/francoisgn/ios-app_SwiftHFR/issues/75) | blocked |
| LOT-048 | Post-form engine: reply, edit, delete (incl. first post = whole topic), new topic, new MP, MP reply — posts as the **selected** account (Q-8); `verifrequet`, browser checkbox semantics, refuses non-BMP characters (Q-3), per-flow success markers, never reports success unless HFR confirmed it | HFRClient | difficult | Opus → Fable | 036, 037, 042 | D3 | medium | — · old [#76](https://github.com/francoisgn/ios-app_SwiftHFR/issues/76) | blocked |
| LOT-049 | Quote engine: quote template GET, `[quotemsg]` selection formatter | HFRClient | medium | Opus → Fable | 048, 031 | D4 | medium | — · old [#77](https://github.com/francoisgn/ios-app_SwiftHFR/issues/77) | blocked |
| LOT-050 | Moderator alert | HFRClient | easy | Sonnet → Opus | 036, 037 | D5 | medium | — · old [#78](https://github.com/francoisgn/ios-app_SwiftHFR/issues/78) | blocked |
| LOT-051 | Topic flags & favourites writes | HFRClient | medium | Opus → Fable | 037, 042 | D7 | medium | — · old [#79](https://github.com/francoisgn/ios-app_SwiftHFR/issues/79) | blocked |
| LOT-052 ★ | MPStorage transport (find, read, create, update; conflict-aware) | HFRClient | difficult | Opus → Fable | 038, 048, 062 | D8 | medium | — · old [#80](https://github.com/francoisgn/ios-app_SwiftHFR/issues/80) | blocked |
| LOT-053 | Smileys: search, wiki | HFRClient | easy | Sonnet → Opus | 025 | NET-12, D9 | low | — · old [#81](https://github.com/francoisgn/ios-app_SwiftHFR/issues/81) | todo |
| LOT-054 | Poll vote | HFRClient | medium | Sonnet → Opus | 026, 037 | D11 | medium | — · old [#82](https://github.com/francoisgn/ios-app_SwiftHFR/issues/82) | blocked |
| LOT-055 | AQ client: per-topic check, create, RSS feed + "new since" badge; returns every item with its category (hiding Apple for reviewers is app policy, Q-7) | HFRClient | easy | Sonnet → Opus | 028, 071 | D6 | low | — · old [#83](https://github.com/francoisgn/ios-app_SwiftHFR/issues/83) | blocked |
| LOT-057 | REST browsing client (`rest_api.php`: categories, topics, flag buckets) with HTML fallback | HFRClient | medium | Opus → Fable | 040, 041, 010, 021, 022, 024, 001 | redface2 E1 | medium | — · old [#85](https://github.com/francoisgn/ios-app_SwiftHFR/issues/85) | blocked |
| LOT-058 | MP actions: mark unread, group MP members, MP quote | HFRClient | easy | Sonnet → Opus | 042, 045, 036 | redface2 E6, E8, E9 | low | — · old [#86](https://github.com/francoisgn/ios-app_SwiftHFR/issues/86) | blocked |

### Storage (`HFRStorage`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-060 ✱ | Settings catalogue & store (legacy key names kept) | HFRStorage | easy | Sonnet → Opus | 013 | E-1 | — | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-061 ✱ | Blacklist / whitelist store (never overwrite with empty) | HFRStorage | medium | Sonnet → Opus | 013 | E-2 | — | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-062 ✱ | MPStorage document codec & merge (incl. `mpFlags` for MP list decoration) — pure value logic, usable by `HFRClient` | HFRModels | medium | Opus → Fable | 013 | E-3 | — | cloud/c3b-opus (2026-10-26) | done |
| LOT-063 ✱ | Drafts per context | HFRStorage | easy | Sonnet → Opus | 013 | E-4, D12 | — | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-064 | Small stores: super-favourites, favourites layout, smiley favourites, histories | HFRStorage | medium | Sonnet → Opus | 013, 004 | E-5 | medium | — · old [#87](https://github.com/francoisgn/ios-app_SwiftHFR/issues/87) | todo |
| LOT-065 ✱ | Account & credential store: protocol + in-memory/file (Linux) + Keychain under `#if canImport(Security)`, versioned envelope | HFRStorage | difficult | Opus → Fable | 013 | E-6, NET-05 | — | cloud/c3b-opus (2026-10-26) | done |
| LOT-066 ✱ | Caches: avatars, temporary files, eviction | HFRStorage | easy | Sonnet → Opus | — | E-8, C17 | — | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-067 | Legacy data import on update (accounts, lists, settings, drafts, smiley favourites, layout), idempotent, never deletes the source; also removes the legacy app caches on first launch (e.g. `Caches/cache/topic-*.htm`) | HFRStorage | difficult | Opus → Fable | 060, 061, 064, 065, 004 | E-7, NET-06 | medium | — · old [#88](https://github.com/francoisgn/ios-app_SwiftHFR/issues/88) | blocked |
| LOT-068 | Offline reading: save topics/pages for reading without network, list and evict them (Q-5) | HFRStorage | medium | Sonnet → Opus | 011, 066 | E-8, `OfflineStorage.m` | medium | — · old [#89](https://github.com/francoisgn/ios-app_SwiftHFR/issues/89) | todo |

### Gates

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-071 | Third-party services: inventory (image rehost, AQ, Giphy…), data sent, owner, first-use notices, configuration (Q-4, ADR 0007) | docs | easy | Opus → Fable | — | review Q-4 | medium | mac/w2-071-opus (2026-10-27) · old [#91](https://github.com/francoisgn/ios-app_SwiftHFR/issues/91) | done (#27) |
| LOT-072 | Shared pseudo normaliser (ZWSP and format characters, case rules) used by blocklist, drafts and accounts; removes the three private copies | HFRStorage | easy | Sonnet → Opus | 061, 063, 065 | reviews of #30, #31, #34 | low | — · old [#92](https://github.com/francoisgn/ios-app_SwiftHFR/issues/92) | todo |
| LOT-073 | MPStorage JSON tokenizer that preserves number lexemes natively, replacing the private-use marker workaround of LOT-062 | HFRModels | medium | Opus → Fable | 062 | review of #33 | low | — · old [#93](https://github.com/francoisgn/ios-app_SwiftHFR/issues/93) | todo |
| LOT-070 | Parity gates: differential roll-up, persistence parity checklist, write chapter of HFR-PROTOCOL | docs/tests | medium | Opus → Fable | all parsing/network/storage lots | C18, E-9, D13 | medium | — · old [#90](https://github.com/francoisgn/ios-app_SwiftHFR/issues/90) | blocked |

## Phase 4 — app: first usable build

**First usable build** = LOT-080 to LOT-083 and their dependencies: log in, browse forums, topics and flags, read a topic (read-only).
Posting comes next (LOT-036, 037, 048, 031, 049). The app module is `App` (the Xcode target); it may use every `HFRKit` module.

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Priority | Owner | Status |
|---|---|---|---|---|---|---|---|---|---|
| LOT-080 | iOS app target: Xcode 27 project in `App/` (iOS 27), local package `HFRKit` linked, simulator and device build, app build job in CI, ADR on the project-file strategy | App | medium | Opus → Fable | — | ROADMAP Phase 4 | high | mac/w1-080-opus (2026-10-27) · old [#94](https://github.com/francoisgn/ios-app_SwiftHFR/issues/94) | in-progress |
| LOT-081 | Accounts and login screen: add, select and remove an account, login through `HFRClient`, credentials in the account store, session restored at launch, typed errors shown | App | medium | Opus → Fable | 080, 043, 065 | E-6, NET-04 | high | — · old [#95](https://github.com/francoisgn/ios-app_SwiftHFR/issues/95) | blocked |
| LOT-082 | Adaptive navigation: one `NavigationSplitView` app (iPhone, iPad, foldables) forums → topics → messages; forum list, topic list with pagination, flags/favourites; hiding the Apple category for reviewers is applied here (Q-7) | App | medium | Sonnet → Opus | 080, 021, 022, 024, 045 | B1-B7 | high | — · old [#96](https://github.com/francoisgn/ios-app_SwiftHFR/issues/96) | blocked |
| LOT-083 | Topic reader: page shell and resources, message HTML builder from the normalized `MessageContent` (ADR 0006), WebView without remote scripts, page navigation, images through the cookie-less client; image loading policy C (operator 2026-10-27, recorded by LOT-071): no private/LAN hosts, no non-image `*.hardware.fr` paths, third-party images on tap or per the image setting | App | difficult | Opus → Fable | 080, 030, 033, 034, 045, 071 | C12, C13 | high | — · old [#97](https://github.com/francoisgn/ios-app_SwiftHFR/issues/97) | blocked |

## Phase 4 backlog — app side (not engine)

Pure Swift but app-side, kept here so nothing is lost: visibility policy (BL/WL/filters, C10) · filtered-posts use case (C11, candidate for `HFRClient`) · message HTML builder (C12) · page shell & resources (C13) · typed JS bridge (C14) · message action policy (C15) · image/GIF decoding (E-8) · background MP check scheduling (NET-13) · Giphy (E-10) · MP list decoration with `mpFlags` · account deletion mail and other hard-coded addresses (Q-10) · static pages, alternate icons, haptics, tab-bar settings UI · App Review policy: hide the Apple category (cat 25) when logged out or for the configured review account (Q-7) · inbound link router (forum links open the app) · Dynamic Type everywhere · iPad multi-window and favourites side panel · "posts quoting me" view (`quote_only=1`) · reply "+" carries selected quotes, classic post layout option (user feedback, docs/research/user-feedback-p450-510.md).

## Wave plan (orchestrator)

Orchestrator: `mac/orch-opus` (2026-10-27), operator brief of 2026-10-27. **MVP** = the first usable build (LOT-080 to 083 and their engine dependencies) plus login/session (LOT-043, 044) and posting basics (LOT-036, 037, 048). App lots (Track D: 080 → 081, 082, 083) run on the Mac session only; the cloud keeps their dependencies moving.

| Wave | Lot | Track | Author → reviewer | Why now |
|---|---|---|---|---|
| 1 | LOT-043 login | E | Opus → Fable | unblocks LOT-081 |
| 1 | LOT-024 favourites parser | E | Sonnet → Opus | unblocks LOT-082 |
| 1 | LOT-034 content normalization | C | Fable → Opus | unblocks LOT-083, 035 |
| 1 | LOT-023 MP list ★ | B | Sonnet → Opus | critical path → 038, 047 |
| 1 | LOT-036 `hop` form parser | A | Sonnet → Opus | → 048 |
| 1 | LOT-037 `hop` response classifier | A | Sonnet → Opus | → 048, 050, 051, 054 |
| 1 | LOT-080 iOS app target (Mac) | D | Opus → Fable | operator request: critical path of the MVP (→ 081, 082, 083) |
| 2 | LOT-044 session health & refresh | E | Opus → Fable | MVP login/session basics |
| 2 | LOT-031 per-message actions | C | Opus → Fable | → 049 quote engine; message actions for the reader |
| 2 | LOT-071 third-party services inventory | E | Opus → Fable | → 055, 083: records the third-party loading policy (operator decision 2026-10-27: option C) |
| 3 (planned) | LOT-048 (after 036), 038 and 047 (after 023), 032, 056, 064 | A–E | per row | when their dependencies are done |

## Other work

Work that is not a lot, listed so nothing lives only in a session's memory. Claim an entry like a lot: a PR that puts your id and `in-progress` in its Owner and Status cells.

| Work | Source | Owner | Status |
|---|---|---|---|
| Pre-commit config (syntax, lint, secrets; pinned versions) and a CI job replaying `pre-commit run --all-files` | old [#14](https://github.com/francoisgn/ios-app_SwiftHFR/issues/14) | — | todo |
| App feature backlog FEAT-001…021: each feature gets its spec `docs/features/FEAT-XXX.md`, then engine lots here and app PRs ([ADR 0011](adr/0011-contribution-model-and-feature-intake.md) §2) | [FEATURES.md](FEATURES.md) | — | todo |
| Cutover follow-ups: ADR 0010 → Accepted and learnings in AGENTS.md §11, once ezzz has done the owner actions of [EZZZ-CUTOVER](migration/EZZZ-CUTOVER.md) step 9; then delete the runbook | [ADR 0010](adr/0010-hosting-on-ezzz-hfrnow-dev-swift.md) | — | blocked (ezzz, step 9) |

## Capture backlog (Mac)

Page states that merged lots listed as **pending capture** (never hand-built in the cloud, LESSONS 36), copied from the frozen old issue [#98](https://github.com/francoisgn/ios-app_SwiftHFR/issues/98). Each needs a live capture on the Mac with the LOT-001 kit (`tooling/fixtures/`), anonymized, plus a legacy oracle when a parser consumes it (LOT-002..005 tooling). Owner: — · status: ready · `host: mac`. Claim it like a lot (owner here); one PR per batch of captures; a captured state is removed from this table by its PR.

| State | Wanted by | Note |
|---|---|---|
| Favourites: logged-in `forum1f.php?owntopic=1` with no flagged topic; two or more categories; a row without flag link, a single-page topic, sticky / closed / poll rows | LOT-024 | R10 has one category with two topics (MANIFEST says two); the empty `owntopic=1` page decides what HFRClient may assume from a `.hop` |
| Maintenance page (home, lists) | LOT-021, LOT-022 | cannot be provoked; capture when HFR shows one |
| Poll: multi-choice | LOT-026 | find a topic with a multi-choice poll |
| Poll: plain "already voted" without the multipseudo notice | LOT-026 | needs a vote (P05 out of scope) → only if the operator agrees |
| `div.sondageFooter` | LOT-026 | |
| Topic list: MP list logged out, cross-category search results, rare row shapes | LOT-022 | see the LOT-022 spec |
| Locked topic seen logged in; favourite/flagged topic page; checked in-topic search filter (R52a was a 302) | LOT-033 | |
| Deleted message wrapper `messagetabledel`; in-topic search prefix link | LOT-030 | |
| Profile: logged in, banned/deleted member, real birth date and signature, status other than "Membre", smiley file name with apostrophe/space, non-jpg avatar | LOT-027 | anonymize every free-text field |
| Home row without `id="cat<N>"`; full sub-forum lists | LOT-021 | REST R57a counts 27 sub-forums for Programmation, page + table give 14 |
| Topic page with `quote_only=1` (LOT-001 checklist R34, dropped as optional): is there any server signal that someone quoted me? | FEAT-018, HFR-PROTOCOL §7b B11 | read-only GET; settles feasibility before FEAT-018 is promised |
| Site `apple-app-site-association` (AASA): which App IDs and paths it names | FEAT-020, Q-1 | reported live 2026-10-26 to name `QMG83DG7YP.hfrplus.red.super` (old format), not captured; plain GET, no account |
| AQ listing (`getAlertesByTopic`) and AQ RSS feed, with HTML entities in titles, authors and comments | LOT-028, LOT-055, issue to open #4 | third-party host `aq.super-h.fr` (LOT-001 checklist row P08, skipped while Q-4 was open); Q-4 is decided (keep, first-use notice), so capture it now, plus a legacy oracle for the parser |
| `reho.st` image fetched cookie-less with and without `Referer: https://forum.hardware.fr/`; one `http://`-only image host of `R20`/`R21`/`R22a` requested over `https` | LOT-056, LOT-071, LOT-083 | settles HFR-PROTOCOL §7 E26 and the `http`-only hosts of the LOT-071 decision D-071-1; plain GETs, no account, no upload |
| Moderator alert: page of an already-reported message (text, is it `.hop` + link/input?) | LOT-037, LOT-050 | `modo.php` GET on a message the account already reported; `alreadyAlerted` rests on the legacy rule alone |
| Moderator alert: submit success (text, refresh, "avec succès"?) | LOT-037, LOT-050 | until captured, an alert write cannot be classified `success` |
| Other logged-out write answers (flag GET, alert, vote) and login-form pages | LOT-037 | `loggedOut` matches only the W17c sentence |
| Poll vote answer; other refusal sentences (locked topic, ban) | LOT-037, LOT-054 | classified `rejected` by shape only |
| Login refused for flood or lockout (several wrong passwords in a row) | LOT-043 | its text is unknown (HFR-PROTOCOL §7 "Login"); today reported as `unrecognizedResponse`. Use a throwaway account: it may lock it |
| Login with the pseudo typed in another case, and with a pseudo holding a space or an accent: the `md_user` value set | LOT-043 | settles whether `md_user` keeps the typed case and how it is URL-encoded; `expectedUserKey` stays an exact comparison with the stored cookie value (`LoginResult.userKey`, LOT-043 spec) |
| `editprofil.php?config=hfr.inc&page=5` without a working session (logged out or expired cookies) | LOT-043 | settles what the login flow's page-5 check sees when the new cookies do not work (not captured; until then `LoginFlow` treats a page without a non-empty `hash_check` as `missingHashCheck`, see [LOT-043 spec](lots/LOT-043-login.md)) |
| Topic page logged in with one of the viewer's own posts on a **public** topic; a quote or edit link printed in clear (not `md_noclass_cryptlink`) | LOT-031 | every edit link of the corpus is in an MP thread; read-only GET of a page holding a post of the account |

## Issues to open (backlog until Issues are enabled on ezzz/HFRnow)

Real legacy bugs found by Bybifok (`moust4ki`) in [ezzz/HFRnow#3](https://github.com/ezzz/HFRnow/pull/3), to check and fix in SwiftHFR. Each becomes an issue titled `[SwiftHFR] …` with labels `type: bug`, `moust4ki aka bybifok finding`, its area, priority, difficulty and status, then this section is deleted. Until then they are tracked here like lots: claim one by a PR that adds your id and `in-progress` to its status cell.

| # | Issue | Legacy commit | Area · priority · difficulty · status | SwiftHFR work |
|---|---|---|---|---|
| 1 | Topic-list pager: a link without `href` must not break the parser | `237db70` | parsing · medium · easy · todo | Non-regression test in LOT-022 (and LOT-021, later 024/MP lists): skip the entry, keep the rows |
| 2 | Topic-list page N must really load page N (`liste_sujet` paging) | `a817498` | network · high · easy · todo | LOT-041 builder never yields `liste_sujet-1.htm?page=N`; capture to settle HFR-PROTOCOL §7b B2 |
| 3 | Topic lists must not show a fake total page count | `dc93420` | parsing · high · medium · todo | LOT-022 `PageNavigation`: windowed pager = lower bound, not total (HFR-PROTOCOL §7b B1) |
| 4 | AQ RSS: decode HTML entities in titles, authors and comments | `a817498` | parsing · low · easy · blocked (AQ capture) | Test in LOT-028; the AQ capture (Capture backlog) settles HFR-PROTOCOL §7b B4 |
| 5 | Links to a post (AQ, bookmarks) must open its page and anchor, not page 1 | `246a9c7` | app · medium · easy · todo | Page and `#t<numreponse>` kept through LOT-020, 045, 083; tests on both URL shapes |
| 6 | Refresh must reload the current page, not page 1 | `246a9c7` | app · medium · easy · blocked (LOT-082/083) | Acceptance criteria of LOT-082/083: current page, content kept while loading, kept on failure |
| 7 | Topic loading: a cancelled request must never complete the next load | `be196f8` | app · medium · medium · blocked (LOT-083) | One task per load, cancelled one cannot deliver; show at `DOMContentLoaded`; test with a fake page driver |
