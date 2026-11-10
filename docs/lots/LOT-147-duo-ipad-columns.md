# LOT-147 — iPhone Duo and iPad column layouts

- **Module:** App
- **Difficulty / model:** difficult (Fable → Opus)
- **Issue:** [#237](https://github.com/ezzz/HFRnow/issues/237) · implements FEAT-016 (#160, proposed by Bybifok), all of it
- **Milestone:** M4, the whole lot: the legacy Duo layout as a backport of legacy evolution (operator, 2026-11-09, [#655](https://github.com/ezzz/HFRnow/issues/655)), and the FEAT-016 additions legacy lacks (operator, 2026-11-09, on [#237](https://github.com/ezzz/HFRnow/issues/237))
- **Depends on:** LOT-082 (#100, done), LOT-170 (#296, done: the iPad split root this lot widens). No longer LOT-145 (#235, M5): the handoff is an in-memory store, not per-scene state restoration (`FoldHandoffStore.swift:11-88` @ `2fe43da3`)

Short spec written by the catch-up pass of [#655](https://github.com/ezzz/HFRnow/issues/655) (legacy reference `legacy/duo-inner-cover` @ `2fe43da3`, PR #372), and brought to the reference `87fe0d1c` on 2026-11-10 ([below](#legacy-at-87fe0d1c-the-beta-feedback-fixes)). It records what the reference does and the operator decision on the fold handoff; the author of the lot completes it before coding (AGENTS.md §5).

## Scope (M4): the iPhone Duo as legacy has it at `2fe43da3`

**Operator decision, 2026-11-09, on [#659](https://github.com/ezzz/HFRnow/issues/659#issuecomment-6733950589):** the reference stays `2fe43da3`; the iPhone Duo fold/unfold handoff is in it, so it is **parity, M4, in scope of this lot**. It is not an open question any more. #450 (built on #372) is a legacy matter: nothing is taken from it by default.

**Operator decision, 2026-11-09, on [#655](https://github.com/ezzz/HFRnow/issues/655):** the **whole lot** goes to M4 (the inner-screen split, the handoff, all of it), as a backport of legacy evolution: legacy added the Duo support during SwiftHFR's development (legacy PR #372, `796b34bd` to `35337c9a`). It needs no Phase 5 design document any more: the design is the legacy one.

What legacy does at `2fe43da3` (`HFRswift/Swift/`). The `@ 87fe0d1c` ranges in brackets are the same code at the current reference, shifted by the five commits of the section below; `FoldHandoffStore.swift` and `FoldHandoffDestination.swift` did not change:

| Legacy @ `2fe43da3` | Behaviour |
|---|---|
| `MainWindow.swift:1357-1365` (`usesSidebarRoot`) [`:1380-1388` @ `87fe0d1c`] | split root (sidebar + list + topic) when the scene is regular in both dimensions, or on an iPad in regular width: the unfolded Duo (a `.phone` reporting regular/regular) gets the split; the cover screen, other iPhones and a landscape Pro Max (regular width, compact height) keep the tab bar |
| `MainWindow.swift:1367-1373, 1702-1709` (`prefersDetailOnlyTopic`) [`:1390-1396, 1755-1762` @ `87fe0d1c`] | unfolded Duo in portrait: once a topic is open it goes full width (`detailOnly`); landscape shows list + topic again |
| `FoldHandoffStore.swift:11-88` | one store for the topic read at the root of the selected tab: `register` / `update` (page, last page), a clear deferred 400 ms so that the root swap of a fold wins over the teardown of the old hierarchy (`scheduleClear`, `rootGeneration`), `beginRootSwap`, `requestCompactPush` / `consumePendingPush` |
| `MessagesView.swift:3180-3208` [`:3244-3272` @ `87fe0d1c`] | only the root reader of a tab registers (`navigationDepth == 0`): readers pushed from links are not carried; a reader covered by its own push, search or image viewer keeps its registration |
| `MainWindow.swift:1694-1696, 2087-2140` (`handleRootSwap`, `clearAllTopicTargets`) [`:1747-1749, 2140-2193` @ `87fe0d1c`] | on unfold, the topic read in the selected tab opens in the split's detail column of that tab's destination (Plus is carried only towards Bookmarks / Alertes Qualitay); nothing read → every split selection is cleared, so an older one cannot come back. On fold, the split selection is cleared and the topic is pushed on the compact tab's stack |
| `FoldHandoffDestination.swift:1-57` | the compact tab root pushes the pending topic (`navigationDestination`) when it appears or when a push is requested |
| `HFRswiftTests/FoldHandoffStoreTests.swift` | the store's rules as unit tests |
| `Common.swift:187-200, 214-242` (`HFRSwiftOrientationPolicy`, `796b34bd`) | unfolded (any scene regular in both dimensions), every orientation but upside down whatever the rotation setting, and no portrait lock while composing; the locks apply again once folded (GAP-213) |
| `Common.swift:337-373` (`expandedPhoneInlineNavigationTitle`, `e1fdb57e`, `f81200d9`) [`:337-388` @ `87fe0d1c`] | on a regular/regular `.phone` layout, the tab roots and the split columns use inline titles: a workaround for an iOS 27.1 hang after a large title collapses on the inner screen. **At `87fe0d1c` the cover screen gets them too** (`903bcb06`, below): the `2fe43da3` rule alone no longer describes legacy. Same kind, `Common.swift:375-390` (`ToolbarRefreshIcon`, `f026682f`) [`:390-405` @ `87fe0d1c`]: refresh buttons keep their label while loading, else the Liquid Glass toolbar balloons during a push on the inner screen. Check on the Duo whether SwiftHFR needs either before porting it |
| `MessagesView.swift:3210-3214` (`shouldHideReplyComposerButton`) [`:3274-3278` @ `87fe0d1c`] | the reply button hides on a `.phone` in compact height only, so the unfolded Duo keeps it |

The handoff carries the topic and its **page** (`Reading.navigationTarget`: `initialScroll` nil, `FoldHandoffStore.swift:93-103`), not the scroll position inside the page.

SwiftHFR today: the split root is iPad-only (`App/SwiftHFR/Root/RootNavigationView.swift:47-48`, ported from `2440d79`), so the unfolded Duo shows the tab bar and there is no handoff (GAP-210, GAP-215, GAP-217).

## Scope (M4): the FEAT-016 additions legacy lacks

**Operator decision, 2026-11-09** (m2-lead, recorded on [#237](https://github.com/ezzz/HFRnow/issues/237)): the FEAT-016 items legacy does not have at `2fe43da3` are in M4 too, in this lot. They are evolutions, not parity: an explicit operator exception to the M5 rule of `docs/LOTS.md`. They stay under the UX principles of `docs/FEATURES.md` (*Preserve what works*, *Defaults keep the legacy UX; changes are opt-in settings*, operator 2026-10-28): **both are opt-in settings, off by default**, so the legacy bottom bar and the legacy sidebar behaviour stay the default. Making one the default would change navigation and needs the community's support recorded on #160 (`docs/FEATURES.md:12`). GAP-655 (`b·operator`) records them.

| FEAT-016 item ([#160](https://github.com/ezzz/HFRnow/issues/160), Bybifok) | Legacy @ `2fe43da3` | To specify before coding |
|---|---|---|
| Tabs in a rail when folded | the cover screen keeps the tab bar (`MainWindow.swift:1357-1365`, `usesSidebarRoot` false) | which screens and size classes get the rail; how it coexists with the reader's hidden tab bar (GAP-008, UXD-02) and the Liquid Glass bars (GAP-220 to GAP-226) |
| Sidebar pinned or on demand | two split roots (`MainWindow.swift:1796-1820`; every `MainWindow.swift` line of this cell is 19 to 53 lines lower at `87fe0d1c`, e.g. `:1849-1873`, `:1336-1341`, `:1378`, `:1489-1506`, `:2128-2135`). Destinations with a topic list: the sidebar starts hidden (`doubleColumn`, list + topic), the user shows or hides it with the system control, and that choice is persisted across launches, but picking a destination sets it back to `doubleColumn` (`detailOnly` for a Duo portrait topic, `:2075-2079`) (`:1317-1322` `SidebarVisibilityStorage`, key `HFRswiftIPadSplitColumnVisibilityV3`; `:1355` default; `:1452-1469` binding). The other destinations (Réglages, Rechercher, Crédits, Charte, Supprimer mon compte): a two-column split whose sidebar starts visible (`:1343` `.all`, `:1813`), not persisted, and set back to `.all` (`:2082`). No pin setting | what "pinned" adds to the persisted visibility (a sidebar that stays shown when a topic opens, say), the setting, its scope (device, ADR 0013) and whether it also applies to the iPad split; off by default |

Bybifok's own notes are ideas only (`docs/research/bybifok-proposals.md:33, 77`: PR #4, ultra-hfr `RootLayout`). There is no design document: **the author writes this section's design (layouts, defaults, the setting if any) in this spec first, and the operator approves it on #237 before any code.** Off by default, as above. The PR that ships them says `Closes #160` (this lot is FEAT-016's last one).

## Legacy at `87fe0d1c`: the beta-feedback fixes

The reference moved to `87fe0d1c` on 2026-11-10 (operator, [#655](https://github.com/ezzz/HFRnow/issues/655); AGENTS.md §2). `git log 2fe43da3..87fe0d1c` is five commits of 2026-11-09, the answers to the Duo beta feedback on #372. `87fe0d1c` does not compile as is (`MainWindow.swift:1677`: `WindowShape` must be `Sendable`, [Mac check of `87fe0d1c` on #372](https://github.com/ezzz/HFRnow/pull/372#issuecomment-6737029007), check 0); the lines below are for citations, and a fix commit on #372 may shift these lines: re-check citations then. Legacy's own description of the three fixes is `backlog.md:65-67` @ `87fe0d1c` (HFR-097 to HFR-099). Lines @ `87fe0d1c`, `HFRswift/Swift/` unless said otherwise; the measured column is that Mac check (simulator, iOS 27.2, with a local one-line `Sendable` patch).

| Legacy @ `87fe0d1c` | Behaviour | Owner in SwiftHFR |
|---|---|---|
| `PhoneDisplayPolicy.swift:5-12, 44-70` (`PhoneDisplayKind`, `displayKind`) | the scene is `.duoInner` when a `.phone` shows the split root, `.duoCover` when a `.phone` without the split root matches **any** of: model identifier `iPhone19,4` (`:25`; `SIMULATOR_MODEL_IDENTIFIER` in the simulator, `hw.machine` on a device, `:33-42`; `5f6c411c`), a portrait window with a side safe-area inset (the cover screen's system chrome is a vertical strip on the right edge; `903bcb06`), or the split root seen on a `.phone` since launch (`903bcb06` persisted it in `UserDefaults`; memory only since `5f6c411c`); `.other` otherwise, and always on an iPad | this lot (detection), [#681](https://github.com/ezzz/HFRnow/issues/681) (first user) |
| `MainWindow.swift:1362-1365, 1398-1410, 1677-1693` (`RootTabView`: `windowShape`, `hasShownExpandedPhoneLayout`, `phoneDisplayKind`; `903bcb06`, `WindowShape` and the single pass `5f6c411c`) | the root measures orientation and side inset in one geometry pass (`WindowShape`, `PhoneDisplayPolicy.swift:15-20`), sets the "seen unfolded" flag when `usesSidebarRoot` is true on a `.phone`, and publishes the kind in the environment (`hfrPhoneDisplayKind`, `Common.swift:351-361`) | this lot |
| `Common.swift:337-343, 371-388`; `PhoneDisplayPolicy.swift:72-83` (`usesInlineRootTitle`; `903bcb06`) | inline tab-root titles on **both** Duo displays (any kind but `.other`), and on a regular/regular `.phone` outside the root; other iPhones and the iPad keep large titles. Cause: the iOS 27.1/27.2 hang (`_observeScrollViewDidScroll` / `_updateSafeAreaInsets`) after a large title collapsed on scroll, also on the cover screen (open a category after scrolling Catégories). Measured: the hang reproduces at `2fe43da3` and is gone at `87fe0d1c` (10 categories and Plus), titles inline on the cover (checks 1a to 1c) | [#681](https://github.com/ezzz/HFRnow/issues/681) (M4, `host: mac`): port it only if SwiftHFR hangs too, as the row on `Common.swift:337-373` above says |
| `CoverScreenThumbActions.swift:1-9`; `MainToolbar.swift:18, 26, 46`; `MainWindow.swift:206, 376-393, 844-852`; `Favorites.swift:806`; `MPListView.swift:676` (`ea531a2a`; the forum list's grouping off the cover screen `5f6c411c`) | **Intended by the code:** on the cover screen only (`PhoneDisplayPolicy.swift:85-89`, `placesThumbActionsAtBottom`), "Actualiser" of Catégories, a forum's topic list, Favoris and Messages goes from the top trailing corner to the bottom of the toolbar column (`.bottomBar`), within thumb reach. **Measured** (checks 2a, 2b, 2d, 2e): at the bottom on the forum list and Favoris; **at the top on Catégories and Messages**, as at `2fe43da3` (probable cause: a strip with no top item draws its only `.bottomBar` item at the top). That defect is reported on #372 for legacy. **SwiftHFR target:** the intended placement, at the bottom on all four lists; do not port the defect | this lot (GAP-713) |
| `CoverScreenThumbActions.swift:11-35`; `MainWindow.swift:854`; `MessagesView.swift:5696` (`ea531a2a`) | on the cover screen, a pushed forum topic list and a pushed topic get a "Retour" button (`chevron.backward`, `dismiss()`) at the bottom of the toolbar column; the system back button and the edge swipe stay. Measured as intended on the forum list and the topic (checks 2a, 2c; on the topic it sits right above the page-previous chevron) | this lot (GAP-713) |
| `HFRswiftTests/PhoneDisplayPolicyTests.swift:1-79` (`5f6c411c`, `87fe0d1c`) | the rules above as unit tests: cover screen by side strip, by model, by "seen unfolded"; a regular iPhone in portrait and in landscape (side insets of the sensor housing) is not a cover screen; the iPad never is; inline titles on both Duo displays only; thumb actions on the cover screen only | this lot, #681 |

Not this lot: `b16eb82d`, no page swipe from a touch that starts in a horizontally scrollable block (`[fixed]`, measured; a `[code]` line is not such a block on HFR, check 4a'), is the reader's: [LOT-106](LOT-106-reader-display-settings.md) and [#672](https://github.com/ezzz/HFRnow/issues/672).

Legacy's thumb-reach answer covers the **cover** screen; the beta feedback of [#671](https://github.com/ezzz/HFRnow/issues/671) (a legacy-app study, open) is about the **unfolded** Duo's reader, which `87fe0d1c` leaves as it was (refresh at the bottom only on the last page scrolled to its end, `MessagesView.swift:4972`). This lot ports the cover-screen behaviour; the inner screen follows #671's outcome.

## Not in this lot
- iOS 27.1 layout APIs as a goal of their own: use them only where the design above needs them.
- Legacy's own iPad layout (sidebar sections, Bookmarks and Alertes Qualitay in the split) is LOT-170 and #685.
- The cover screen's fill: done by #432 (M4, GAP-216).
- Scroll position across a fold: legacy carries the page only (above).

## Legacy counterpart (app lots)
To write by the author: one line per SwiftHFR file, citing the rows above (`// Port of HFRswift/Swift/FoldHandoffStore.swift (FoldHandoffStore) @ 87fe0d1c. Differences: …`; `FoldHandoffStore.swift` is the same at `2fe43da3`).

## Behaviour, edge cases, fixtures
To write. No HFR request is involved (layout only), so no capture is needed; Mac check on the iPhone Duo (or an iPad window resized between compact and regular, which legacy treats the same way, `FoldHandoffStore.swift:4-8`).

## Intentional differences from legacy
To write.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
