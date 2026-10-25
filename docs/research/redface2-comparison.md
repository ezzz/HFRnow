# Redface 2 (Android) vs SwiftHFR: comparison and convergence study

Date: 2026-10-25. Status: research note, not normative. Nothing here changes `HFR-PROTOCOL.md` or `LOTS.md`; Section 4 lists the amendments we should make once we have our own fixtures.

## 0. Scope, sources, limits

**Subject.** `ForumHFR/redface2`, the community Android client for forum.hardware.fr ("Redface 2"), a ground-up rewrite of the Java client Redface v1.

**What was read.**

| Item | Value |
|---|---|
| Clone | `git clone --depth 50` into `/tmp/claude-0/redface2` |
| `main` | `08d5b41c`, 2026-09-22, app 0.62.0 (public beta) |
| `dev` | `7bb95d03`, 2026-10-15, app 0.63.2 (fetched separately, 7 commits ahead of `main`; diff touches diagnostics, flags refresh, no protocol doc) |
| `gh-pages` | **does not exist**. `git ls-remote --heads` lists only `main`, `dev`, `fix/873-preview-perso-smileys` and Dependabot branches. The project site (<https://forumhfr.github.io/redface2>) is a Jekyll "just-the-docs" site built from `docs/` (`docs/_config.yml:1-22`), so the repo `docs/` folder **is** the site source. |
| Our side | `README.md`, `docs/ARCHITECTURE.md`, `docs/audit/README.md`, `docs/LOTS.md`, `docs/HFR-PROTOCOL.md`, audit reports A-E (grep only), ADR 0003/0007, `FIXTURES.md`, `ROADMAP.md`, `LICENSE`, `CREDITS.md` |

**Limits (read before trusting any claim).**

1. forum.hardware.fr and `*.github.io` are unreachable from here. **I verified nothing against the live forum.** Every statement tagged *rf2-live* is redface2's own claim of live verification (usually with a date and a fixture name). Treat it as strong second-hand evidence, not as ground truth.
2. The GitHub REST API was not available for this repository in this session, so stars, forks, open-issue counts, the contributors page and GitHub Releases metadata are **unverified**. Activity figures below come from the local git history and from `app/CHANGELOG.md`.
3. The clone is shallow, so commit counts are what the clone exposes (674 commits), not necessarily the whole history.
4. License conclusions in Section 5.1 are engineering analysis, not legal advice.

**Citation conventions.**

- `rf2:path:line` = file in the redface2 clone at `main@08d5b41c` unless marked `dev`.
- `PH` = `rf2:docs/specs/protocol-hfr.md` (1182 lines). `HP` = our `docs/HFR-PROTOCOL.md`.
- Evidence tags: **rf2-live** (claimed live-verified by redface2), **rf2-code** (visible only in its code or fixtures), **ours-code** (our audit of legacy code), **unverified**.

---

## 1. Redface 2 overview

### 1.1 Identity and status

| Aspect | Finding | Source |
|---|---|---|
| Purpose | Community Android client for HFR, public beta, rewrite of Redface v1 | `rf2:README.md:1-5` |
| Distribution | Google Play open beta, F-Droid beta and dev channels (own repo `forumhfr.github.io/redface2-fdroid`), signed APKs on GitHub Releases (`app-v<N>` tags) | `rf2:README.md:7-14` |
| Version | 0.62.0 beta (2026-09-22) on `main`; 0.63.2 dev (2026-10-15) | `rf2:app/build.gradle.kts:56`, `rf2:app/CHANGELOG.md:19`, `dev` log |
| Feature state | Phases 0-3 of its roadmap delivered (reading, writing, MP, DT); Phase 4 = UI rework delivered, community extensions (bookmarks, AQ, redflag, colour tag, GIF, stats) **not started** except blacklist | `rf2:docs/specs/roadmap.md:29-36`, `rf2:docs/specs/extensions.md:16-19` |
| Open umbrellas | extension architecture (#7), MPStorage sync between devices (#6) | `rf2:README.md:23` |
| License | **GPL-3.0-only** | `rf2:LICENSE`, `rf2:README.md:66`, `rf2:docs/adr/010-licence-client-android.md:28` |
| Language | French docs, French-only UI | `rf2:docs/specs/scope.md:134` |

### 1.2 Tech stack

Source of truth: `rf2:gradle/libs.versions.toml`, summarised in `rf2:docs/specs/stack.md:18-38`.

| Layer | Choice |
|---|---|
| Language / UI | Kotlin 2.4.10, Jetpack Compose (BOM 2026.08), Material 3 + M3 Adaptive 1.2, Navigation 3 1.1.2 |
| Pattern / DI | MVI (unidirectional), Hilt 2.60 (KSP) |
| HTTP | OkHttp 5.5 directly (no Retrofit), `kotlinx.serialization` for the REST payloads |
| HTML | Jsoup 1.23.2 (only HTML parser) |
| Storage | Room 2.8.4 (schema v19, 9 entity classes under `rf2:core/database/.../entities/`), DataStore for preferences, cookies, blacklist JSON, super-favourites |
| Images | Coil 3.6 (+ GIF, SVG), Telephoto for zoom |
| Targets | minSdk 29, targetSdk 36, compileSdk 37 |

### 1.3 Architecture and modules

18 Gradle modules (`rf2:settings.gradle.kts:17-37`): `:app`; 8 `:core:*` (model, domain, data, network, parser, database, ui, extension); 9 `:feature:*` (flags, forum, topic, editor, messages, auth, search, settings, profile). `:core:extension` is an empty shell: the planned extension modules (bookmarks, blacklist, qualitay, redflag, colortag, imagehost, gifpicker, stats) are commented out in `settings.gradle.kts`. Module boundaries are enforced by Konsist (`rf2:app/src/test/kotlin/fr/forumhfr/redface2/ArchitectureKonsistTest.kt`).

Size: 529 main Kotlin files / about 91.7k lines; 403 test files / about 105.6k lines (counted locally).

The split that matters for us mirrors our own: `core:parser` (pure functions from HTML to models), `core:network` (OkHttp, cookies, endpoints), `core:data` (repositories orchestrating fetch, parse, submit, cache), `core:domain` (interfaces and pure logic). Roughly `HFRParsing` / `HFRNetwork` / `HFRClient` plus `HFRStorage` in our terms.

### 1.4 How it fetches and parses HFR

**Hybrid REST + HTML scraping**, formalised in ADR-003 (`rf2:docs/adr/003-api-rest-hfr-hybride.md:21-48`):

- **JSON REST** at `/webservices/rest_api.php?uri=<URI>` for *browsing*: category list, sub-categories, topic lists, personal flag buckets, topic metadata. Client: `rf2:core/network/.../HfrApiClient.kt` (REST path constant at `:252`, HATEOAS rewrite at `:159`). DTOs and mappers live in `core:data` (`RestForumDtos.kt`, `RestFlagMappers.kt`). The ADR reports a bench of -91% bytes and 3.45x speed-up over HTML for a simulated session (`ADR-003:28`), and 1 KB vs 220 KB for topic metadata (`ADR-003:43`).
- **HTML + Jsoup** for post content, private messages, login, every write, search, polls, profile. Selector constants in `rf2:core/parser/.../common/HfrSelectors.kt:3-104`; parsers under `rf2:core/parser/src/main/kotlin/fr/forumhfr/redface2/core/parser/` (about 4.5k lines).
- **Five OkHttp clients** (`rf2:core/network/.../di/NetworkModule.kt:44-105`): authenticated (read), mutation (no connection retry), anonymous (no cookie jar), image (no cookies, may follow https-to-http), upload (long timeouts, no cookies). None follows https-to-http redirects except the image client (`NetworkModule.kt:50,60,71,80-87`).
- Timeouts: connect 15 s, read 20 s, write 20 s, call 30 s (`rf2:core/network/.../HfrConstants.kt:34-37`); custom User-Agent `Redface2/0.1 (Android; +https://github.com/ForumHFR/redface2)` (`HfrConstants.kt:9`).
- Session expiry is detected from the final URL (`/login.php`, `/login_validation.php`) or from a login form served with HTTP 200 (`rf2:core/network/.../HfrClient.kt:1028-1048,1088-1096`). Non-2xx raises a typed `HfrServerException` (`HfrClient.kt:1030-1034`).
- Concurrency guidance recorded as *empirical*: at most 10 simultaneous TCP connections to HFR (Apache saturates near 20), at most 2 POST/s, exponential backoff on 429/403, no `Retry-After` (`PH:848-854`, `ADR-003:54`, `PH:1124`).

### 1.5 Auth, session, accounts

- Login: `POST /login_validation.php?config=hfr.inc` with only `pseudo` and `password`; success is decided from the **`Set-Cookie: md_user`** value matching the submitted pseudo (URL-form-decoded), not from the body; failures from two body markers (`rf2:core/network/.../auth/AuthRemoteDataSource.kt:61-72,135-147,181-182`). A staging cookie jar with redirects disabled means a failed login never installs a session (`AuthRemoteDataSource.kt:87-102,117-120`).
- Persistence: session cookies only, in an unencrypted DataStore, relying on Android file-based encryption and `allowBackup=false`; **no password stored, no transparent re-login** (`rf2:docs/adr/002-credentials-option-a.md:30-38`, `PersistentCookieJar.kt`).
- **Multi-account is a stated non-goal** (`rf2:docs/specs/scope.md:131`). In practice a user can log in as another account directly, and caches, drafts and super-favourites are keyed per lower-cased pseudo and purged on logout or switch (`rf2:core/domain/.../editor/EditorDraftStore.kt:5-18`, `rf2:app/CHANGELOG.md:505`, `ADR-018` decision 3). There is no stored list of accounts.

### 1.6 Rendering of posts

HFR HTML is parsed into a frozen **`PostContent` AST** (blocks + inline), serialized into Room, and rendered with Compose `AnnotatedString` plus block composables (`rf2:docs/adr/011-postcontent-ast.md`, `rf2:docs/guides/known-issues.md:17`). A separate `BbcodeContentParser` builds the same AST from editor BBCode for live preview. Image rendering has its own normative 922-line contract (`rf2:docs/specs/images.md`, v1.6): intrinsic size, no upscaling, per-host headers, anti layout-shift. No WebView.

### 1.7 Storage

Room cache of topics, flags, MP pages and read positions (v19, 19 schema snapshots in `rf2:core/database/schemas/`); DataStore for preferences, cookies, blacklist JSON, super-favourites; per-account editor drafts with a retention TTL; MP content cached in RAM, with an **opt-in, default-off** disk cache that overwrites database bytes on logout (`rf2:docs/adr/018-mp-cache-disque-opt-in.md`). The MPStorage location (thread id plus first-post `numreponse`) is cached per account in `mp_storage_locations`.

### 1.8 Tests and CI

- JUnit 4, MockK, Robolectric, Turbine, Konsist (architecture), Roborazzi (screenshot tests, record-only), MockWebServer (`rf2:gradle/libs.versions.toml`). 401 `*Test.kt` files.
- **Fixtures**: raw HFR captures, never hand-written; `core/parser/src/test/resources/fixtures/` has 188 files and `core/data/src/test/resources/fixtures/` 87 (HTML, REST JSON, `.source.txt` sidecars with URL, capture date, sanitization, test context). A blocking CI guard enforces provenance (`rf2:scripts/check-fixtures-provenance.sh`, `rf2:AGENTS.md:80`). Policy: 100% coverage on the HTML-to-model transformers, risk-based elsewhere.
- CI (`rf2:.github/workflows/ci.yml`): matrix of assemble / test / lint / detekt, plus a `repo-guards` job (fixture provenance, changelog on version bump, "reading parity" guard that blocks PRs touching topic or MP reading code without updating `docs/specs/reading-parity.md`).
- Release (`rf2:.github/workflows/release.yml`): manual dispatch builds signed AAB/APK, tags `app-v<N>` (tag ledger allocates `versionCode`), creates a GitHub Release, uploads to Play Console, feeds F-Droid.

### 1.9 How it is built

The README states the code is "produced by LLM agents orchestrated from Claude Code, with cross-review and blocking CI" and that forum testers steer the product (`rf2:README.md:5`). History bears this out: about 324 of the 674 visible commits carry a `Co-Authored-By: Claude ...` trailer and about 22 a GPT trailer. The operating manual for agents is `rf2:AGENTS.md` (symlinked as `CLAUDE.md`, `GEMINI.md`) with 14 skills under `.agents/skills/`. Same working model as ours.

### 1.10 Activity (from the clone)

| Metric | Value |
|---|---|
| First visible commit | 2026-05-31 |
| Last commit | `main` 2026-09-22; `dev` 2026-10-15 |
| Commits by month (visible) | 2026-05: 1, 06: 266, 07: 128, 08: 121, 09: 158 |
| Authors | one human maintainer under several identities ("Clément XaT" 617 commits under two e-mail addresses, azora.fr and gmail; "xat" 47 commits, azora.fr), very likely one person (**unverified**), plus Dependabot (10). No other human committer is visible. |
| Releases | 250 `app-v<N>` tags from `app-v69` (2026-06-01) to `app-v346` (2026-09-22); 164 changelog entries June-September, of which 11 are public beta promotions (0.18.0 on 2026-06-29 up to 0.62.0 on 2026-09-22) |
| Scale of PR flow | PR/issue numbers reach #1479 by 2026-10-15 |
| Community loop | Testers report in two HFR forum topics (beta and dev) linked from the README; two HFR accounts (XaTelitte, XaTriX) are used as test accounts in the fixtures; XaTriX also appears as the product arbiter in the docs (`rf2:docs/specs/images.md:14-17`), so it is probably the maintainer's pseudo (**unverified**) |
| Stars, forks, outside contributors | unverified (API unavailable) |

Interpretation: a very high-velocity, single-maintainer, agent-driven project with an active tester community, still moving as of two weeks before this note.

---

## 2. Feature matrix

Legend. *Legacy iOS* is taken from our audit (section refs in parentheses); where the audit is silent the cell says "unverified". *redface2* is from code, docs and changelog. *SwiftHFR plan* uses lot ids from `docs/LOTS.md`; "none" means no lot and no Phase 4 backlog line.

### 2.1 Reading and navigation

| Feature | Legacy iOS | redface2 | SwiftHFR plan |
|---|---|---|---|
| Forum and sub-category list | yes, HTML home (A E1, B4) | yes, REST `categories/` (19 public), `rf2:PH:1092` | LOT-021 (HTML), LOT-014 (static id table) |
| Topic list of a (sub)category | yes (A E2, B5) | yes, REST `topics/last/`, 50 per page, flags inline when logged in (`PH:1094-1095`) | LOT-022 |
| Read a topic (pages, anchors, rendering) | yes, WKWebView + HTML rewriting (C) | yes, Jsoup to AST to Compose (`PH:1074-1076`, ADR-011) | LOT-030..035 |
| Resume at last read | first-unread anchor from the HTML flags page (`PH:1144`, stated for the HTML client generally; unverified for our legacy app) | REST `last_post_read_id` as scroll anchor, "last read" divider, restored scroll position | partly LOT-024/033; no explicit lot |
| Flag lists (cyan / red / favourites) | yes, HTML `forum1f.php` (A E3) | yes, REST per-category fan-out + Room cache (`PH:1097-1098`), redesigned view (ADR-017) | LOT-024 (HTML parser) |
| Add / remove favourite flag | yes (`addflag` GET; bulk `manageaction.php` POST, HP:56-57) | add yes; remove one yes via `delflag.php` GET; bulk not implemented (`PH:226-258`) | LOT-051 |
| Super-favourites (local pins) | yes, local (D 2.8) | yes, local per account, "Super" tab (`rf2:docs/specs/navigation.md:96`, `rf2:app/CHANGELOG.md:505`) | LOT-064 |
| "Cited N times" / posts citing a post | unverified | yes, `quote_only=1` (`PH:69`) | none |
| Public profile | yes (R9) | yes + role badge from staff directory (`PH:260-334`) | LOT-027; staff directory none |
| Sanctions history | no | yes (`PH:182-224`) | none |
| Deep links from HFR URLs | unverified | yes, intent filters for `forum1/2/1f.php`, `/user/modo.php`, `/hfr/*` (`rf2:app/src/main/AndroidManifest.xml:19-60`); cannot auto-verify, hardware.fr is not theirs (`known-issues.md:48`) | URL helpers in LOT-020; routing Phase 4; no lot. iOS Universal Links hit the same limit (we cannot host `apple-app-site-association` on forum.hardware.fr). |
| Tablet / large screen | unverified | adaptive nav bar/rail (`NavigationSuiteScaffold`, `rf2:app/.../RedfaceNavigation.kt:1297`); two-pane list-detail specified (`scope.md:122`) but **not found in code** (unverified) | Phase 5 column navigation, no lot |

### 2.2 Writing

| Feature | Legacy iOS | redface2 | SwiftHFR plan |
|---|---|---|---|
| Reply | yes (D 2.1) | yes | LOT-036/037/048 |
| Single quote | yes, server-generated `[quotemsg]` (D 2.2) | yes; "Citer" self-built from `numrep`, "quote start" truncation | LOT-049 |
| Multi-quote | yes, **client cookie** `quotes...` (D 2.2b, C 5) | yes, **no cookie**: N quote-form GETs concatenated client-side, basket FAB (`rf2:core/domain/.../TopicReplyQuoteMaterializer.kt:1-26`) | LOT-042 (cookie) + LOT-049 |
| Edit post | yes (D 2.3) | yes | LOT-048 |
| Edit first post (title, sub-category, poll) | unverified (`HP:46-50` lists edit and new topic separately) | yes (`PH:516-543`) | LOT-048 (scope unclear) |
| Delete post / topic | post yes; HP:49 says first post not deletable | post yes; **first post deletes the whole topic** (`PH:545-562`) | LOT-048 |
| New topic | yes (D 2.5) | yes (success returns no topic id, `PH:499`) | LOT-048 |
| Drafts | yes (D12) | yes, per account, TTL purge (`EditorDraftStore.kt`) | LOT-063 |
| Message tone icon (`MsgIcon` 1-16) | unverified (field forwarded) | yes (`PH:1006-1019`) | none (generic hidden-field copy) |
| Smileys: builtin, perso, search | yes (R7, D 2.11) | yes; search via `message-smi-mp-aj.php` (`PH:804-820`); intrinsic sizing | LOT-012, LOT-034, LOT-053 |
| Smiley favourites | yes (E-5) | not found (unverified) | LOT-064 |
| Image upload | yes, Chevereto `img3.super-h.fr` with hard-coded key (D 3.2, ADR 0007) | yes, **Diberie anonymous** (default) and **Imgur with the user's own Client-ID** (`rf2:core/data/.../upload/DiberieProvider.kt:25,144-145`, `ImgurProvider.kt:26-32`) | LOT-056 (injected key) |
| GIF picker | yes, Giphy SDK with hard-coded key (E 6) | no (planned, Phase 4) | Phase 4 backlog (E-10), undecided |
| Polls | read, vote (PollData.swift, D 2.9) | read, vote, close, create/edit via first post (`PH:340-401`) | LOT-026, LOT-054; close and create none |
| Moderator alert | yes (D 2.6) | yes, 6-state flow, incoming-link handling (`PH:71-180`) | LOT-050 |

### 2.3 Private messages and sync

| Feature | Legacy iOS | redface2 | SwiftHFR plan |
|---|---|---|---|
| MP list, read, reply, new | yes (B6, D 2.5) | yes | LOT-023, LOT-048 |
| MultiMP ("DT") members, participants | unverified | yes (`newdest`, `PH:914-922`) | none |
| MP quote and multi-quote | unverified | yes (`PH:924-987`) | LOT-049 covers topics; MP not explicit |
| Mark MP as unread | unverified | yes (`nonlu.php`, `PH:903-912`) | none |
| MP unread badge / background check | yes, BGTask + local notification (E 93-94) | no; non-goal, "polling only if decided later" (`scope.md:129`) | LOT-047 + Phase 4 scheduling |
| MP delete / archive | unverified | not found | none |
| MPStorage: read (`mpFlags`, DT read positions) | yes (E-3) | yes, plus seeding of local positions (ADR-014 decision 5) | LOT-038, LOT-052, LOT-062 |
| MPStorage: write | yes, full read-modify-write, no checks (D 2.10) | yes but **opt-in, OFF by default**, update-only mode, verify-after-write, size cap (`PH:989-1000`) | LOT-052 (conflict-aware) |
| Blacklist | yes, local + MPStorage sync (E-2) | yes, local DataStore JSON, collapsible placeholder; **no MPStorage sync found** (unverified) | LOT-061, LOT-062 |
| Whitelist ("love list") | yes, local (E 67) | no | LOT-061 |
| Bookmarks | yes, MPStorage-backed (D 2.10) | no (planned Phase 4) | LOT-038/052/062 storage; UI Phase 4 |
| AQ (Alerte Qualitay) | yes, `aq.super-h.fr` (D 2.7) | no (RSS URL cited only, `extensions.md:272`) | LOT-055 (status blocked) |
| Ego quote / ego posts highlight | unverified | partial (`rf2:core/domain/.../ego/EgoHighlight.kt`; UI extent unverified) | none |

### 2.4 Search

| Feature | Legacy iOS | redface2 | SwiftHFR plan |
|---|---|---|---|
| Global search | yes, POST `search.php`, meta-refresh (A E7-E8) | yes, **direct anonymous GET** of the results URL, filters (pseudo, date, scope), pivot categories (`PH:670-695`, `rf2:HfrClient.kt:645-675`) | LOT-025, LOT-046 |
| Intra-topic search | yes, `transsearch.php` (A E6) | yes, with next/previous and filter mode (`PH:697-708`) | LOT-046 |

### 2.5 Accounts and platform

| Feature | Legacy iOS | redface2 | SwiftHFR plan |
|---|---|---|---|
| Login / logout | yes | yes | LOT-043 |
| Multi-account | yes, `MultisManager`, switch = cookie wipe (A 4) | no saved accounts (non-goal); direct re-login works | LOT-042 per-account sessions, LOT-065, Q-8 |
| Credential storage | Keychain, `NSKeyedArchiver`, no password | unencrypted DataStore + platform FBE, no password | LOT-065 (Keychain, after-first-unlock, this-device-only) |
| Session-expiry handling | partial (no HTTP status check, A 3.4) | yes, typed exception, re-login prompt | LOT-044 |
| Themes, dark mode | yes (E 137-141) | yes: light / dark / AMOLED, 8 accents + hex, dynamic colour, tones | LOT-060 (settings only); UI Phase 4 |
| Text scaling | yes (injected CSS font size, C 101) | yes, preset x system font scale (`rf2:core/domain/.../FontScalePreference.kt:4-8`) | none (UI) |
| Accessibility | unverified | partial evidence: 218 `contentDescription` uses, normative a11y section in image contract (`images.md:482-532`) | none |
| Offline reading | exists, unused in HFRswift (E 209) | no; caches only, MP disk cache "is not an offline mode" (`ADR-018` decision 3) | LOT-068 (in scope, Q-5) |
| Widgets | none (E 319: dead `Extensions/` dir) | none | none |
| Share / save image / viewer | unverified | yes (zoom, save, share) | Phase 4 image decoding (E-8) |
| Proxy setting | no (`adv_ssl` disables TLS validation, not carried over) | yes (ADR-012, `rf2:docs/guides/proxy.md`) | none |
| Diagnostics export | unverified | yes, redacted (`DiagnosticRedactor.kt`) | none |
| Alternate app icons / haptics | yes (Phase 4 backlog) | alternate icons yes | Phase 4 backlog |

---

## 3. Gaps

### 3.1 What redface2 does that our plan misses

Ranked by expected value for SwiftHFR.

1. **The JSON REST API** (`/webservices/rest_api.php`). Neither the legacy app nor `HFR-PROTOCOL.md` knows it. It gives categories, sub-categories, topic lists, flag buckets and topic metadata as compact JSON, with read flags and last-read ids inline, for a fraction of the bytes. Now planned as LOT-057 (`HFRClient`); a redface2-reported fact pending verification with LOT-001 fixtures (HFR-PROTOCOL §7, E1).
2. **The "authenticated GET changes server state" rule.** HFR marks topics as read on *any* authenticated request, so prefetch must be anonymous (`PH:858-901`). Our plan has no such rule; it matters for LOT-045 (fetchers), LOT-068 (offline save) and any background refresh. The one bounded exception redface2 found: the MP list GET is inert and the MP "unread" state is a binary per-conversation dot cleared by opening it (`PH:901`).
3. **Silent post truncation at the first non-BMP character** (emoji) with an HTTP 200 success (`rf2:core/data/.../write/ContentFormSanitizer.kt:3-31`). Directly answers our open decision **Q-3**.
4. **Real response markers for every write** (success sentences, flood, invalid token, empty body, locked topic, deleted topic), each with a captured fixture (`PH:484-514,545-562`). Fills LOT-037 and answers the audit's open question D 10-4 (real flood wording).
5. **Endpoints we do not have**: `quote_only=1`, `delflag.php`, `nonlu.php`, `close_sondage.php`, `modo/historique.php`, the staff directory, `newdest` for MultiMP members, poll creation through first-post edit.
6. **MPStorage safety practice**: update-only write mode, verify-after-write with bounded restore, size cap, fail-closed on unstorable characters, never repair or reset an unreadable document, unknown-key preservation, inbox scan with cached location (`ADR-014`, `rf2:DefaultMpStorageRepository.kt`). Our LOT-052/062 plan is conflict-aware but does not list these.
7. **Image host realities**: reho.st answers 403 without a `Referer` on `*.hardware.fr`, serves `http://` URLs that should be upgraded to https, and returns 200 with an empty body for unknown hashes (`rf2:docs/specs/images.md:188-192`). Without this, remote images from the most common HFR host fail in a native client.
8. **Privacy engineering for private content** (scrub on logout and switch, opt-in disk cache, overwrite of database bytes, per-account keys). Relevant to LOT-068 if offline reading ever includes MP.
9. **Process guards**: fixture-provenance sidecars enforced in CI, a "reading parity" matrix between topic and MP surfaces (`rf2:docs/specs/reading-parity.md`), docs-consistency tests.
10. **Smaller product features**: ego highlight, message tone picker, read-position sync for DT, session-state-aware sheets.

### 3.2 What we plan that redface2 lacks

1. **Multi-account** with isolated sessions and per-account posting (LOT-042, Q-8). redface2 has one active account.
2. **Whitelist** and **MPStorage-synced blacklist and bookmarks** (LOT-061/062). redface2 keeps its blacklist local and has no bookmarks.
3. **AQ client** (LOT-055). Not built there.
4. **Background MP check and notifications** (LOT-047 plus app scheduling). redface2 declares them out of scope.
5. **Keychain-grade credential storage** (LOT-065) versus their plaintext DataStore + OS encryption decision.
6. **Offline reading** (LOT-068). redface2 has caching but explicitly no offline mode.
7. **Differential testing against a second implementation** (legacy oracle, ADR 0004). redface2 relies on single-implementation fixture tests.
8. **Linux-testable UI-free engine** with enforced module boundaries. redface2's parser modules are pure JVM, but its network and data layers import Android APIs (for example `android.util.Log` in `AuthRemoteDataSource.kt:3`, `android.os.Looper` in `PersistentCookieJar.kt:3`), so they cannot be tested off-device without Robolectric.
9. **GIF picker** (deferred) and **Giphy**: not built there either, so not a differentiator yet.
10. **Source-cited protocol document with status per fact** (`HP` header, "code" vs "verified"). redface2's `protocol-hfr.md` has dates and fixture names but no systematic status column and contradicts itself in places (Section 4.5).

---

## 4. Protocol knowledge (most valuable section)

Everything below is second-hand (Section 0). Each row says whether redface2 **confirms**, **contradicts** or **extends** our `HFR-PROTOCOL.md`, with the evidence tag. Proposed follow-up is in the last column; all of it should be re-verified on our own fixtures (LOT-001) before we edit `HP`.

### 4.1 Confirmed (with extra detail)

| # | Our fact | redface2 evidence | Notes / action |
|---|---|---|---|
| C1 | Host and `config=hfr.inc` everywhere (`HP:7`) | `rf2:HfrConstants.kt:7-12` | Confirmed. rf2 builds all writes with `config=hfr.inc`. |
| C2 | `hash_check` is the anti-CSRF token, hidden input, per account (`HP:79`) | `PH:604-624`; per-session and **not rotated per request**, reuse of an earlier form's token is valid (`rf2:DefaultMpStorageRepository.kt:395`, **rf2-live**); empty on anonymous forms, 32 hex chars when authenticated (`PH:355-358`) | Supports LOT-042 design. Also: take the token from the form you are about to submit, never a global cache (`PH:119`). |
| C3 | Login at `/login_validation.php?config=hfr.inc`, fields `pseudo`, `password` (`HP:77`) | `AuthRemoteDataSource.kt:61-72`, `PH:574-583` | See X5 for the success signal and the two extra legacy fields. |
| C4 | `md_user` is the identity cookie (`HP:78`) | `PH:826-835`, `AuthRemoteDataSource.kt:111,180` | Also `md_pass` (1 year) and `md_forum` (session) per `PH:830-832`; see 4.5 for rf2's own inconsistency on cookie names. |
| C5 | Obfuscated links use the alphabet `0A12B34C56D78E9F`, pairs map to bytes (`HP:73`) | `rf2:CryptlinkDecoder.kt:42,59-70`; algorithm checked against HFR's `common.js` (`md_forum_decryptlink`) | Confirmed independently; also see E7 for extensions. |
| C6 | Dates are Paris time, `DD-MM-YYYY à HH:MM:SS`; list dates have no seconds | `rf2:HfrDateParser.kt:41-52,95-103`; "Posté le" prefix, "Message édité par" trailer | Confirms LOT-020. |
| C7 | MPStorage: subject `a2bcc09b796b8c6fab77058ff8446c34`, recipient `MultiMP`, first post holds a JSON envelope (`HP:61-62`) | `rf2:MpStorageRepository.kt:92`, `HfrConstants.kt:32`, `rf2:docs/specs/models.md:703-724` | Same constants as the legacy iOS code. |
| C8 | `mpFlags.list[]` entries are `{post, p, href, page, uri}` (E-3, `HP:61`) | `models.md:724`: `post` integer, `page` integer, `p` **string**, `href` = `t<numreponse>`, `uri` desktop URL, all with `cat=prive` | Matches our audit E (105). Real documents also carry numbers as strings from some writers, so decode leniently (`rf2:MpStorageParser.kt:12-20`). |
| C9 | MPStorage find = scan of the MP list; title search is not used (`HP:62`) | `ADR-014` addendum (`:71-73`): server title search **always** returns no result for the 32-hex subject on real accounts (**rf2-live**, 2026-06-14); scan up to 50 pages (`DefaultMpStorageRepository.kt:652`) | Confirms. Do not implement search-based discovery. |
| C10 | Write flows: GET form (`hop`), copy fields, override, POST (`HP:33-43`) | `ReplyFormParser.kt:22-27,130-166`, `DefaultReplyRepository.kt:228-285` | Confirmed. Reply and quote and new topic to `bddpost.php`, edit and delete to `bdd.php` (`PH:45-49`). |
| C11 | Add favourite = state-changing GET of the `addflag` link (`HP:56`) | `PH:242-248`, `HfrClient.kt:795`, **rf2-live** 2026-05-28 | Success text "Favori positionné avec succès". |
| C12 | `owntopic` filters: 1 cyan, 2 red, 3 favourites (`HP:14`) | REST `flag_owntopic`: 1 = participated (cyan), 2 = read (red), 3 = favourite, 0 = none (`PH:1132`) | Consistent naming. |
| C13 | Permalink redirect gives the page (`HP:17`) | `PH:668` | Extended in E16. |
| C14 | Smiley search needs 3+ characters (`HP:19`) | `PH:816`: HFR JS gates on `length > 2`, client debounces 300 ms | Confirmed. |
| C15 | Profile page structure `table.main`, `profilCase2/3`, avatar (`HP:21`) | `PH:272-276` (`body#unique__user_page__view_user_profile`, `h4.Ext`, `tr.profil td.profilCase2/3`, `div.avatar_center img`) | Confirmed. |
| C16 | Not-logged-in detection from login form markers (`HP:41`) | `HfrClient.kt:1088-1096` uses final URL and the combination `login_validation.php` + `name="pseudo"` + `name="password"` | Union the two marker sets in LOT-037/044. |
| C17 | HFR answers HTTP 200 even on rejection (`HP:38`) | Flood, invalid token, delflag miss, vote refusal all 200 (`PH:237-238,363-368,484-514`) | Confirmed. Plus: permalink 301 relative, deleted topic 404, REST `/posts/` 500 (`PH:668,562,1102`). |
| C18 | `subcat`, `post`, `page`, `cat` are required hidden fields | `PH:407-432` | Confirmed; see E24 for `subcat=0`. |

### 4.2 Contradicted or needing correction

| # | Our statement | redface2 says | Evidence | Impact |
|---|---|---|---|---|
| X1 | "First post of a topic not deletable" (`HP:49`) | **The topic owner can delete the first post**: the edit form shows "Effacer l'intégralité du sujet" (`delete=1`), the POST removes the whole topic, success text "Message effacé avec succès !", the topic URL then answers 404, the response refreshes to the sub-category list. | `PH:545-562`, **rf2-live** 2026-05-17 (`write_delete_topic_form.html`, `write_delete_topic_success_response.html`, `write_deleted_topic_404.html`) | LOT-048: model "delete topic" as a distinct, confirmed, destructive action; navigate to the list afterwards. |
| X2 | Quote text is `[quotemsg=cat,post,numreponse]` (`HP:71`) | `[quotemsg=<cited numreponse>,<opaque index>,<cited author's user id>]`, e.g. `[quotemsg=2784595,768,1214571]`. The second value was 768, 640, 1 in different captures, meaning unconfirmed. In MP the second value equals the source-page rank `ref` (`PH:943-944`). | `PH:468-482,938-948`, **rf2-live** | Fix `HP:71`. Safe approach (rf2's): reuse the server-prefilled `content_form` verbatim, never rebuild the tag. Our selection formatter (LOT-049) only needs to keep the three numbers opaque. |
| X3 | Checkboxes are copied as `"1"`/`"0"` (`HP:35`) | Browser semantics: unchecked checkboxes and radios are **not sent**. Options are `signature`, `smiley` (disable smileys) and `emaill` (HFR's own double-l spelling, e-mail notification); `MsgIcon` is a radio group 1-16 with one pre-checked; `password` is never echoed back; `pseudo` is echoed only when authenticated. | `rf2:ReplyFormParser.kt:134-148`, `DefaultReplyRepository.kt:268-285` | LOT-036/048: replace our "1/0" rule. Sending `signature=0` or leaving defaults checked changes behaviour. |
| X4 | Constant `verifrequet` not documented in `HP` | Every `bddpost.php` / `bdd.php` write carries `verifrequet=1100` (string). The vote form does **not** carry it. Other constants seen in forms: `wysiwyg=0`, `cache=cache`, `sond=0`, `new=0`, `p=1`. | `PH:407-432,626-640`, `HfrConstants.kt:20`; our own audit lists it only in the MPStorage field list (`audit D:85,164`) | Add to `HP` section 3.1; LOT-048 must set it (or copy it from the form). |
| X5 | Login success iff body contains `login_redirection.php` (`HP:77`); legacy also sends `action=send`, `login=Se connecter` | redface2 classifies by `Set-Cookie: md_user` equal (after URL-decoding, `+` is a space) to the submitted pseudo, with two body markers for failure: "Votre mot de passe ou nom d'utilisateur n'est pas valide" and "Afin de prévenir les tentatives de flood" (login rate limit). It sends **only** `pseudo` and `password`. Cookies from the response are held in a staging jar and committed only on success. | `AuthRemoteDataSource.kt:67-72,135-147,181-182`, `PH:586-598` | LOT-043: add the cookie-based signal and the rate-limit marker; the extra legacy fields look unnecessary (rf2-code, since rf2 ships without them). Match case-insensitively on pseudo? rf2 compares exactly; HFR displays some pseudos lower-cased (`PH:405`), unverified. |
| X6 | Remove a favourite with `POST /modo/manageaction.php` (`HP:57`) | Single removal is a plain `GET /user/delflag.php?config=hfr.inc&cat&subcat&post&page&p=1&sondage=0&owntopic=<type>&new=0`, `numreponse` not required. Success text "Drapeau effacé avec succès", failure text differs, both HTTP 200. Bulk `manageaction.php` is "out of scope" for them. | `PH:226-240,258`, **rf2-live** 2026-05-28 (favourite, `owntopic=3`); cyan/red removal inferred, not tested | LOT-051: both exist; `delflag.php` is simpler for the common case; keep `manageaction.php` for bulk (our contract, see 5.4). |
| X7 | Global search: POST `/search.php?config=hardwarefr.inc`, `hash_check` first, field order matters, query lowercased, results via meta-refresh (`HP:27-28`) | `search.php` POST returns a waiting page whose `<meta refresh>` points to `GET /forum1.php?recherches=1&...`; rf2 **skips the POST** and calls the GET anonymously (no `hash_check`), with `config=hfr.inc`, `cat=<id>*hfr.inc` or empty, `resSearch=20`, `daterange=2`, `jour/mois/annee` required even when ignored, `titre` 0 / 1 / 3, `orderSearch` 0 / 1, `searchtype=1`, `trash=0`, `trash_post=0`, `moderation=0`. Order is "not significant". HFR upper-cases the echoed query and matches case-insensitively, so lowercasing is unnecessary. | `PH:670-695`, `rf2:HfrClient.kt:645-675`, **rf2-live** 2026-05-22 | LOT-046: our two-step flow works but a direct GET is simpler and needs no session. Re-verify `config` (hfr.inc vs hardwarefr.inc) and the 200 vs 20 result size. |
| X8 | MPStorage JSON = text of the first message's `<p>` with U+00A0 removed (`HP:63`) | JSON is read from the **edit form** of the first post: `GET message.php?cat=prive&post=<mp>&numreponse=<first post>`, textarea `content_form` (raw, not rendered HTML). First-post `numreponse` = `name.split('t')[1]` of the first `a[name]` on the conversation page. Cached per account. | `rf2:docs/specs/models.md:757-761`, `ADR-014:44-46` | LOT-038: prefer the edit-form source (no entity or whitespace damage). Marked **rf2-code**; the live write path is not observed, see 4.5. |
| X9 | Emoji handling undecided (Q-3); audit counts "emoji no longer stripped" as a legacy bug | HFR **truncates the message at the first code point outside the BMP** (`>= U+10000`, mostly emoji) *and still answers HTTP 200 success*; everything after is lost silently. rf2 strips non-BMP and lone surrogates from user content; for the shared MPStorage document it **refuses to post** instead. | `ContentFormSanitizer.kt:3-31,58-79`, `rf2:app/CHANGELOG.md:2414`, **rf2-live** (#114, #594) | Resolves Q-3 towards "strip or refuse, never send". LOT-048 and LOT-062. Reproduce once in Phase 2 before deciding the UX (warn vs strip). |
| X10 | Multi-quote via client cookie `quotes<a>-<b>-<c>` (`HP:72`) | redface2 never uses the cookie. It fetches one quote form per post (same endpoint, `numrep` swapped), concatenates the prefills in selection order and submits with the first form's `hash_check`. HFR never sees a multi-quote request. The feature has shipped since #291 and was dogfooded (`rf2:app/CHANGELOG.md:1556`), so topics accept several `[quotemsg]` blocks in one post (inferred, not explicitly documented as a fixture); acceptance of such a POST was **not observed live for MP** (`PH:985-987`). | `TopicReplyQuoteMaterializer.kt:1-26`, `PH:980-987` | Not a contradiction of the cookie (unverified either way), but a proven alternative that removes cookie handling. Decide in LOT-042/049; also fixes the legacy substring bug by construction. |
| X11 | `\n` is converted to `\r\n` before posting (`HP:36`) | No CRLF conversion found anywhere in rf2's write path; reads use `wholeText()`, so CRLF from the server is preserved on display only. | grep over `rf2:core` (only two read-side normalisations: `PostContentParser.kt:488`, `BbcodeContentParser.kt:406`) | **Unverified**; either HFR accepts bare LF or normalises server-side. Add to LOT-001 capture list. |
| X12 | Cookie list is only `md_user` (+ `deleted`) (`HP:78`) | `md_pass`, `md_forum` too (`PH:830-832`); REST auth documented as `md_id` / `md_user` / `md_passs` (`ADR-003:24`) | rf2 contradicts itself on names | Capture real `Set-Cookie` headers in LOT-001. |

### 4.3 Extensions: facts we do not have

| # | Topic | What redface2 documents | Evidence | Maps to |
|---|---|---|---|---|
| E1 | **REST API** | `GET /webservices/rest_api.php?uri=<URI>[&page=N&results_per_page=M]`. Endpoints: `forums/hardwarefr/categories/`, `.../categories/{cat}/subcategories/`, `.../categories/{cat}[/subcategories/{sub}]/topics/last/`, `.../categories/{cat}/topics/{id}/`, flag buckets `.../topics/{participated,read,favorites}/` per category (flat) or global (grouped by category, and truncated by recency). Auth = the normal session cookies. Verbs GET/POST/PUT; PATCH and DELETE give 501; POST/PUT need `hash_check`. HFR returns hrefs as `https://forum.hardware.fr/api/<path>`, which **404**: rewrite to `.../webservices/rest_api.php?uri=<path>`. Default page size 25. JSON lacks `views`; `total_pages` = ceil(`links.posts.count` / per-page); `last_position` is an offset, not a page; `flag_owntopic` is the strongest flag on the topic, not the bucket; `last_post_read_id` is the last read post. Names/titles may carry unescaped HTML entities. Topic content (`/posts/`) returns 500 unconditionally; MPs have no REST resource; flag mutations via REST are accepted with an error body (`error_code 501`) and change nothing. REST create-topic and reply exist and worked in tests but were deferred (no delete). | `PH:1080-1145`, `ADR-003:21-48`, **rf2-live** 2026-05-01 / 2026-05-28 / 2026-06-11; fixtures `core/data/src/test/resources/fixtures/rest_*.json` | New lot proposal (5.2) |
| E2 | `quote_only=1` | `GET forum2.php?config=hfr.inc&cat&post&numreponse&quote_only=1` returns a topic-style page containing only posts that quote the target; anonymous access works; no pagination (`page=2` repeats page 1); server de-duplicates and the list can differ from the displayed "cited N times" counter. | `PH:69` | none yet |
| E3 | Moderator alert (`modo.php`) | Open with `GET /user/modo.php?config=hfr.inc&cat&post&numreponse&page&ref=1` (build the URL from the post, do not parse the post's own link, it may be obfuscated). Six states: form, join-prompt (`cfmodoalert=1`), pending-mine, pending-joined, treated-mine, treated-joined (with date string). POST fields: `hash_check`, `referer_page` if present, then `raison` + `Submit=Valider votre message` (send) or `cfmodoalert=1` + `Submit=Confirmer` (join). Form `action` keeps its query (`ref=18`), may be relative to `/user/`. `numreponse` is unique only within a category. Alert works on locked topics. Empty reason acceptance not verified. | `PH:71-180`, **rf2-live** 2026-09-05 with two accounts, 8 fixtures | refines LOT-050; our model "`.hop` with a link means already alerted" is too coarse |
| E4 | Sanctions history | `GET /modo/historique.php?config=hfr.inc`, anonymous gets HTTP 200 with an **empty body**; table with 7 cells (poster, sanction, moderator, category, date, lifted-on, reason) | `PH:182-224` | none |
| E5 | Staff directory | `GET /message-smi-mp-aj.php?config=hfr.inc&user_id=0&responsable=1`, anonymous, HTML fragment, 64 entries with roles (Modérateur, Administrateur, Super Administrateur, Développeur, Architecte / Développeur principal); key is pseudo, no numeric id. The profile page also has a "Statut" field. | `PH:308-334` | optional |
| E6 | Mark MP unread | `GET /user/nonlu.php?config=hfr.inc&cat=prive&subcat=0&post=<thread>&page=<n>&p=1&sondage=0&owntopic=0&new=0`, no `hash_check`; unread state is binary per conversation (not per page). | `PH:903-912`, **rf2-live** 2026-06-11 | none |
| E7 | Obfuscated links, more detail | Three class prefixes: `md_noclass_cryptlink` (20 chars), `md_blank_cryptlink` (18), `md_cryptlink` (12), applied on `<span>`, not only around the "answer" image. Obfuscation is intermittent and topic-dependent; it can hit quote, edit, PV and addflag links. **URL shape depends on auth**: anonymous `message.php?...&numrep=N&ref=M`; authenticated pretty URLs `/hfr/<cat>/citer-<a>-<numreponse>-<page>-<ref>.htm`, `/hfr/<cat>/editer-<a>-<numreponse>-<page>.htm`, `repondre-...htm`. Profile links are in clear. The pager links of an authenticated MP list page 2+ are obfuscated spans too. Browser-saved fixtures run the page's JS and are misleading; capture raw bytes. Presence of the edit link is the authoritative "can edit" signal (own, not locked, not restricted); "quote" is universal and needs no link. | `PH:438-451`, `CryptlinkDecoder.kt:35-103`, `HfrSelectors.kt:99-103` | LOT-020, LOT-031, LOT-001 capture rules |
| E8 | MultiMP members | `newdest` holds the CSV of current members, prefilled **only for the owner**, in the `message.php` conversation form (not `forum2.php`); add or remove by editing the CSV in a normal reply POST; at least one member must stay; HFR inserts a "Modération" system message. Non-owners see the roster as read-only text in `th.repCase1` "Destinataires". | `PH:914-922`, `ReplyFormParser.kt:102-110` | none |
| E9 | MP quote | `GET /message.php?config=hfr.inc&cat=prive&post=<thread>&numrep=<cited>&ref=<rank in page>&page=<n>&p=1&subcat=0&sondage=0&owntopic=0&new=0#formulaire` returns a `hop` form to `bddpost.php` with `[quotemsg=...]` prefilled. `numrep` has three meanings (quick-reply: last message; plain reply: empty; quote: cited). The first "message" of page N > 1 is a "Reprise du message précédent" with `ref=0`. A page beyond the last is served as the last. | `PH:924-987`, **rf2-live** 2026-08-12/17/25 | LOT-049 for MP |
| E10 | Poll vote | `POST /user/vote.php?config=hfr.inc`. Body order: `hash_check`, hidden fields in DOM order (`cat`, `p`, `page`, `sondage`, `owntopic`, `subcat`, `numeropost`), then choices: single = `reponse=<value>`, multi = one `reponse<N>=1` per option. No `verifrequet`, **no `Referer` needed**. Success "Votre vote a bien été pris en compte !" (with meta refresh); already voted "Désolé, vous avez déjà voté !" (no refresh). Not idempotent: one POST, no retry. | `PH:340-373`, **rf2-live** | closes our "radio value semantics unverified" (HP:53) in LOT-054 |
| E11 | Poll close / create | Close: `GET /user/close_sondage.php?cat&config=hfr.inc&post=<topic>`, no `hash_check`, success "Le sondage a bien été clos", irreversible; the close link is rendered only for the owner of an open poll on every page of the topic. Create or edit a poll by **editing the first post**: `have_sondage=1`, `textreponse0` (question), `textreponse1..10`, `max_votes`, `allowvisitor`, `jour/mois/annee/heure/minute`; not available in the new-topic form. | `PH:375-401` | none |
| E12 | Global search result shapes | Four shapes: no result (`div.hop` "Désolé, aucune réponse n'a été trouvée !"), pivot-single and pivot-multi (banner + `select[name=cat]` with values `<id>*hfr.inc`, mirrored by hidden `post_cat_list` `\|1*hfr\|16*hfr\|...\|`), explicit-category listing. `forum2.php?...&page=1&numreponse=M` links on result rows always carry `page=1`; the real page comes from a server redirect. | `PH:670-695` | LOT-025/046 |
| E13 | Page resolution | `GET forum2.php?config=hfr.inc&cat&post&page=1&numreponse=M` answers **301** with a **relative** `Location: /hfr/<cat>/<sub?>/<slug>-sujet_<post>_<page>.htm#t<M>`; parse the `sujet_<post>_<page>` segment, never the path depth. An anonymous probe paginates at the server default (40), a logged-in user with another "posts per page" may land elsewhere (**unverified**). Reply success redirects (`<meta refresh>`) follow the same shape: `...-sujet_<id>_<page>.htm#bas` (reply) or `#t<numreponse>` (quote, edit). | `PH:497,668`, `rf2:HfrClient.kt:943-985` | R5 in `HP`, LOT-045 |
| E14 | Create-topic result | Success text "Votre message a été posté avec succès !", `<meta refresh>` goes to the **category listing**, not the new topic: no topic id is returned. rf2 navigates to the list and highlights the exact title. | `PH:499` | LOT-048 result model |
| E15 | Write response markers | Reply "Votre réponse a été postée avec succès !", edit "Votre message a été édité avec succès !", create "Votre message a été posté avec succès !", delete "Message effacé avec succès !"; empty body "Vous devez remplir tous les champs avant de poster ce message"; invalid token "Une erreur est survenue lors de l'envoi des données. Essayez de vider le cache de votre navigateur" (**plain text, about 99 bytes, no HTML envelope**, `ReplySubmitResponseParser.kt:29-35`); **flood: "Afin de prevenir les tentatives de flood, vous ne pouvez poster plus de 3 réponses consécutives dans un intervalle de 10 minutes"** (no accent on "prevenir" in the post-flow capture, whereas the login flood marker has "prévenir"); locked "Désolé ce sujet a été fermé...". rf2 matches substrings on the visible text (and matches the flood rule on the accent-free tail). | `PH:484-514`, `rf2:ReplySubmitResponseParser.kt:29-80,117-143`, **rf2-live** 2026-05-17 | LOT-037; answers audit D 10-4 (flood wording) |
| E16 | Locked topics | A locked topic's page shows no reply link, but a hand-built `message.php` URL still serves a composer; only the POST is refused. Presence of the form is not proof of postability. Anonymous `message.php` serves a composer with visible `pseudo`/`password` fields. | `PH:512-514` | LOT-036 |
| E17 | `subcat=0` | A valid, postable value for categories without sub-categories (e.g. cat 32); `-1` is rf2's own "unknown" sentinel. Read `subcat` from the write form's input, not from the quick-search widget that has the same field name. | `PH:434` | LOT-036 |
| E18 | `numreponse` scope | Unique per category, not globally; the triplet (cat, topic, numreponse) is unique. Use a composite key in any store. | `PH:644-666` | LOT-010/011 key design |
| E19 | Posts per page | A user setting (`editprofil.php?page=3`), not constant 40. REST page size is independent. Topic meta description carries `Pages : N`; absent means unknown (sentinel). | `PH:1070-1076`, `models.md:767` | LOT-033 |
| E20 | Post DOM details | Ads ("Publicité" blocks) look like posts (same `icon1.gif`, `alt="mood"`) but lack `a[name^=t]`: drop them. Tone icon = `td.messCase1 div.right a[href^=#t] img` with `/icones/message/iconN.gif` (1 = default, values above 16 exist). Edit trailer `div.edited` may hold "Message cité N fois" with or without "Message édité par X le <date>". Deleted/moderated posts collapse to author bar plus a notice. Citation header link has two forms: anonymous static permalink, authenticated `forum2.php?...&numreponse=0&...#t<id>`; **only the fragment `#t<id>` identifies the cited post** (query `numreponse` is 0 on topics). Block tables: `table.citation`/`oldcitation`, `quote`/`oldquote`, `spoiler`, `fixed`, `code` (nest freely). Signature in `span.signature`. | `PH:1006-1064`, `HfrSelectors.kt:13-30`, `PostContentParser.kt:296-348` | LOT-030/031/032/034 |
| E21 | MP list DOM | Row `tr.sujet`; cells `td.sujetCase1` (icon `closedbp.gif` = unread, `closedp.gif` = read), `td.sujetCase3 a.cCatTopic` (subject, `post=` id), `td.sujetCase4` (last-page link, absent for one page), `td.sujetCase6` (correspondent link, or a `span` "Interlocuteurs multiples" for group MP, or a bare span for a non-clickable pseudo), `td.sujetCase9 a` (date). Pager `tr.fondForum1PagesHaut .left`: current page in `b`, others `a.cHeader`, **obfuscated spans on authenticated pages 2+**. | `PrivateMessageListParser.kt:17-19,70-99,135-145`, `HfrSelectors.kt:82-103` | LOT-023 (the "3 legacy variants") |
| E22 | Smileys | Builtin base `https://forum-images.hardware.fr/icones/` (`smilies/jap.gif`), perso `.../images/perso/<user_id>/...` (paths may hold numbered sub-folders and spaces: use the `src` as given). `message-smi-mp-aj.php?config=hfr.inc&user_id=<uid>&findsmilies=<q>` returns a fragment of `<img alt="[:token]" onclick=putSmiley(...)>`; `user_id` comes from `find_smilies_timer('hfr.inc', N)` in the form; duplicates occur, tokens contain spaces, underscores, dashes, `:N` suffixes. A crawl found 34,139 perso smileys, most 50 px high. | `PH:753-820` | LOT-053, LOT-034 |
| E23 | MPStorage envelope in the wild | Real document: `{"data":[{"version":"0.1","mpFlags":{"list":[...],"active":true},"blacklist":{},"hfrChat":{},"superFavs":{},"hfr4k":{},"egoQuote":{},"egoPost":{},"lastRead":{},"ezzziDrap":{},"fastDelete":{},"fastValid":{},"catMP":{},"oemMP":{},"sourceName":"DTCloud_GM","lastUpdate":<ms>}],"sourceName":"DTCloud_GM","lastUpdate":<ms>}`: 13+ namespaces written by different userscripts; `sourceName`/`lastUpdate` belong to the **last writer**, duplicated at root and in the v0.1 entry. `mpFlags` = **read position** of group conversations (DTCloud), not read/unread. No "MPStorage2" exists in `XaaT/hfr-redkit` (empty). A validity check must not treat a missing `data`/`lastUpdate` as "reset to default" (the original library does, destructively). | `models.md:705-724`, `ADR-014:26-35,79` | LOT-062: preserve unknown keys verbatim, never reset |
| E24 | MPStorage write contract | Fields for the `bdd.php?config=hfr.inc` POST (`cat=prive`): `hash_check`, `verifrequet=1100`, `content_form`, `numreponse`, `post`, `pseudo`, `sujet` (always the constant hash, with a guard that refuses if the form's subject differs), `delete` never sent. Cap 64 KiB (`MAX_CONTENT_FORM_BYTES`), HFR truncates silently beyond its limit (limit itself never observed). Update-only mode never creates entries. Verify by re-reading; restore only on real corruption. **Contract "not observed live"** in the spec (`PH:991`). | `rf2:DefaultMpStorageRepository.kt:433-476`, `MpStorageRepository.kt:92-100`, `PH:989-1000` | LOT-052; see 4.5 caveat |
| E25 | Prefetch / read marking | Any authenticated request to a topic page marks flags read. Prefetch anonymously (cookie-less client). MP exception: opening a conversation clears the dot; the MP list GET is inert; no server read position exists for MP. | `PH:858-912` | LOT-045, LOT-068 |
| E26 | Outbound headers | Custom User-Agent works. `vote.php` works **without Referer**. `reho.st` image host returns 403 without `Referer: https://forum.hardware.fr/` and 200 with empty body for unknown ids. Some image hosts are http-only; the HFR session client refuses https-to-http redirects, a separate cookie-less client handles images. | `HfrConstants.kt:9`, `PH:349-351`, `images.md:188-192` | closes HP:86 "unverified" for UA/Referer |
| E27 | Encoding | All genuine HFR captures in rf2's fixtures declare `<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">` (139 such meta tags across the captured pages; the only `iso-8859-1` hits, 5 files, are rf2's own MPStorage inbox fixtures under `core/data/.../fixtures/mp_storage_*`, which carry no provenance sidecar and look synthetic, **unverified**). rf2 decodes with OkHttp's `body.string()` (honours Content-Type charset, else UTF-8) and posts `FormBody.Builder(Charsets.UTF_8)`. OkHttp's form content type carries no charset parameter (library behaviour, not stated in the repo) and HFR accepts it. | `grep` over `core/*/src/test/resources/fixtures`, `HfrClient.kt:442`, `DefaultReplyRepository.kt:234` | Strong evidence for Q-2: **UTF-8 in and out**; still capture raw bytes + headers in LOT-001 to be sure |
| E28 | `transsearch.php` | Requires a non-empty `hash_check` (auth only). Fields: `hash_check`, `post`, `cat`, `config`, `p=1`, `sondage=0`, `owntopic`, `word`, `spseudo`, `filter=1` only when "matches only" (absent is not 0), `dep=0` + `firstnum` only on a **fresh** search, `currentnum` (empty on fresh, previous match's `numreponse` when stepping). **Re-sending `firstnum` on a step makes HFR re-anchor on the first match and the cursor never advances.** Forward only; previous = client-side history. Response is a normal topic page positioned on the match; absence of the cursor among the page's posts marks the end. "No result" is a normal answer (also for words that hit MyISAM's 50% rule). | `PH:697-708`, `HfrClient.kt:717-763`, **rf2-live** (#546, #894) | LOT-046. Consistent with our "do not follow redirects, read `Location`" if HFR redirects; rf2's client follows the redirect (unverified). |
| E29 | Session / rate limits | HFR sends no `Retry-After`; thresholds are empirical (see 1.4). Signed-out detection and re-login are explicit; no replay of POSTs (mutation client disables connection retry). | `PH:848-854`, `NetworkModule.kt:56-63` | LOT-040, LOT-044 |
| E30 | `listenumreponse` | Every topic page embeds a JS array `listenumreponse[i] = <numreponse>` of the page's posts. Documented as an opportunity; **not used** by rf2 code (grep finds no consumer). | `PH:712-741` | optional cross-check for LOT-030 |

### 4.4 Divergences to settle with our own fixtures

These cannot be decided from reading either code base. Add them to the LOT-001 capture checklist.

1. First-post delete (X1) and what the page looks like for a non-owner.
2. `[quotemsg]` argument meaning for topic pages (second value) (X2).
3. Checkbox/option semantics and CRLF acceptance (X3, X11).
4. Login success signal and exact cookie set from `Set-Cookie` (X5, X12).
5. Global search: `config=hfr.inc` vs `hardwarefr.inc`, GET without session, result page size (X7).
6. MPStorage read path: edit-form textarea vs rendered `<p>`; behaviour of the `[non lu] ` prefix on the subject in the MP list when the storage MP is unread (our `HP:62`; rf2 matches subject equality only, `MpStorageRepository.kt:42`).
7. MP unread count: home-page `.cCatTopic.red` (ours, `HP:20`) versus counting `closedbp.gif` rows in the MP list (rf2, `PrivateMessageListParser.kt:33-39`). rf2 dropped its home-footer count (`rf2:docs/specs/mvi.md:187`). Also check whether an authenticated GET of `/` marks flags read before using it for background polling.
8. Intra-topic search: redirect `Location` versus followed redirect (E28).
9. `editprofil.php` path: `/user/editprofil.php` (ours, `HP:18`) versus `/editprofil.php` (theirs, `PH:59`).
10. Whether `addflag`/`delflag` need the `ref`, `page`, `p` parameters (rf2 sends them; `numreponse` is optional for delete only).

### 4.5 Reliability caveats about redface2's own documentation

- **Internal contradictions**: MPStorage write cap is 64 KiB in code and `PH:995`, but "256 KiB" in `known-issues.md:57`; that same line says the write contract was "validated live" while `PH:991`, `ADR-014:51,61` and the code comments say it was **never observed live**. Cookie names differ between `PH:830-832` and `ADR-003:24`. "22 categories" (`scope.md:50`) versus "19 public" REST categories (`PH:1092`). Treat the more conservative statement as true.
- **Mostly single-account evidence**: the live captures use two maintainer-owned test accounts (XaTelitte, XaTriX), so behaviours that depend on roles, bans, restrictions or posts-per-page settings are thinly covered.
- **Dated evidence**: live checks span 2026-05 to 2026-09; HFR can change (the project already hit one cryptlink change).
- **Parts of `protocol-hfr.md` are stale**: the `cryptlink` section says external URLs are *not* decoded (`PH:745-749`), contradicting `PH:438-451` and the shipped decoder; `listenumreponse` is recommended (`PH:712-741`) but no code uses it. The code and the ADR addenda win when they differ.

---

## 5. Convergence

### 5.1 Licensing: what may be reused

| | redface2 | SwiftHFR |
|---|---|---|
| License | **GPL-3.0-only** (`rf2:LICENSE`, `README.md:66`, ADR-010) | **PolyForm Noncommercial 1.0.0** (`LICENSE`, ADR 0003) |
| Scope | Code, plus "specification files" of the repo (`rf2:docs/guides/contributing.md:218-222`); no separate documentation license found | Own code and docs |
| Third-party assets | Redface v1 icon under Apache-2.0 credited in `rf2:app/THIRD_PARTY_NOTICES.md` | SwiftSoup (MIT) |

**Analysis (not legal advice).**

1. **Code copying is not compatible.** A work derived from GPL-3.0 code must be conveyed under GPL-3.0 as a whole, and GPL-3.0 section 10 forbids adding further restrictions. PolyForm Noncommercial restricts commercial use, so it is not a GPL-compatible license. Therefore **no redface2 source (Kotlin) may be pasted into SwiftHFR, and a close line-by-line Swift translation should be treated as a derivative work too.** The reverse also holds: GPL redface2 cannot take our PolyForm-only code or text.
2. Relicensing SwiftHFR to GPL would remove the noncommercial restriction we chose in ADR 0003, and redface2's own ADR-010 notes that App Store distribution under the GPL is "not a compatible goal" (`ADR-010:42`). Not recommended.
3. **Facts are free, expression is not.** Endpoint paths, field names, constants, CSS class names, marker sentences, wire formats and behaviours are functional facts about HFR, not redface2's expression. We may learn them, then verify and write them in our own words and structure. Avoid copying their tables or prose verbatim and avoid mirroring their document structure. I have now read their code and spec in detail, so a strict clean-room claim is no longer available; the safeguard is independent verification on our fixtures and independent wording.
4. **Algorithms with independent provenance are safe**: the cryptlink alphabet exists in HFR's own `common.js` and in our legacy code (`RangeOfCharacters.m:92-114`).
5. **Fixtures**: do not import theirs. They are GPL-covered captures of third-party forum content (real members' posts; sanitization removes `hash_check`, cookies, e-mail but not necessarily pseudos), which would also break our `FIXTURES.md` anonymization rule. We need our own captures anyway (LOT-001). Running our parsers locally against their fixtures is only an option if their maintainer agrees or their fixtures carry terms that allow it, since they contain third-party forum content; ask first, never commit or redistribute them; I have not verified this against any file-level terms and recommend asking first.
6. **Authorship caveat**: much of their code is agent-written (324 commits with Claude trailers). Copyrightability of fully generated code is unsettled, but their stated license and our caution do not depend on it.
7. **Symmetry**: redface2 applies the same rule to the iOS lineage ("no LICENSE means no borrowing", `rf2:docs/guides/references.md:179-195`, which lists `ezzz/HFRnow` as unlicensed). Our `CREDITS.md` says legacy code is reused with gratitude. Worth stating our own provenance position explicitly, but outside this note's scope.
8. **Practical path to more**: ask the maintainer ("Clement XaT", via GitHub issue or the HFR beta topic) for an explicit permission or a CC-BY-4.0 / CC0 grant for the protocol-spec text and for specific fixtures. Nothing in this note was posted anywhere.

### 5.2 Worth reusing (ideas, not code), in priority order

1. **REST API for browsing** (E1). Proposed new lot in `HFRNetwork` + `HFRModels`: typed client, HATEOAS rewrite, DTOs, with HTML parsers as the fallback already planned (LOT-021/022/024). Benefits: category table without a static id list (replaces much of LOT-014), flag lists and last-read ids with one small call per category, topic metadata at 1 KB. Risk: undocumented and could vanish (ADR-003 itself keeps HTML as fallback by domain); needs authenticated fixtures (LOT-001 extension).
2. **Anonymous vs authenticated client split and the prefetch rule** (E25, E26). Add as a requirement to LOT-042 (two session types: with and without cookies) and to LOT-045/068.
3. **Write-side hardening**: sanitize/refuse non-BMP (X9), `verifrequet` and browser-style form submission (X3, X4), response-marker table and no-retry for non-idempotent POSTs (E15, E10), "owner can delete topic" (X1). Feeds LOT-036/037/048 and resolves Q-3.
4. **MPStorage discipline** (E23, E24, C9): inbox scan, cached location, edit-form read, unknown-key preservation, update-only and verify-after-write, fail closed on non-BMP, never repair a malformed document. Feeds LOT-038/052/062 and the Q-6 merge semantics.
5. **Image-loading quirks** (E26): Referer for reho.st, https upgrade, dedicated cookie-less image client, tolerance for empty 200 bodies. Plus the **upload options**: Diberie needs no key, Imgur takes a user-supplied Client-ID (`ImgurProvider.kt:26-32`). Either removes the need to reuse the hard-coded legacy key; update ADR 0007's alternatives (it currently lists only user-supplied key for Giphy).
6. **Capture checklist**: their fixture catalogue (reply/quote/edit/delete forms and responses, flood, invalid token, locked topic, anonymous composer, search shapes, poll vote, moderation states, MP list variants, DT forms, REST samples) is a ready-made case list for LOT-001/`FIXTURES.md`, each with `Source / Captured / URL / Notes / Sanitization / Test context` sidecars. Reuse the *schema of the sidecar* and the case list, capture our own bytes.
7. **Process guards**: CI check that every fixture has provenance; a parity matrix when two surfaces (topic and MP) share logic; docs-consistency tests. Adopt as lessons in `docs/agents/LESSONS.md`.

### 5.3 What could be shared between the two projects

1. **A neutral HFR protocol spec** (endpoints, forms, markers, cookies, quirks), license CC-BY-4.0 or CC0, with a status column per fact (`code` / `verified@date@fixture`). Both documents are already organised as endpoint tables; merge them, deduplicate, and add a "conflicts" table seeded from Section 4.2. Home: a separate repo or the `ForumHFR` org, so neither GPL nor PolyForm applies to the text.
2. **A shared fixture sidecar schema and sanitizer rules**, plus a common checklist of cases to capture. Fixtures themselves stay per project (privacy, license). Optionally a shared, strongly sanitized "public pages only" set under a clear license if the maintainer agrees.
3. **MPStorage v0.1 compatibility contract**: JSON Schema for the envelope, a registry of known namespaces (DTCloud `mpFlags`, HFR4K, `superFavs`, `egoQuote`... plus our `blacklist` and `bookmarks`), and merge rules (preserve unknown keys, last-writer metadata, size cap, update-only, verify-after-write, no destructive reset). Natural co-owners: `XaaT/hfr-redkit`, Wiripse, both clients. This also settles our open Q-6.
4. **Cross-implementation conformance**: a small JSON "expected output" per fixture for the shared pages (topic list, MP list, flags, poll, profile). Each project can then check its parser against the other's on fixtures each is licensed to hold.
5. **A "known quirks" page** that both link to (non-BMP truncation, reho.st Referer, `ref=0` recap message, page clamping, empty-body anonymous sanctions page, `numreponse=0` in authenticated citation hrefs).
6. **Coordination on live probing**: a shared policy for test accounts and for not hammering the forum (their empirical limits in 1.4).

### 5.4 What we could contribute back

1. **iOS-lineage knowledge**: AQ endpoints and RSS (`aq.super-h.fr`, `HP:93`), MPStorage `blacklist` and `bookmarks` shapes (`audit E:103-108`), which their blacklist could adopt for cross-client sync, and our bulk favourite removal contract (`manageaction.php`: `hash_check, topic1=-1, topic_statusno1=-1, action_reaction=message_forum_delflags, type_page=forum1f, topic0, valuecat0, valueforum0=hardwarefr`, `HP:57`), which they list as out of scope (`PH:258`). All **ours-code**, to be re-verified before offering.
2. **Evidence they lack**: how the multi-quote cookie behaves, how the iOS lineage handled emoji before it stopped stripping them (audit "Visible bugs"), and the rest of that legacy quirks catalogue.
3. **Methodology**: differential testing against a legacy oracle (ADR 0004), Linux-testable engine boundaries.
4. **Review**: a PR or issue against their `protocol-hfr.md` once we hold fixtures, correcting stale or contradictory lines (4.5), written under a license they can accept (new text we author can be offered under GPL or CC0; do not paste our PolyForm-only text).

### 5.5 Suggested actions (proposals, none executed)

| Action | Where | Depends on |
|---|---|---|
| Add Section 4.4 items to the LOT-001 capture list and to `FIXTURES.md` | `docs/FIXTURES.md` | none |
| Draft a lot for a REST browsing client (spike: categories + flag buckets, authenticated fixtures) | `docs/LOTS.md` | LOT-040/042 |
| Amend `HFR-PROTOCOL.md` after fixtures confirm: X1-X4, X6, E3, E6, E10, E13-E15, E25-E27 | `docs/HFR-PROTOCOL.md` | LOT-001 |
| Decide Q-3 as "strip or refuse non-BMP, warn the user" pending a Phase 2 repro; Q-2 as "UTF-8" pending raw capture | `docs/audit/README.md` decision table | LOT-001 |
| Add "anonymous client for prefetch" and "no retry on non-idempotent POST" to LOT-042/045/048 specs | `docs/LOTS.md` | none |
| Add a requirement for image loading (Referer, https upgrade) to the Phase 4 image lot (E-8) | `docs/LOTS.md` Phase 4 backlog | none |
| Update ADR 0007 with the key-free upload alternatives | `docs/adr/0007-third-party-api-keys.md` | maintainer decision |
| Ask the redface2 maintainer about a CC-BY/CC0 grant for protocol text and about a shared MPStorage contract | outside the repo; maintainer's call | none |

---

## Appendix A. Key redface2 files worth reading again

| Topic | Path |
|---|---|
| Protocol spec (primary source) | `docs/specs/protocol-hfr.md` |
| REST decision | `docs/adr/003-api-rest-hfr-hybride.md` |
| MPStorage decision and model | `docs/adr/014-mpstorage-v01-de-facto.md`, `docs/specs/models.md:701-761` |
| Login | `core/network/src/main/kotlin/fr/forumhfr/redface2/core/network/auth/AuthRemoteDataSource.kt` |
| Transport, search, flags | `core/network/.../HfrClient.kt`, `HfrApiClient.kt`, `di/NetworkModule.kt` |
| Form parsing and POST building | `core/parser/.../write/ReplyFormParser.kt`, `core/data/.../write/DefaultReplyRepository.kt` |
| Response classification | `core/parser/.../write/ReplySubmitResponseParser.kt` |
| Cryptlink | `core/parser/.../CryptlinkDecoder.kt` |
| HTML selectors | `core/parser/.../common/HfrSelectors.kt` |
| Non-BMP sanitizer | `core/data/.../write/ContentFormSanitizer.kt` |
| MPStorage client | `core/data/.../mpstorage/DefaultMpStorageRepository.kt`, `MpStorageEnvelopeWriter.kt` |
| Image host rules | `docs/specs/images.md:188-192` |
| Fixtures | `core/parser/src/test/resources/fixtures/`, `core/data/src/test/resources/fixtures/` |
| Known limits | `docs/guides/known-issues.md` |

## Appendix B. Method

`git clone --depth 50` of the repository, `git ls-remote --heads` to rule out `gh-pages`, `git fetch origin dev --depth 50`, then read the docs, ADRs, selected code and fixture metadata listed above and counted files and commits locally. No request was made to forum.hardware.fr or to `*.github.io`, nothing was posted on GitHub, and no repository other than this file was modified.
