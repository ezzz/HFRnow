# Bybifok's proposals — review and credit

Proposals, findings and prototype of **Bybifok** (GitHub [`moust4ki`](https://github.com/moust4ki)), credited to Bybifok wherever they are used. Research record (reference material): the live backlog is [FEATURES.md](../FEATURES.md), the bugs to fix are issues [#102](https://github.com/ezzz/HFRnow/issues/102)–[#108](https://github.com/ezzz/HFRnow/issues/108).
Reviewed 2026-10-26 from Bybifok's proposal message, PRs [ezzz/HFRnow#3](https://github.com/ezzz/HFRnow/pull/3)–[#6](https://github.com/ezzz/HFRnow/pull/6) and prototype [moust4ki/ultra-hfr](https://github.com/moust4ki/ultra-hfr). Everything below stays credited to Bybifok, whoever implements it.

## 1. What is already in the shared docs, with credit

- **Protocol facts** Bybifok found (B1–B10) and **feasibility questions** (B11–B15): [HFR-PROTOCOL.md §7b](../HFR-PROTOCOL.md#7b-reported-by-bybifok-to-verify-with-our-fixtures) ([ezzz/HFRnow#11](https://github.com/ezzz/HFRnow/pull/11)). Settle one with a captured, anonymized page (`docs/FIXTURES.md`): high value, it unblocks lots.
- **Contribution model**: [ADR 0011](../adr/0011-contribution-model-and-feature-intake.md) — fork, PR into `dev-swift`, idea → spec → lots → PR; no human approval required: the author merges once the [merge criteria](../../CONTRIBUTING.md#2-merge-criteria) hold, including a review by a different model.
- **Real legacy bugs** from PR #3, as SwiftHFR work to claim (§7): one issue each, [#102](https://github.com/ezzz/HFRnow/issues/102)–[#108](https://github.com/ezzz/HFRnow/issues/108) (label `moust4ki aka bybifok finding`).

## 2. Features to spec (FEAT-001…021)

Spec one at a time in `docs/features/FEAT-XXX.md` on `dev-swift`: what and why, screens and states (light, dark, Dynamic Type XL, iPad), HFR facts with their source, edge cases, engine lots needed (`docs/LOTS.md`), legacy settings kept. Attach the design boards to the feature spec (or its issue). Start with the `high` ones whose engine lots are done or close (FEAT-002, 001, 006, 008, 007, 009). App code waits for the app target (LOT-080) and the lots each feature needs.

The list, with engine dependencies, open questions, priority and status, is the backlog [FEATURES.md](../FEATURES.md) (single source).

## 2b. Ideas and UX we did not have (source of each feature)

| Idea | Where Bybifok showed it | Feature |
|---|---|---|
| Home / "À suivre": everything new on one screen, resume reading | message; ultra-hfr "Le Fil" (`UltraHFR/Feed/`) | FEAT-001 |
| Page navigator from the title (±5, blocks of 50) | message; PR #6 | FEAT-002 |
| Honest list paging ("Page N", "Dernière page" disabled) | PR #3 | FEAT-003 |
| Page scrubber with first-unread dot and haptics | message; ultra-hfr `Reader/PageScrubber.swift` | FEAT-004 |
| Serverless notifications through a Shortcuts App Intent | message | FEAT-005 |
| Quote tray with count, topic order, emptied after send; draft + quotes merge | message; ultra-hfr `Reader/QuoteTray.swift` | FEAT-006 |
| Same swipes in every list, "Lu" with "Annuler" | message; PR #6 ("Dernière page" swipe) | FEAT-008 |
| Session expiry sheet keeping the draft | message | FEAT-009 |
| Darker dark, OLED, 1 pt separators, one-line header, single accent, live preview in settings, smiley scale, avatar colour from the pseudo | message; PRs #5–#6; ultra-hfr `HFRDesign` | FEAT-010 |
| Emoji refused with a smiley suggestion | message | FEAT-012 |
| Exact BBCode preview | ultra-hfr `HFRContent` (`BBCodeParser`, `BBCodeWriter`) | FEAT-013 |
| State restoration on fold / multi-window; iPhone Duo two columns and rail | message; PR #4; ultra-hfr `RootLayout` | FEAT-015, FEAT-016 |
| Continuous reading with at most 10 pages in memory | ultra-hfr | FEAT-017 |
| iPad keyboard shortcuts, Spotlight for read topics | ultra-hfr | FEAT-021 |
| Search help when a word is shorter than 4 letters; refresh that stays on the current page; pull to refresh on categories; "Connexion requise" alert; active-filter summary with "Tout afficher"; categories grouped by family | PR #3, PR #6 | Phase 4 details |
| Design document: colour tokens, 4.5:1 contrast targets | PR #5 | Phase 5 design input |

## 3. Engineering patterns worth porting (through our lots)

| Pattern | ultra-hfr source | Target |
|---|---|---|
| At most 2 concurrent requests to HFR, identifiable User-Agent | `HFRKit` client (actor + limiter) | LOT-040 / LOT-045 |
| Parsing off the client actor (`@concurrent`) | `HFRKit` | LOT-045 |
| Prefetched pages fetched **without** session, current page reloaded with session (flags never advanced behind the reader) — same principle as our LOT-045 | decision D6 | LOT-045, FEAT-017 |
| Reading position that only moves forward; "since your visit of …" | decisions D8–D9 | new reading-position store (FEAT-001, FEAT-015) |
| Message content as a typed tree rendered to our own HTML, everything escaped | decision D5, `HFRContent`, `HFRReader` | input for the ADR to take before LOT-034 (revisits ADR 0006 option 1) |
| Reader tests with a stub `URLProtocol` and a fake page driver | `UltraHFRTests` | Phase 4 test strategy |
| Feed refresh at most every 2 minutes when logged in | decision D11 | FEAT-001, FEAT-005 |

## 4. Protocol facts

Moved to [HFR-PROTOCOL.md §7b](../HFR-PROTOCOL.md#7b-reported-by-bybifok-to-verify-with-our-fixtures) (B1–B10, B11–B15) with credit. Not kept: the `[quotemsg=numreponse,page,0]` format — our captures (`R41a`, `R41b`, `R47a`) show `numreponse,ref,<quoted member id>`; the empty smiley-search result — our `R53c` shows a "Désolé…" text.

## 5. Legacy features the proposals do not mention

"All current functions" stay in scope. Checked in the legacy code; none may disappear silently:
multi-account · blacklist and whitelist · MPStorage sync · bookmarks · post filter · MP actions (new MP, mark unread, delete) · new topic, edit and delete own posts · moderator alert · AQ creation · poll vote and poll draft · archived drafts · "+" button modes · Giphy · automatic background MP check (BGTask) — FEAT-005 adds to it, does not replace it · **account deletion** (App Store 5.1.1(v)) · start-screen and favourites-mode settings · multi-window · the legacy "swipe changes page" setting (on by default; the proposal removes the gesture — keep the setting, default to be decided).

## 6. Claims checked

| Claim | Verdict |
|---|---|
| HFR gives no total page count in topic lists | 🟠 True for the list pager, false for each topic (row `sujetCase4`): HFR-PROTOCOL §7b B1 (`R04`, `R05a`, `R05b`) |
| No universal links: the site publishes no `apple-app-site-association` | 🔴 False: the AASA exists (old format) and names the legacy App ID `QMG83DG7YP.hfrplus.red.super` (checked live 2026-10-26, not captured yet: Capture backlog in LOTS.md). Universal links work for a release under that App ID (Q-1), not for a third-party app |
| HFR cuts a message at the first emoji | 🟢 At the first non-BMP character (HFR-PROTOCOL §6 and §7b B13, `W12`); BMP emoji untested |
| Upload deletion on reho.st | 🔴 No delete API evidenced for guest uploads: the legacy rehost client only uploads (HFR-PROTOCOL §7b B12 and §8; LOT-056); not captured |
| No instant push | 🟢 The legacy app polls the MP count in the background (audit NET-13, LOT-047); no push service in the legacy code |

## 7. Bybifok's PRs on `ezzz/HFRnow:master` (#3–#6)

They target the **shipped Objective-C app**, not SwiftHFR: merging them is ezzz's decision. Our review (static only, no build possible on Linux; no CI ran on them; all start from tag `4.0`, 43 commits behind `master`):

| PR | Content | Verdict |
|---|---|---|
| #3 Bug fixes | real legacy bugs (nil crash in list parsers, pager index, `liste_sujet` paging, AQ entities, bookmarks open page 1, list jump on refresh) | 🟠 Cherry-pick: `237db70`, `a817498`, `9935b98`, `dc93420` apply cleanly. Blockers: a committed `Carthage/Build` symlink to the author's machine; "Link"→"Lien" breaks `MessagePopupMenuPolicyTests.swift:48,128`; a nil image `src` can mark a flag "red" |
| #4 iPhone Duo | Duo inner/outer screens, workarounds for iOS 27.1 freezes, `displayScale` instead of `UIScreen.main` | 🟠 Keep the workarounds; `b1f07e2` removes `TabBarReselectionObserver` and conflicts with `c1e1424` |
| #5 "Natif calme" reskin | ~95 % visual, +2.5 k lines, no tests | 🔴 Not as is: `[code]` blocks lose monospace (`!important` rule), user accent colours overwritten, brightness/tint settings removed (just restored on `master`), fixed font sizes |
| #6 Sidebar, page menu, single colour | replaces the iPad split navigation just finished on `master` (HFR-006) | 🔴 Not as is: custom back-gesture delegate makes other gestures fail, `onAppear` counter can drift, filter summary counts only the current page |

Fixes from #3 are also **non-regression tests to write** in SwiftHFR (LOT-022, 025, 041, 046).

**Backport to `master`** (the shipped app) is Bybifok's call with ezzz: the cherry-pickable commits of #3 are listed above.
**In SwiftHFR**, the real bugs of #3 are issues [#102](https://github.com/ezzz/HFRnow/issues/102)–[#108](https://github.com/ezzz/HFRnow/issues/108), in this order:

| Legacy commit | SwiftHFR work | Area | Lot |
|---|---|---|---|
| `237db70` | Topic-list pager: a link without `href` must not break the parser (test + fix) | parsing | LOT-022, 021 |
| `a817498` | Topic-list page N must really load page N (`liste_sujet` paging) | network | LOT-041 |
| `dc93420` | No fake total page count from the windowed pager | parsing | LOT-022 |
| `a817498` | AQ RSS: decode HTML entities in titles, authors, comments | parsing | LOT-028 (needs the AQ capture) |
| `246a9c7` | Links to a post (AQ, bookmarks) open its page and `#t` anchor, not page 1 | app | LOT-020, 045, 083 |
| `246a9c7` | Refresh reloads the current page and keeps content meanwhile | app | LOT-082, 083 |
| `be196f8` | A cancelled topic request never completes the next load; show at `DOMContentLoaded` | app | LOT-083 |

## 8. Licence

ultra-hfr is MPL-2.0 (file-level copyleft); SwiftHFR is PolyForm Noncommercial. Copied files would stay MPL-2.0. Preferred path: ideas and facts are ported through our lots with credit; code submitted by PR is contributed under this project's licence (CONTRIBUTING.md on `dev-swift`). Any wholesale import needs an ADR amending ADR 0003.

## 9. Prompt for a contributor's agent

```text
You work on SwiftHFR, a native iOS client for forum.hardware.fr.
Repository: https://github.com/ezzz/HFRnow — branch dev-swift ONLY. The default branch master is the legacy app:
never branch from it, never target it, and ignore its CLAUDE.md.

Setup:
1. Fork ezzz/HFRnow, clone your fork, then: git fetch origin dev-swift && git switch dev-swift
2. Read and follow, in this order: AGENTS.md, docs/adr/0011-contribution-model-and-feature-intake.md,
   docs/HFR-PROTOCOL.md (§7b lists the facts I reported), docs/FIXTURES.md, docs/LOTS.md.
3. Read docs/FEATURES.md (my features FEAT-001…021) and docs/research/bybifok-proposals.md (my PRs #3–#6, the bugs to fix).
4. Create every branch from dev-swift, open every PR against dev-swift on ezzz/HFRnow.

Task: <ONE item: "spec FEAT-002 page navigator", "settle fact B2 with a capture", "issue: <title>">.

Rules:
- One item per PR, claimed first on its issue with a /claim comment; the PR says Closes #N and Claim: <id>. Credit me (Bybifok) in the PR.
- Never guess how HFR behaves: every URL, form field, cookie or selector comes from the legacy code (master) or a captured page.
  If it is not documented, stop and tell me what to capture.
- Captured pages are anonymized (docs/FIXTURES.md) and checked by someone else before any push. No secrets, cookies or real pseudos.
- Spec: docs/features/FEAT-XXX.md with screens and states, HFR facts with their source, edge cases, engine lots needed, legacy settings kept.
- Code: tests first (Swift Testing), view logic in testable view models, AGENTS.md §4 conventions, AGENTS.md §9 definition of done.
- Before opening the PR, self-review against docs/agents/LESSONS.md and name the model that wrote it.
- Then ask a second agent, on a different model, to review the diff adversarially; fix every finding.
- No human approval is required (ADR 0011): merge only once every merge criterion holds (CONTRIBUTING.md §2:
  required checks green, no conflict, every conversation answered and resolved, definition of done met).
```
