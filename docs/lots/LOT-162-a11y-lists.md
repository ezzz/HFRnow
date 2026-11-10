# LOT-162 — Accessibility pass: lists, navigation, accounts, settings

- **Module:** App
- **Difficulty / model:** medium (Sonnet → Opus)
- **Issue:** #252 (absorbs the Phase 4 backlog item "Dynamic Type everywhere"; contains #646)

## Legacy sources
None: legacy @ `87fe0d1c` has almost no accessibility work. Only #646 cites legacy: the unread-pages capsule was grey with white text in light and white with black text in dark (`Common.swift:691-700, 3122-3130` @ `2440d79`).

## Legacy counterpart (app lots)
No new view. Touched views keep their own pointers: `TopicRowView` (Favorites.swift TopicRowView), `MessageRowView` (MPListView.swift MPRowView), `TopicListView`, `ForumListView`, `AccountMenuButton`, `AccountsView`, `LoginView`, `SettingsView`, `ThemeSettingsView`, `PlusView`, `ForumSearchView`, `FilteredPostsBanner`.

## UX evolutions (app lots)
None beyond accessibility. Two visible colour changes, both `b·needed` (contrast; no GAP row, the legacy colours were not 4.5:1 either):
- the unread-pages capsule and the MP "non lu" capsule use fixed fills at ≥ 6.8:1 (#646); the "member has viewed" state is outlined instead of half-opacity;
- failure and warning messages keep their coloured icon and take the primary text colour (red and orange text measure 2.2 to 3.6:1 on the cards).

## Scope
Screens: forum list (Catégories), topic list (Favoris, forum topics) and its rows, MP list and rows, accounts menu, accounts screen, login sheet, Plus tab, settings (Général, Thème), forum search, filtered-posts banner. Reader and composer: LOT-163 (#253). Profile, offline list and smiley picker already carry labels and combine their rows; checked, no change.

## Checklist and findings
| Item | State at `dev-swift` | Change |
|---|---|---|
| VoiceOver labels | Rows combine children; unread dot, flag, post-it, lock, poll already labelled | spinners (`Chargement`, `Connexion en cours`) labelled; section header count spoken "N sujets"; search result row and its excerpt read as one element |
| Traits and values | Account menu: current account shown only by a checkmark glyph | `.isSelected` on the current account; settings sliders no longer read their value twice (the visible `LabeledContent` is hidden) |
| Dynamic Type to AX5 | Rows already lift line limits and cap the avatar; `FilteredPostsBanner` fixed at one line | banner lifts its limit at accessibility sizes |
| Contrast ≥ 4.5:1 | capsules 1.5:1 (#646) and 1.7:1; red/orange text 2.2–3.6:1 | `AccessibleColors` (computed and tested ratios), `BadgeCapsule`, `StatusLabel` |
| 44 pt targets | section fold chevron 32×28; banner dismiss buttons glyph-sized | 44×44 |
| Reduce Motion | none of these screens animates by hand (grep `withAnimation`, `.animation`, `.transition`: no hit) | none needed |
| Async announcements | sent-confirmation banners, failure banner, login error, search outcome were silent | `AccessibilityNotification.Announcement` |

## Edge cases
- The outlined capsule sits on the row's own background: unread MP rows are tinted, and the outlined state only shows on read rows, so it is drawn on the plain card (tested on white, black and the two grouped greys).
- An announcement is posted when a banner appears; a banner that changes text while visible is not re-announced.

## Fixtures
None (no HFR fact).

## Intentional differences from legacy
None.

## Mac checks (not possible in the cloud)
Accessibility Inspector audit and a VoiceOver pass on iPhone 18 Pro and iPad (iOS 27.0): lists, accounts, settings, search. AX5 Dynamic Type, Increase Contrast, light and dark; read the capsule contrast on screenshots (#646's table).

## Learnings
A colour used as text (red, orange, the accent) is not a text colour: put it on the icon and keep the text primary, or use a pair with a tested ratio.
