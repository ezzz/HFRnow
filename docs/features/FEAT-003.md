# FEAT-003 — Honest list paging

- **Issue:** [#147](https://github.com/ezzz/HFRnow/issues/147) · **Proposed by:** Bybifok (credit kept, see [CREDITS.md](../../CREDITS.md))
- **Engine lots:** [LOT-022](../lots/LOT-022-topic-list-parser.md) (pager shape), [LOT-082](../lots/LOT-082-adaptive-navigation.md) (no total shown), [LOT-167](../lots/LOT-167-page-navigation-exactness.md) (`PageNavigation.isExact`)

## What and why
The forum-list pager is a window (`1 … 10 20 … 100 200 … 500`): its last link is not the page count. The legacy app showed it as one (bug #104). Lists show "Page N" without a total unless HFR gives a real count, and never offer a "Dernière page" that leads to the wrong place.

## Screens and states
- Forum, favourites, search and MP lists: header "Page N"; "N / total" only when `navigation.isExact`.
- "Dernière page" (swipe, menu): enabled only when `isExact`; otherwise disabled with the same label.
- Topic row: the page count from the row (`sujetCase4`) stays exact and usable for "dernière page" of a topic.
- Light, dark, Dynamic Type XL and iPad: no layout change, text only; disabled state follows the system style.

## HFR facts
HFR-PROTOCOL §7b B1, §6c LOT-022 and LOT-167. Short pagers (`1…N`, `N < 10`) are exact; any window is a lower bound.

## Edge cases
Empty list or no pager: one page, exact. Hop/maintenance page: no list, not exact. Old stored navigation (no flag) decodes as lower bound.

## Engine lots needed
LOT-167 (this flag, set by `TopicListPager`). App wiring is part of the app list screens (LOT-082 and the Phase 4 list lots).

## Legacy settings kept
None.
