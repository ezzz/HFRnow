# Migration lots

Single tracking table for the engine migration. Rules: [AGENTS.md §5](../AGENTS.md#5-the-migration-loop-one-lot).
Claim a lot by setting yourself as owner and status `in-progress`, committed and pushed **before** writing code — unless an orchestrator session is active: then only the orchestrator edits this file ([ORCHESTRATION](agents/ORCHESTRATION.md)).
Lots come from the [Phase 1 audit](audit/README.md); the "Audit" column maps each lot to the audit proposals it merges.

Statuses: `todo` · `in-progress` · `review` · `done` · `blocked` · `dropped`
Model column: author → reviewer ([AGENTS.md §6](../AGENTS.md#6-model-routing-which-agent-does-what)).
**Fixtures-free** lots (✱) can start before Phase 2; a lot that lists fixtures in its spec still cannot *close* without them.
**Critical path** (★): LOT-001 → 002 → 022 → 023 → 038 → 052 (longest chain). Highest-risk chain for reading topics: 003 → 030 → 034.

## Phase 1 — audit

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-000 | Audit the legacy engine, split into lots | docs | difficult | Opus → Fable | — | all | cloud/opus (2026-10-24) | done |

## Phase 2 — fixtures and oracle

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-001 ★ | Prerequisite: legacy app builds and runs on the Mac (Carthage, Xcode). Fixture capture kit + anonymizer that decodes obfuscated quote/edit/crypt-link payloads, redacts, re-encodes (test: no decoded fixture contains `hash_check=` or a real pseudo). One merged capture checklist in `docs/FIXTURES.md`, including the open points of HFR-PROTOCOL §7 and research/redface2-comparison §4.4 | tooling | medium | Sonnet → Fable | — | B6, C8, D9, review F7/F8 | mac/opus M1 (2026-10-26) | in-progress |
| LOT-002 ★ | Oracle exporter: legacy list parsers → JSON | tooling (legacy app) | medium | Sonnet → Fable | 001 | B10 | mac/opus M1 (2026-10-26) | in-progress |
| LOT-003 | Oracle exporter: legacy topic-page parsing (`LinkItem`, page metadata, actions, `toHTML`) → JSON | tooling (legacy app) | medium | Opus → Fable | 001 | C00 | mac/opus M1 (2026-10-26) | in-progress |
| LOT-004 | Oracle exporter: forms, write responses, storage formats (synthetic keychain blob, plists, MPStorage JSON) | tooling (legacy app) | medium | Sonnet → Fable | 001 | D9, E fixtures | mac/opus M1 (2026-10-26) | in-progress |

## Phase 3 — engine

### Models (`HFRModels`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-010 ✱ | List models: forums, topics, flags, pagination, search hits, favourites sections | HFRModels | easy | Sonnet → Opus | — | B1 | cloud/c1-sonnet (2026-10-25) | done |
| LOT-011 ✱ | Topic page & message models, `MessageContent` (normalized HTML, signature, typed images/smileys/links/embeds — the LOT-034 output), `MessageActions`, poll | HFRModels | easy | Sonnet → Opus | — | C01 | cloud/c1-sonnet (2026-10-25) | done |
| LOT-012 ✱ | Form & write models (`ForumForm`, `HopResponse`, `RehostedImage`, AQ items), bundled smiley catalogue resource | HFRModels | easy | Sonnet → Opus | — | D1, D2, D10 | cloud/c1-sonnet (2026-10-25) | done |
| LOT-013 ✱ | Account, `StoredCookie` (Codable, never `HTTPCookie`), settings enums, MPStorage document types | HFRModels | easy | Sonnet → Opus | — | E-3, E-6 | cloud/c1-sonnet (2026-10-25) | done |
| LOT-014 ✱ | Forum catalogue: category id table, URL aliases | HFRModels | trivial | Haiku → Sonnet | 010 | B2 | cloud/c1b-haiku (2026-10-25) | done |

### Parsing (`HFRParsing`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-020 ✱ | Parsing core: selector helpers, HFR dates (Europe/Paris), URL helpers, obfuscated-URL decoder, integer extraction, typed errors | HFRParsing | medium | Opus → Fable | 010, 011 | B3, C02, D4 | cloud/c4-opus (2026-10-25) | in-progress |
| LOT-021 | Forum list (home page) parser (returns all categories; hiding Apple for reviewers is app policy, Q-7) | HFRParsing | medium | Sonnet → Opus | 010, 020, 002 | B4 | — | todo |
| LOT-022 ★ | Topic list parser (forums, MP, search results) — critical path | HFRParsing | difficult | Opus → Fable | 010, 020, 002 | B5 | — | todo |
| LOT-023 ★ | MP list specifics + unread badge (one parser for the 3 legacy variants) | HFRParsing | easy | Sonnet → Opus | 022 | B6, NET-13 | — | todo |
| LOT-024 | Favourites page parser | HFRParsing | medium | Sonnet → Opus | 022 | B7 | — | todo |
| LOT-025 | Small parsers: search redirect, `editprofil` page (hash, avatar), smiley search results, AQ listing and AQ RSS feed | HFRParsing | easy | Sonnet → Opus | 020 | B8, NET-04, NET-12, D6, D9 | — | todo |
| LOT-026 | Poll parser (vote / results / closed) | HFRParsing | medium | Sonnet → Opus | 011, 020 | B9, C07, D11 | — | todo |
| LOT-027 | User profile page parser (`/hfr/profil-NNN.htm`: fields, avatar, personal smileys) | HFRParsing | medium | Sonnet → Opus | 010, 020 | review F4 | — | todo |
| LOT-030 | Message block extraction — core of the topic page | HFRParsing | difficult | Fable → Opus | 011, 020, 003 | C03 | — | todo |
| LOT-031 | Per-message action links (quote, edit, alert, profile, MP, flag, quoteJS) | HFRParsing | medium | Opus → Fable | 030 | C04 | — | todo |
| LOT-032 | Quote analysis (authors, nesting) | HFRParsing | medium | Sonnet → Opus | 030 | C05 | — | todo |
| LOT-033 | Topic page metadata (title, pagination, answer form, hidden fields) | HFRParsing | medium | Sonnet → Opus | 011, 020, 003 | C06 | — | todo |
| LOT-034 | Content normalization (smileys, images, links, signature, code, spoilers) | HFRParsing | difficult | Fable → Opus | 030, ADR 0006 | C08 | — | todo |
| LOT-035 | Video embed detection (fixes the YouTube hour bug) | HFRParsing | easy | Sonnet → Opus | 034 | C09 | — | todo |
| LOT-036 | `hop` form parser (inputs, selects, `content_form` textarea incl. `[quotemsg]` prefill, entity decoding) | HFRParsing | medium | Sonnet → Opus | 012, 020, 004 | D1 | — | todo |
| LOT-037 | `hop` response classifier (success, rejected, logged out, already alerted) | HFRParsing | medium | Sonnet → Opus | 012, 004 | D2 | — | todo |
| LOT-038 ★ | MPStorage page parsing (locate the storage MP, read its JSON) | HFRParsing | medium | Sonnet → Opus | 023, 030 | D8 | — | todo |

### Network (`HFRNetwork`) — transport, endpoints, sessions, raw fetchers

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-040 ✱ | Transport: protocol + URLSession + mock, form encoding (fixes accent bug), charset decoding, timeouts, typed errors incl. HTTP status | HFRNetwork | easy | Sonnet → Opus | — | NET-01, NET-14 | cloud/c2-sonnet (2026-10-25) | done |
| LOT-041 ✱ | Endpoint catalogue (typed URL builders) | HFRNetwork | easy | Sonnet → Opus | 040, 014 | NET-02 | cloud/c2b-sonnet (2026-10-25) | done |
| LOT-042 ✱ | Per-account session: isolated cookie jar, `hash_check` with `updateHashCheck(_:)`, multi-quote cookie (exact id match), `StoredCookie` import/export | HFRNetwork | medium | Opus → Fable | 040, 013 | NET-03, C16, D4 | cloud/c2c-opus (2026-10-25) | done |
| LOT-045 ✱ | Page fetchers: lists and topic page (final URL after redirects); cookie-less client for prefetch and images, since authenticated topic GETs mark flags read | HFRNetwork | easy | Sonnet → Opus | 041, 042 | NET-08, NET-09 | cloud/c2d-sonnet (2026-10-26) | in-progress |
| LOT-056 | Image hosts: rehost client (key and base URL injected; legacy key reused for now, ADR 0007) + host adapter table (Referer for reho.st, keyless hosts, http-only hosts) | HFRNetwork | easy | Sonnet → Opus | 012 | D10 | — | todo |

### Flows (`HFRClient`) — fetch → parse → submit → classify ([ADR 0008](adr/0008-hfrclient-orchestration-module.md))

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-043 | Login (validate before replacing cookies) | HFRClient | medium | Opus → Fable | 042, 025 | NET-04 | — | todo |
| LOT-044 | Session health & refresh (expiry detection, cookie merge) | HFRClient | medium | Opus → Fable | 042, 013 | NET-07 | — | todo |
| LOT-046 | Search: global (meta-refresh flow, banned-word list → refuse with a warning, Q-7) and intra-topic (no-redirect flow) | HFRClient | medium | Sonnet → Opus | 041, 025 | NET-10, NET-11 | — | todo |
| LOT-047 | MP unread count poll (scheduling stays in the app) | HFRClient | easy | Sonnet → Opus | 023, 045 | NET-13 | — | todo |
| LOT-048 | Post-form engine: reply, edit, delete (incl. first post = whole topic), new topic, new MP, MP reply — posts as the **selected** account (Q-8); `verifrequet`, browser checkbox semantics, refuses non-BMP characters (Q-3), per-flow success markers, never reports success unless HFR confirmed it | HFRClient | difficult | Opus → Fable | 036, 037, 042 | D3 | — | todo |
| LOT-049 | Quote engine: quote template GET, `[quotemsg]` selection formatter | HFRClient | medium | Opus → Fable | 048, 031 | D4 | — | todo |
| LOT-050 | Moderator alert | HFRClient | easy | Sonnet → Opus | 036, 037 | D5 | — | todo |
| LOT-051 | Topic flags & favourites writes | HFRClient | medium | Opus → Fable | 037, 042 | D7 | — | todo |
| LOT-052 ★ | MPStorage transport (find, read, create, update; conflict-aware) | HFRClient | difficult | Opus → Fable | 038, 048, 062 | D8 | — | todo |
| LOT-053 | Smileys: search, wiki | HFRClient | easy | Sonnet → Opus | 025 | NET-12, D9 | — | todo |
| LOT-054 | Poll vote | HFRClient | medium | Sonnet → Opus | 026, 037 | D11 | — | todo |
| LOT-055 | AQ client: per-topic check, create, RSS feed + "new since" badge; returns every item with its category (hiding Apple for reviewers is app policy, Q-7) | HFRClient | easy | Sonnet → Opus | 025, Q-4 | D6 | — | blocked |
| LOT-057 | REST browsing client (`rest_api.php`: categories, topics, flag buckets) with HTML fallback | HFRClient | medium | Opus → Fable | 040, 041, 010, 021, 022, 024, 001 | redface2 E1 | — | todo |
| LOT-058 | MP actions: mark unread, group MP members, MP quote | HFRClient | easy | Sonnet → Opus | 042, 045, 036 | redface2 E6, E8, E9 | — | todo |

### Storage (`HFRStorage`)

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-060 ✱ | Settings catalogue & store (legacy key names kept) | HFRStorage | easy | Sonnet → Opus | 013 | E-1 | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-061 ✱ | Blacklist / whitelist store (never overwrite with empty) | HFRStorage | medium | Sonnet → Opus | 013 | E-2 | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-062 ✱ | MPStorage document codec & merge (incl. `mpFlags` for MP list decoration) — pure value logic, usable by `HFRClient` | HFRModels | medium | Opus → Fable | 013 | E-3 | cloud/c3b-opus (2026-10-26) | in-progress |
| LOT-063 ✱ | Drafts per context | HFRStorage | easy | Sonnet → Opus | 013 | E-4, D12 | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-064 | Small stores: super-favourites, favourites layout, smiley favourites, histories | HFRStorage | medium | Sonnet → Opus | 013, 004 | E-5 | — | todo |
| LOT-065 ✱ | Account & credential store: protocol + in-memory/file (Linux) + Keychain under `#if canImport(Security)`, versioned envelope | HFRStorage | difficult | Opus → Fable | 013 | E-6, NET-05 | cloud/c3b-opus (2026-10-26) | in-progress |
| LOT-066 ✱ | Caches: avatars, temporary files, eviction | HFRStorage | easy | Sonnet → Opus | — | E-8, C17 | cloud/c3a-sonnet (2026-10-26) | done |
| LOT-067 | Legacy data import on update (accounts, lists, settings, drafts, smiley favourites, layout), idempotent, never deletes the source; also removes the legacy app caches on first launch (e.g. `Caches/cache/topic-*.htm`) | HFRStorage | difficult | Opus → Fable | 060, 061, 064, 065, 004, Q-1 | E-7, NET-06 | — | todo |
| LOT-068 | Offline reading: save topics/pages for reading without network, list and evict them (Q-5) | HFRStorage | medium | Sonnet → Opus | 011, 066 | E-8, `OfflineStorage.m` | — | todo |

### Gates

| Lot | Scope | Module | Difficulty | Model | Depends on | Audit | Owner | Status |
|---|---|---|---|---|---|---|---|---|
| LOT-071 | Third-party services: inventory (image rehost, AQ, Giphy…), data sent, owner, first-use notices, configuration (Q-4, ADR 0007) | docs | easy | Opus → Fable | — | review Q-4 | — | todo |
| LOT-070 | Parity gates: differential roll-up, persistence parity checklist, write chapter of HFR-PROTOCOL | docs/tests | medium | Opus → Fable | all parsing/network/storage lots | C18, E-9, D13 | — | todo |

## Phase 4 backlog — app side (not engine)

Pure Swift but app-side, kept here so nothing is lost: visibility policy (BL/WL/filters, C10) · filtered-posts use case (C11, candidate for `HFRClient`) · message HTML builder (C12) · page shell & resources (C13) · typed JS bridge (C14) · message action policy (C15) · image/GIF decoding (E-8) · background MP check scheduling (NET-13) · Giphy (E-10) · MP list decoration with `mpFlags` · account deletion mail and other hard-coded addresses (Q-10) · static pages, alternate icons, haptics, tab-bar settings UI · App Review policy: hide the Apple category (cat 25) when logged out or for the configured review account (Q-7) · inbound link router (forum links open the app) · Dynamic Type everywhere · iPad multi-window and favourites side panel · "posts quoting me" view (`quote_only=1`) · reply "+" carries selected quotes, classic post layout option (user feedback, docs/research/user-feedback-p450-510.md).
