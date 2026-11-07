# LOT-185 — Liquid Glass surfaces, buttons and bars outside the reader

- **Module:** App
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5 review)
- **Issue:** #548 (umbrella #545, M4; operator decision 2026-11-07: the HIG wins over legacy, every divergence is recorded)

## Legacy sources
- `HFRswift/Swift/LiquidGlass.swift` @ `2440d79` (the helpers `hfrGlassSurface`, `hfrGlassButton`, `hfrToastSurface`, `presentationGlassBackground`).
- List pagers: `MainWindow.swift:977-981`. Filtered "Résultats suivants" bar: `MessagesView.swift:4728-4740`.

No `View` extension mirrors the helpers: every converted site is one modifier (`glassEffect`, `safeAreaBar`) and the minimum target is iOS 27, so the helpers' `#available` fallbacks are dead code.

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `Navigation/PagerToolbar.swift` (new), `Navigation/TopicListView.swift` (`PageBar`) | `MainWindow.swift` (`ForumTopicsPaginationBar`, :977-981) |
| `Messages/MessageListView.swift` (`MessagePageBar`) | `MainWindow.swift:977-981` |
| `Search/ForumSearchView.swift` (`pagerToolbar`) | `ForumSearchView.swift` pager (own glass capsule) |
| `FilteredPosts/FilteredPostsView.swift` (`NextBatchBar`, `FilteredPostsBanner`) | `MessagesView.swift:4728-4740`, `Favorites.swift` (`FavoritePostFilterProgressBanner`) |
| `Smileys/SmileyPickerView.swift`, `Offline/ReaderOfflineSave.swift`, `Reader/Viewer/ImageViewerView.swift`, `Root/RootTabsView.swift` | none @ 2440d79 (new screens), or toolbar of `MessagesView.swift` |

## UX evolutions (app lots)
GAP rows are written by the docs child of #545 (`ext/francoisgn-docs-545`); this lot lists its divergences here.

| Change | Class | Reason |
|---|---|---|
| List pagers (forum, MP, search) are system bottom-bar items, not a hand-built strip | `b·operator` (2026-11-07) | Legacy pagers were glass too (parity); on iPhone Duo's cover screen the system moves bottom bars to the side, a custom strip cannot. |
| Pager bar is the system's, not legacy's own glass capsule | `b·operator` | HIG Toolbars: [reduce toolbar backgrounds](https://developer.apple.com/design/human-interface-guidelines/toolbars). |
| Image viewer: black bar background dropped, `ellipsis` instead of `ellipsis.circle`, toast is glass | `b·operator` | HIG Toolbars: "Borders (like outlined circle symbols) aren't necessary". |
| Smiley "notice" capsule is glass | `b·operator` | Floating over scrolling content: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials). |

## Behaviour
View-only. Model logic is unchanged (`TopicListModel`, `MessageListModel`, `ForumSearchModel`, `FilteredPostsModel` untouched). Enabled states and visibility conditions of each pager are the ones of the removed strips, now read in `.toolbar { … }`.

APIs used (verified on the live docs 2026-11-07, see #545): `glassEffect(_:in:)`, `safeAreaBar(edge:…)`, `ToolbarSpacer` (iOS 26.0+). `.buttonStyle(.glassProminent)` was unverified: if CI does not compile it, replace by `.glass` + tint.

## Sites (every one converted or kept)
HIG: [Materials](https://developer.apple.com/design/human-interface-guidelines/materials) ("Don't use Liquid Glass in the content layer"; glass for floating elements), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout) (scroll edge effect instead of an opaque fill under controls), [Buttons](https://developer.apple.com/design/human-interface-guidelines/buttons) (one prominent action per view).

| Site | Decision | Reason |
|---|---|---|
| `ImageViewerView` `toolbarBackground` ×2 | converted: removed, `toolbarColorScheme(.dark)` kept | Toolbars |
| `ImageViewerView` toast | converted: `glassEffect(in: .capsule)` | floats over the image |
| `ImageViewerView` "Réessayer" (`borderedProminent`) | **kept** | content of a failed page, not floating |
| `ImageViewerView` `ellipsis.circle` | converted: `ellipsis` | Toolbars |
| `TopicListView` pager | converted: `ToolbarItemGroup(.bottomBar)` via `PagerToolbar` | Duo, glass |
| `MessageListView` pager | converted, same | same |
| `ForumSearchView` pager (first/prev/next/last) | converted, same | same |
| `FilteredPostsView` `NextBatchBar` | converted to `safeAreaBar(edge: .bottom)`, fill dropped, button `.glassProminent` (the one primary action). **Not** a toolbar item (legacy used one) | the bar carries a state line, a hint and a Cancel while it runs; a toolbar item cannot hold them without losing information |
| `TopicListView` top strip (store problem) | converted: `safeAreaBar(edge: .top)`, fill dropped | Layout |
| `ReaderOfflineSave` top strip | converted, same | Layout |
| `FilteredPostsView` top banner (`bar` in rounded rect) | `safeAreaBar(edge: .top)` + `glassEffect(in: .rect(cornerRadius: 10))` | floats over the reader |
| `MessageListView` segment switch | converted: `safeAreaBar(edge: .top)`, fill dropped | Layout |
| `SmileyPickerView` search bar | converted: `safeAreaBar(edge: .bottom)`, fill dropped (a bottom bar, not a top strip as #548 says) | Layout |
| `SmileyPickerView` notice capsule | converted: `glassEffect(in: .capsule)` | floats over the grid |
| Notice cards `LoadFailureView:36`, `TopicSentBanner`, `MessageSentBanner`, `LoadFailureBanner` | **kept** `regularMaterial` | content layer: they push the list down |
| Cards of `ReaderReplyFlow`, `ReplyComposerView`, `TopicSearchSheet` | not touched | LOT-186 / LOT-174 |
| Buttons `LoadFailureView:15`, `SmileyPickerView:261`, `ImageUploadView:98,193`, `AccountsView:149` | **kept** | content-layer buttons, not floating |
| `RootTabsView` `ellipsis.circle` | converted: `ellipsis` | Toolbars |
| `FormattingToolbar` `.background(.bar)` | **kept** | composer bar: LOT-174 (M5) |
| `LOT-115` glass buttons dropped without a UXD | reversed for the search pager only through the system bar | operator 2026-11-07 |

Acceptance grep: `.background(.bar)` outside `Reader/` leaves only `Composer/FormattingToolbar.swift:16` (LOT-174).

## Edge cases
- A pager appears only when the old strip did (paged source with content; MP page > 1 or next; search with a previous or next path).
- Dynamic Type XL can overflow a 5-item bottom bar (search): to check on the Mac.

## Fixtures
None (view-only). Existing app tests unchanged.

## Mac check needed
Light, dark, Dynamic Type XL, Reduce Transparency, Increase Contrast; iPhone 18 Pro, iPad, iPhone Duo poses. Check in particular: pagers over the tab bar, the toolbar item "Page N" contrast, the search bar above the keyboard in the smiley picker, glass banner contrast over the reader.

## Intentional differences from legacy
See "UX evolutions".

## Learnings
- A toolbar item cannot carry multi-line state: keep `safeAreaBar` for bars with text beyond a button.
