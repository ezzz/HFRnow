# LOT-147 — iPhone Duo and iPad column layouts

- **Module:** App
- **Difficulty / model:** difficult (Fable → Opus)
- **Issue:** [#237](https://github.com/ezzz/HFRnow/issues/237) · implements FEAT-016 (#160, proposed by Bybifok)
- **Depends on:** LOT-145 (#235), LOT-082 (#100, done)

Short spec written by the catch-up pass of [#655](https://github.com/ezzz/HFRnow/issues/655) (legacy reference `legacy/duo-inner-cover` @ `2fe43da3`, PR #372). It records what the reference does and the operator decision on the fold handoff; the author of the lot completes it before coding (AGENTS.md §5).

## Parity part (M4): fold / unfold handoff

**Operator decision, 2026-11-09, on [#659](https://github.com/ezzz/HFRnow/issues/659#issuecomment-6733950589):** the reference stays `2fe43da3`; the iPhone Duo fold/unfold handoff is in it, so it is **parity, M4, in scope of this lot**. It is not an open question any more. #450 (built on #372) is a legacy matter: nothing is taken from it by default.

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

The handoff carries the topic and its **page** (`Reading.navigationTarget`: `initialScroll` nil, `FoldHandoffStore.swift:93-103`), not the scroll position inside the page.

SwiftHFR today: the split root is iPad-only (`App/SwiftHFR/Root/RootNavigationView.swift:47-48`, ported from `2440d79`), so the unfolded Duo shows the tab bar and there is no handoff (GAP-210, GAP-215, GAP-217).

## Rest of the lot
The other Duo and iPad column layouts of FEAT-016 (tab rail, pinned or on-demand sidebar, cover screen) keep their milestone (`tooling/roadmap/m5.py`) until the orchestrator splits the lot; GAP-215 to GAP-217 say which part legacy already has. The inner-screen split and the portrait full-width topic above are what the handoff needs to exist; whether they move to M4 with it follows the same rule ("in the reference, so parity") and is the orchestrator's call.

## Legacy counterpart (app lots)
To write by the author: one line per SwiftHFR file, citing the rows above (`// Port of HFRswift/Swift/FoldHandoffStore.swift (FoldHandoffStore) @ 2fe43da3. Differences: …`).

## Behaviour, edge cases, fixtures
To write. No HFR request is involved (layout only), so no capture is needed; Mac check on the iPhone Duo (or an iPad window resized between compact and regular, which legacy treats the same way, `FoldHandoffStore.swift:4-8`).

## Intentional differences from legacy
To write.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
