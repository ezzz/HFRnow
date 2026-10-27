# Bybifok's proposals — what we keep, with credit

Author: **Bybifok** (GitHub [`moust4ki`](https://github.com/moust4ki)). Reviewed 2026-10-26 (cloud session, read-only on Bybifok's repositories).
Sources: the proposal message (feature list, design boards on Imgur — not readable from cloud sessions, to attach to the issues), PRs [ezzz/HFRnow#3](https://github.com/ezzz/HFRnow/pull/3), [#4](https://github.com/ezzz/HFRnow/pull/4), [#5](https://github.com/ezzz/HFRnow/pull/5), [#6](https://github.com/ezzz/HFRnow/pull/6), and prototype [moust4ki/ultra-hfr](https://github.com/moust4ki/ultra-hfr) (MPL-2.0, ~16.7 k lines of Swift, 198 tests).

This page exists so that Bybifok's work is not lost and not taken from them: every item below is credited to Bybifok wherever it is implemented, and Bybifok is welcome to implement it through [COLLABORATION §3](../COLLABORATION.md#3-from-an-idea-to-a-merged-feature). Features are tracked in [FEATURES.md](../FEATURES.md) (FEAT-001…021). What to dig first, and a prompt to start an agent on it: [bybifok-next-steps.md](bybifok-next-steps.md).

## 1. Ideas and UX we did not have

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

## 2. Engineering patterns worth porting (through our lots)

| Pattern | ultra-hfr source | Target |
|---|---|---|
| At most 2 concurrent requests to HFR, identifiable User-Agent | `HFRKit` client (actor + limiter) | LOT-040 / LOT-045 |
| Parsing off the client actor (`@concurrent`) | `HFRKit` | LOT-045 |
| Prefetched pages fetched **without** session, current page reloaded with session (flags never advanced behind the reader) — same principle as our LOT-045 | decision D6 | LOT-045, FEAT-017 |
| Reading position that only moves forward; "since your visit of …" | decisions D8–D9 | new reading-position store (FEAT-001, FEAT-015) |
| Message content as a typed tree rendered to our own HTML, everything escaped | decision D5, `HFRContent`, `HFRReader` | input for the ADR to take before LOT-034 (revisits ADR 0006 option 1) |
| Reader tests with a stub `URLProtocol` and a fake page driver | `UltraHFRTests` | Phase 4 test strategy |
| Feed refresh at most every 2 minutes when logged in | decision D11 | FEAT-001, FEAT-005 |

## 3. HFR protocol facts Bybifok found

To be **captured as fixtures** before they enter [HFR-PROTOCOL.md](../HFR-PROTOCOL.md) ([AGENTS.md §3](../../AGENTS.md#3-ground-rules)). Credit Bybifok in the protocol entry.

| # | Fact | Evidence | Our status |
|---|---|---|---|
| P1 | The forum-list pager is a window (`1 100 500 … 550`): its last link is a lower bound, not the page count | PR #3; ultra-hfr `TopicListParser.swift:219-230` | Seen in LOT-002 (RC2.1, `R05b`); not yet in HFR-PROTOCOL. The exact page count **of each topic** is in its row (`sujetCase4`) |
| P2 | List paging goes through the path `liste_sujet-<n>.htm`; `?page=` on `liste_sujet-1.htm` is ignored | PR #3 | To capture; check against LOT-041 |
| P3 | Search ignores words shorter than 4 letters | PR #3 | To capture (LOT-046) |
| P4 | AQ RSS keeps HTML entities in titles and descriptions | PR #3 | To check on our AQ captures (LOT-025) |
| P5 | Topic search is a plain GET `forum2.php?…&word=&spseudo=&filter=1&currentnum=`; global search too (`searchall=1`, `post_cat_list`); a member's posts at `/hfr/recherche/pseudo-<name>.htm` | ultra-hfr `TopicSearch.swift:28-36` | To capture (LOT-046) |
| P6 | "Mes drapeaux" lists only followed topics with news; it carries a `suppressflag.php` link that must never be called without an explicit user action | ultra-hfr `docs/pages-connecte.md` | To cross-check with `R10` (LOT-024) |
| P7 | The `closedb_new` icon does not say whether a followed topic is read; icon paths depend on the account's theme (`images_forum/1` vs `images/defaut`): match on `alt` or file name | ultra-hfr parsers | To check (LOT-022) |
| P8 | In the MP list, `[non lu]` means the **correspondent** has not read it | ultra-hfr `docs/pages-connecte.md` | To capture (LOT-023) |
| P9 | Old `forum2.php3` links still work; "Achats & Ventes" points to its first sub-forum | ultra-hfr | To capture (link router, FEAT-020) |
| P10 | Home page: Bybifok's fixture and our `R01-home-anon.html` both have 20 `tr.cat` rows, while HFR-PROTOCOL §6b says 19 category links | ultra-hfr fixture; our R01 | To recount and fix in HFR-PROTOCOL |

Not kept: the proposed `[quotemsg=numreponse,page,0]` — our captures (`R41a`, `R41b`, `R47a`) show `numreponse,ref,<quoted member id>`; the empty smiley-search result — our `R53c` shows a "Désolé…" text.

## 4. Legacy features the proposals do not mention

"All current functions" stay in scope. Checked in the legacy code; none may disappear silently:
multi-account · blacklist and whitelist · MPStorage sync · bookmarks · post filter · MP actions (new MP, mark unread, delete) · new topic, edit and delete own posts · moderator alert · AQ creation · poll vote and poll draft · archived drafts · "+" button modes · Giphy · automatic background MP check (BGTask) — FEAT-005 adds to it, does not replace it · **account deletion** (App Store 5.1.1(v)) · start-screen and favourites-mode settings · multi-window · the legacy "swipe changes page" setting (on by default; the proposal removes the gesture — keep the setting, default to be decided).

## 5. Claims checked

| Claim | Verdict |
|---|---|
| HFR gives no total page count in topic lists | 🟠 True for the list pager, false for each topic (row `sujetCase4`) |
| No universal links: the site publishes no `apple-app-site-association` | 🔴 False: the AASA exists (old format) and names the legacy App ID `QMG83DG7YP.hfrplus.red.super` (checked live 2026-10-26). Universal links work for a release under that App ID (Q-1), not for a third-party app |
| HFR cuts a message at the first emoji | 🟢 At the first non-BMP character (HFR-PROTOCOL, `W12`); BMP emoji untested |
| Upload deletion on reho.st | 🔴 No delete API evidenced for guest uploads |
| No instant push | 🟢 |

## 6. Bybifok's PRs on `ezzz/HFRnow:master`

They target the **shipped Objective-C app**, not SwiftHFR: merging them is ezzz's decision. Our review (static only, no build possible on Linux; no CI ran on them; all start from tag `4.0`, 43 commits behind `master`):

| PR | Content | Verdict |
|---|---|---|
| #3 Bug fixes | real legacy bugs (nil crash in list parsers, pager index, `liste_sujet` paging, AQ entities, bookmarks open page 1, list jump on refresh) | 🟠 Cherry-pick: `237db70`, `a817498`, `9935b98`, `dc93420` apply cleanly. Blockers: a committed `Carthage/Build` symlink to the author's machine; "Link"→"Lien" breaks `MessagePopupMenuPolicyTests.swift:48,128`; a nil image `src` can mark a flag "red" |
| #4 iPhone Duo | Duo inner/outer screens, workarounds for iOS 27.1 freezes, `displayScale` instead of `UIScreen.main` | 🟠 Keep the workarounds; `b1f07e2` removes `TabBarReselectionObserver` and conflicts with `c1e1424` |
| #5 "Natif calme" reskin | ~95 % visual, +2.5 k lines, no tests | 🔴 Not as is: `[code]` blocks lose monospace (`!important` rule), user accent colours overwritten, brightness/tint settings removed (just restored on `master`), fixed font sizes |
| #6 Sidebar, page menu, single colour | replaces the iPad split navigation just finished on `master` (HFR-006) | 🔴 Not as is: custom back-gesture delegate makes other gestures fail, `onAppear` counter can drift, filter summary counts only the current page |

Fixes from #3 are also **non-regression tests to write** in SwiftHFR (LOT-022, 025, 041, 046).

## 7. Licence

ultra-hfr is MPL-2.0 (file-level copyleft); SwiftHFR is PolyForm Noncommercial. Copied files would stay MPL-2.0. Preferred path: ideas and facts are ported through our lots with credit; when Bybifok submits their own code by PR, it is contributed under this project's licence ([CONTRIBUTING.md](../../CONTRIBUTING.md)). Any wholesale import needs an ADR amending ADR 0003.
