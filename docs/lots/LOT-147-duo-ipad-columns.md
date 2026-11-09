# LOT-147 — iPhone Duo and iPad column layouts

- **Module:** App
- **Difficulty / model:** difficult (Fable → Opus)
- **Issue:** [#237](https://github.com/ezzz/HFRnow/issues/237) · implements FEAT-016 (#160, proposed by Bybifok), all of it
- **Milestone:** M4, the whole lot: the legacy Duo layout as a backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655)), and the FEAT-016 additions legacy lacks (operator, 2026-11-09, on [#237](https://github.com/ezzz/HFRnow/issues/237))
- **Depends on:** LOT-082 (#100, done), LOT-170 (#296, done: the iPad split root this lot widens). No longer LOT-145 (#235, M5): the handoff is an in-memory store, not per-scene state restoration (`FoldHandoffStore.swift:11-88` @ `2fe43da3`)

Short spec written by the catch-up pass of [#655](https://github.com/ezzz/HFRnow/issues/655) (legacy reference `legacy/duo-inner-cover` @ `2fe43da3`, PR #372). It records what the reference does and the operator decision on the fold handoff; the author of the lot completes it before coding (AGENTS.md §5).

## Scope (M4): the iPhone Duo as legacy has it at `2fe43da3`

**Operator decision, 2026-11-09, on [#659](https://github.com/ezzz/HFRnow/issues/659#issuecomment-6733950589):** the reference stays `2fe43da3`; the iPhone Duo fold/unfold handoff is in it, so it is **parity, M4, in scope of this lot**. It is not an open question any more. #450 (built on #372) is a legacy matter: nothing is taken from it by default.

**Operator decision, 2026-11-09, on [#655](https://github.com/ezzz/HFRnow/issues/655):** the **whole lot** goes to M4 (the inner-screen split, the handoff, all of it), as a backport of legacy evolution: legacy added the Duo support during SwiftHFR's development (legacy PR #372, `796b34bd` to `35337c9a`). It needs no Phase 5 design document any more: the design is the legacy one.

What legacy does at `2fe43da3` (`HFRswift/Swift/`):

| Legacy @ `2fe43da3` | Behaviour |
|---|---|
| `MainWindow.swift:1357-1365` (`usesSidebarRoot`) | split root (sidebar + list + topic) when the scene is regular in both dimensions, or on an iPad in regular width: the unfolded Duo (a `.phone` reporting regular/regular) gets the split; the cover screen, other iPhones and a landscape Pro Max (regular width, compact height) keep the tab bar |
| `MainWindow.swift:1367-1373, 1702-1709` (`prefersDetailOnlyTopic`) | unfolded Duo in portrait: once a topic is open it goes full width (`detailOnly`); landscape shows list + topic again |
| `FoldHandoffStore.swift:11-88` | one store for the topic read at the root of the selected tab: `register` / `update` (page, last page), a clear deferred 400 ms so that the root swap of a fold wins over the teardown of the old hierarchy (`scheduleClear`, `rootGeneration`), `beginRootSwap`, `requestCompactPush` / `consumePendingPush` |
| `MessagesView.swift:3180-3208` | only the root reader of a tab registers (`navigationDepth == 0`): readers pushed from links are not carried; a reader covered by its own push, search or image viewer keeps its registration |
| `MainWindow.swift:1694-1696, 2087-2140` (`handleRootSwap`, `clearAllTopicTargets`) | on unfold, the topic read in the selected tab opens in the split's detail column of that tab's destination (Plus is carried only towards Bookmarks / Alertes Qualitay); nothing read → every split selection is cleared, so an older one cannot come back. On fold, the split selection is cleared and the topic is pushed on the compact tab's stack |
| `FoldHandoffDestination.swift:1-57` | the compact tab root pushes the pending topic (`navigationDestination`) when it appears or when a push is requested |
| `HFRswiftTests/FoldHandoffStoreTests.swift` | the store's rules as unit tests |
| `Common.swift:187-200, 214-242` (`HFRSwiftOrientationPolicy`, `796b34bd`) | unfolded (any scene regular in both dimensions), every orientation but upside down whatever the rotation setting, and no portrait lock while composing; the locks apply again once folded (GAP-213) |
| `Common.swift:337-373` (`expandedPhoneInlineNavigationTitle`, `e1fdb57e`, `f81200d9`) | on a regular/regular `.phone` layout, the tab roots and the split columns use inline titles: a workaround for an iOS 27.1 hang after a large title collapses on the inner screen. Same kind, `Common.swift:375-390` (`ToolbarRefreshIcon`, `f026682f`): refresh buttons keep their label while loading, else the Liquid Glass toolbar balloons during a push on the inner screen. Check on the Duo whether SwiftHFR needs either before porting it |
| `MessagesView.swift:3210-3214` (`shouldHideReplyComposerButton`) | the reply button hides on a `.phone` in compact height only, so the unfolded Duo keeps it |

The handoff carries the topic and its **page** (`Reading.navigationTarget`: `initialScroll` nil, `FoldHandoffStore.swift:93-103`), not the scroll position inside the page.

SwiftHFR today: the split root is iPad-only (`App/SwiftHFR/Root/RootNavigationView.swift:47-48`, ported from `2440d79`), so the unfolded Duo shows the tab bar and there is no handoff (GAP-210, GAP-215, GAP-217).

## Scope (M4): the FEAT-016 additions legacy lacks

**Operator decision, 2026-11-09** (m2-lead, recorded on [#237](https://github.com/ezzz/HFRnow/issues/237)): the FEAT-016 items legacy does not have at `2fe43da3` are in M4 too, in this lot. They are evolutions, not parity: an explicit operator exception to the M5 rule of `docs/LOTS.md` and to the 2026-10-28 rule of not taking Bybifok's UX proposals by default. GAP-655 (`b·operator`) records them.

| FEAT-016 item ([#160](https://github.com/ezzz/HFRnow/issues/160), Bybifok) | Legacy @ `2fe43da3` | To specify before coding |
|---|---|---|
| Tabs in a rail when folded | the cover screen keeps the tab bar (`MainWindow.swift:1357-1365`, `usesSidebarRoot` false) | which screens and size classes get the rail; how it coexists with the reader's hidden tab bar (GAP-008, UXD-02) and the Liquid Glass bars (GAP-220 to GAP-226) |
| Sidebar pinned or on demand | the split root shows the system sidebar, no pin setting | the control (setting or gesture), its default (the legacy behaviour), its scope (device, ADR 0013) and whether it also applies to the iPad split |

Bybifok's own notes are ideas only (`docs/research/bybifok-proposals.md:33, 77`: PR #4, ultra-hfr `RootLayout`). There is no design document: **the author writes this section's design (layouts, defaults, the setting if any) in this spec first, and the operator approves it on #237 before any code.** Defaults keep the legacy layout unless the operator decides otherwise. The PR that ships them says `Closes #160` (this lot is FEAT-016's last one).

## Not in this lot
- iOS 27.1 layout APIs as a goal of their own: use them only where the design above needs them.
- Legacy's own iPad layout (sidebar sections, Bookmarks and Alertes Qualitay in the split) is LOT-170 and #685.
- The cover screen's fill: done by #432 (M4, GAP-216).
- Scroll position across a fold: legacy carries the page only (above).

## Legacy counterpart (app lots)
To write by the author: one line per SwiftHFR file, citing the rows above (`// Port of HFRswift/Swift/FoldHandoffStore.swift (FoldHandoffStore) @ 2fe43da3. Differences: …`).

## Behaviour, edge cases, fixtures
To write. No HFR request is involved (layout only), so no capture is needed; Mac check on the iPhone Duo (or an iPad window resized between compact and regular, which legacy treats the same way, `FoldHandoffStore.swift:4-8`).

## Intentional differences from legacy
To write.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
