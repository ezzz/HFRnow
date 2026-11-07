# LOT-186 — Reader chrome for Liquid Glass and iOS 27

- **Module:** App
- **Difficulty / model:** medium · Opus 5.5 → Fable 5.1 review
- **Issue:** [#549](https://github.com/ezzz/HFRnow/issues/549), absorbs [#428](https://github.com/ezzz/HFRnow/issues/428) (UXD-10). Umbrella: [#545](https://github.com/ezzz/HFRnow/issues/545) (M4; the operator's decision of 2026-11-07: the HIG wins over legacy, every divergence recorded).

## Legacy sources
All at `2440d79` of <https://github.com/ezzz/HFRnow>, `HFRswift/Swift/MessagesView.swift`:

- bottom bar: `4756-4800` (`ToolbarItemGroup(placement: .bottomBar)` with ‹ ›, a spacer, the bottom refresh, the reply "+");
- ‹ › buttons: `4184-4204` (`bottomPreviousPageButton`, `bottomNextPageButton`); ‹ lands at the bottom, › at the top: `4168-4178`;
- the top "…" menu: `4692-4724` (poll, "Rechercher", then `pageChoiceMenuItems`);
- page choices: `4206-4236` (`pageChoiceMenuFinalTargets`, `pageChoiceMenuItems`: "Page 1", "Page ...", the last three pages, "Dernier post");
- reply hidden on an iPhone in compact height: `2762-2764` (`shouldHideReplyComposerButton`);
- bottom refresh only on the last page scrolled to its end: `4180-4182` (`shouldShowBottomRefreshButton`).

## Legacy counterpart (app lots)
- `Reader/ReaderPageControls.swift` (`ReaderPageControls`, `ReaderPageMenu`): `HFRswift/Swift/MessagesView.swift (bottomPreviousPageButton, bottomNextPageButton, pageChoiceMenuItems, pageChoiceMenuFinalTargets)`.
- `Reader/TopicReaderView.swift` (`TopicReaderView`): `HFRswift/Swift/MessagesView.swift (MessagesView)`, comment updated.
- `Reader/ReaderScrollGeometry.swift`, `Reader/ReaderWebController+Scroll.swift`: none @ 2440d79 (legacy's web view did not run under the bars).
- `Composer/ReaderReplyFlow.swift`: unchanged pointer; its button moved to `ReaderPageControls`.

## UX evolutions (app lots)
Each is a divergence from legacy taken because the HIG wins (operator, #545, 2026-11-07). Class is the H.1 column of [GAP-LEGACY-VS-SWIFT.md](../migration/GAP-LEGACY-VS-SWIFT.md#convergence-classification-h1): `b·operator` is a user-visible difference the operator decided, `a (parity)` restores the legacy behaviour. GAP rows are added by the docs child of #545 (`ext/francoisgn-docs-545`), which references this section.

| # | Change | Legacy (file:line @ 2440d79) | HIG rule (live page, read 2026-11-07) | Class |
|---|---|---|---|---|
| D1 | The page choices are in the bottom "N / M" menu **and** in the top "…" overflow (GAP-060, UXD-10, #582): one list (`ReaderPageMenuItems`), after the other actions in a `Section`, only past one page, as legacy does. Labels: "Première page", "Aller à la page…" (legacy "Page 1", "Page ..."), a new "Dernière page" that replaces legacy's last "Page N" (no repeat; `[Page 38, Page 39, Dernière page, Dernier post]` at 40 pages, no "Page 2" at 2). The bottom menu gets the same labels and the extra item (operator, 2026-11-07, #582) | `MessagesView.swift:4692-4724` (symbol `ellipsis`, `:4722`) | [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo): "Reserve the ellipsis symbol for overflow"; [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): the system overflow menu holds what does not fit | b·operator |
| D2 | **Top bar grouping**: "Actualiser" and "Sondage" stay primary actions; "Filtrer les posts", "Rechercher dans le sujet" and "Enregistrer hors ligne" are secondary actions, i.e. the **system overflow menu**; "Répondre" moved to the bottom bar. The top bar shows at most three groups. | `MessagesView.swift:4659-4724` (title, poll, search in search mode, "…") | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): "aim for a maximum of three" groups | b·operator |
| D3 | The filter symbol is `line.3.horizontal.decrease`, no circle. | none (the port's own symbol) | [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars): "Borders (like outlined circle symbols) aren't necessary" | b·operator |
| D4 | **"Répondre" stays in landscape** on an iPhone; with `.visibilityPriority(.high)` the system moves the page menu to the overflow menu first, and the reply button only after it. | `MessagesView.swift:2762-2764` (hidden in compact height) | [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo): toolbars follow the system's layout across poses; [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) | b·operator |
| D5 | **The page runs under the bars** (navigation bar, the reader's banners, the bottom bar); no opaque fill (`.background(.bar)`) remains in `Reader/`; the toast and the reply confirmation are glass. | legacy bars were glass too (`LiquidGlass.swift`, `hfrToastSurface`): parity restored | [Layout](https://developer.apple.com/design/human-interface-guidelines/layout): "Instead of applying a solid or semi-opaque background color beneath controls, use a scroll edge effect"; [Materials](https://developer.apple.com/design/human-interface-guidelines/materials): glass for floating elements | a (parity) |

Kept as shipped, not legacy (already recorded): "Page…" asks in an alert, not legacy's sheet (`TopicPagePickerSheet`, `MessagesView.swift:4805-4812`; GAP-061, the navigator is LOT-110, M5); "Actualiser" stays in the top bar, no bottom refresh (`4180-4182`, `4778-4790`); the tab bar hides in compact width only, see #424 / PR #540 (UXD-02).

## Behaviour
**Bottom bar** (`ReaderPageControls`, only once a page is shown): system toolbar items, so they float as Liquid Glass and, on the iPhone Duo cover screen, move to the side with the system bars ([#545](https://github.com/ezzz/HFRnow/issues/545), [Designing for iPhone Duo](https://developer.apple.com/design/human-interface-guidelines/designing-for-iphone-duo): "Follow the system's vertical layout for toolbars").

```
[ ‹  › ]   ·flexible·   [ 3 / 12 ▾ ]   ·flexible·   [ + ]
 high                    automatic                    high     ← .visibilityPriority (iOS 27.0+)
```

- ‹ opens the previous page at its last message, › the next page at its top (legacy `4168-4178`; the swipe already did this). Both are disabled at the ends and while a page loads.
- The page menu: "Page 1", "Page…", the last three pages after page 1 without repeats (`ReaderPageMenu.finalTargets`, legacy `pageChoiceMenuFinalTargets`), "Dernier post" (last page, at its last message). Disabled for a single page (legacy showed no page items then). Its label is a spinner while a page loads, as the shipped page bar was. The served page is still followed (LOT-167).
- "Répondre" (`plus`, or `square.and.pencil` for `reply_button_behavior = forum`, none when hidden, logged out or without an answer form), disabled while a quote loads; the sheet and the confirmation stay in `ReaderReplyFlow`.
- APIs: `ToolbarItemGroup(placement: .bottomBar)`, `ToolbarSpacer(_:placement:)` (iOS 26.0+), `ToolbarContent.visibilityPriority(_:)` (iOS 27.0+), all read on the live developer docs on 2026-11-07. No iOS 27.1 API (those are LOT-147, M5).

**Page under the bars** (`TopicReaderView`, `ReaderWebController+Scroll`):

```
 ┌ navigation bar ─┐ ┐
 │ reply banner    │ ├ obscuredInsets.top (SwiftUI safe area, banners included)
 ├─────────────────┤ ┘ ← reading top = contentOffset.y + obscuredInsets.top
 │ message …       │
 │                 │
 ├─────────────────┤ ┐
 │ ‹ ›   3/12   +  │ ├ obscuredInsets.bottom
 └─────────────────┘ ┘
```

- The web view ignores the vertical safe area; a `GeometryReader` reads what the bars and banners cover (`proxy.safeAreaInsets`, top and bottom only: the page keeps the horizontal safe area) and the representable hands it to `ReaderWebController.obscuredInsets`.
- The controller sets `WKWebView.obscuredContentInsets` (iOS 26.0+), the scroll view's `contentInset` and indicator insets, and `contentInsetAdjustmentBehavior = .never`: UIKit's safe area does not see the reader's own banners (`LoadFailureBanner`, `ReplySentBanner`, the offline banner), the SwiftUI layout does.
- **A position is the content at the bars' edge** ("reading top", `ReaderScrollGeometry`), never the raw `contentOffset`:
  - a change of insets (a banner shown or hidden, the bar's height changing) keeps the reading top: `offset' = max(offset + old.top − new.top, −new.top)`;
  - a refresh (`keepsScrollPosition`) saves the reading top at `show` and restores it at ready with `window.scrollTo(0, readingTop)`: the page counts `scrollY` from the bars' edge, so the insets of that moment apply (the banner of a failed refresh can come or go meanwhile). Before, `contentOffset` was saved and set back raw at DOMContentLoaded (`ReaderWebController.swift:111, 242` before this lot), which the new document's first layout can undo (the first CI run of `aRefreshReopensAtTheSameMessageWhenTheBarsChanged` timed out on it);
  - the offset never goes above `−top`: the first message never detaches from the bar.
- LOT-111 positions are message numbers, not offsets: `reader.js` lands with `scrollIntoView` and reports the topmost message from `getBoundingClientRect`. With `obscuredContentInsets` set, WebKit counts both from the bars' edge; `ReaderInsetsWebTests` checks it in the real web view (landing below the bar; a message hidden under the bar is not the reading position). `reader.js` is unchanged.
- The toast (`menuFeedback`) is `glassEffect(.regular, in: .capsule)`, `padding(.bottom, 8)` above the bottom bar's safe area; the magic 56 is gone.

## Edge cases
- No page yet (loading, first failure): no bottom bar; the full-screen states (`overlay`) keep the safe area.
- A single page: ‹ › disabled, the menu disabled.
- `FilteredPostsView` (LOT-185's file) reuses `ReaderWebView` without insets: its web view stays inside the safe area, so `.never` with zero insets changes nothing there.
- Dynamic Type XL on a narrow iPhone: the page menu (automatic priority) goes to the overflow menu before ‹ › and "Répondre".
- Contrast of the tinted message headers (`reader.css:58-59, 113-121`) under the glass bars: not changed; checked on the Mac (below). The CSS changes only if that check fails.

## Fixtures
None: no HFR fact. Tests use built pages (`ReaderInsetsWebTests.tallDocument`) and the existing fakes.

## Tests
- `ReaderChromeTests` (model and math): reading top and clamping; insets changing both ways and at the top; the page menu's last pages (1, 2, 3, 4, 5, 1200 pages); ‹ and "Dernier post" land at the last message, › at the top, and "Réessayer" keeps it.
- `ReaderInsetsWebTests` (real `WKWebView`): the insets reach WebKit and the scroll view and the page opens below the bar; a message lands below the bar; the message hidden under the bar is not reported; a refresh reopens at the same content when a banner went away meanwhile.

## Mac check needed
After #540 merges (tab bar hidden). iPhone 18 Pro, iPad, iPhone Duo (each pose); light, dark, Dynamic Type XL, Reduce Transparency, Increase Contrast; dark brightness 0–150 % (LOT-122):
1. The first message sits right under the navigation bar, no gap and no double inset; the last one scrolls above the bottom bar.
2. Messages scroll under both bars with the scroll edge effect; the tinted headers stay readable under the glass.
3. ‹ › / "N / M" / "Répondre" in the bottom bar; on the Duo cover screen they move to the side bar; at Dynamic Type XL the page menu goes to the overflow first.
4. The top bar: "Actualiser", "Sondage" when there is a poll, and the system overflow menu (filter, search, offline save).
5. Reopening a topic at its saved position (LOT-111), a refresh in the middle of a page, a refresh that fails (banner) then succeeds: same message at the bar's edge.
6. The toast floats just above the bottom bar.

## Intentional differences from legacy
D1–D4 above. No legacy bug fixed.

## Learnings
- A web view under SwiftUI bars: read the covered area from SwiftUI (`GeometryReader` + `ignoresSafeArea`), not UIKit's safe area, which misses `safeAreaInset` banners; keep scroll positions as the content at the bars' edge.
