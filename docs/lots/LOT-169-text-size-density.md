# LOT-169 — App-wide text size and compact density

- **Module:** App (`App/SwiftHFR/Settings/TextScale.swift`, `ListDensity.swift`; rows, reader)
- **Difficulty / model:** medium (Opus 5.5 author, Sonnet 5.5 adversarial review)
- **Issue:** [#295](https://github.com/ezzz/HFRnow/issues/295) (operator decision 2026-10-28 (A); absorbs FEAT-010's compact mode and the text-size part of LOT-106)
- **Depends on:** LOT-119 (`text_size_percent`, `compact_mode`), LOT-082 (lists), LOT-083 (reader)

## Legacy sources
Read-only, `origin/master` of ezzz/HFRnow at `21173e77`.

| Legacy | Used for |
|---|---|
| `HFRswift/Swift/Common.swift:228` | `compact_mode` key |
| `HFRswift/Swift/Common.swift:265-293` | `AppTextSizeScale`: 100/110/120/130, `scaledUIFont` = base size × factor, then `UIFontMetrics` (Dynamic Type on top) |
| `HFRswift/Swift/Common.swift:309` | `compactListSectionSpacing`: section spacing in compact mode |
| `HFRswift/Swift/Common.swift:3194-3245, 3515-3581` | `TopicListRowView`: title `@ScaledMetric` base × factor, footer 13 pt, `VStack(spacing: 4)`, content padding |
| `HFRswift/Swift/Favorites.swift:188-215` | `FavoritesListDensity`: row insets 4/12 (regular), 3/12 (compact), section spacing 12 / 6 |
| `HFRswift/Swift/Favorites.swift:1117-1130` | favourites row: title base 14.3 pt, content padding 2/6 |
| `HFRswift/Swift/MessagesView.swift:668-720` | `MessageBodyTextSizeCSS`: the message body size injected as CSS, re-applied by script |
| `HFRswift/Swift/AppSettingsView.swift:597` | settings form spacing 8 in compact mode |

## Behaviour

- **One type scale.** `TextScale(percent:)` gives every text style its system size at the current Dynamic Type size × `text_size_percent` / 100 (`pointSize(_:at:)`). Views use `.scaledFont(.style)` instead of `.font(.style)`; icon and spacing sizes are `@ScaledMetric` × the factor (`scaled(_:)`). No fixed point size is left in the app's views.
- **One settings model.** `SwiftHFRApp` owns the one `GeneralSettingsModel` (created after the legacy settings migration) and puts it in the environment; `SettingsView` reads it from there, so moving the slider or the switch re-renders every screen at once. `appTypography(_:density:)` at the root sets the scale, the density, the default font (body on the scale), the minimum row height and the section spacing of every list.
- **Reader.** `reader.css` sizes the body as `--text-scale` × the root size (`-apple-system-body`, Dynamic Type); every other size is in `em`. `ReaderWebController.textScale` sets `--text-scale` on `<html>` from the reader's own content world: a document-start user script for each new document, applied again when the document reports `ready`, and a script run on the shown document when the value changes (live, no reload, no new `ready`). A live change keeps the pixel scroll offset, not the message at the top (follow-up, reachable when the reader and the settings are both on screen, iPad). The value is a number the app formats; the page's CSP and script policy are unchanged. `TopicReaderView`'s web view host passes the environment's scale on each update.
- **Density.** `ListDensity` (`compact_mode`) drives the topic, favourites, flags and MP rows; other lists (Catégories sidebar, Plus, settings) get the type scale and the minimum row height:

  | | regular | compact |
  |---|---|---|
  | row insets (top/bottom, sides) | 6, 16 | 3, 12 (legacy compact) |
  | title style, most lines | subheadline, 3 | footnote, 2 |
  | meta lines (MP) | two | one (`who · last post`) |
  | unread dot, avatar | 8, 40 | 6, 28 |
  | min row height, section spacing | 44, system | 28, 6 |

- **Dynamic Type.** The percentage multiplies the system size: accessibility sizes still grow the text at every slider value (70 % at AX5 is larger than 130 % at the default size). At accessibility sizes, titles and meta lines drop their line limits so nothing truncates, and the MP avatar stops at 64 pt. Fonts are `.system(size:)` at the computed size, so a text style's own traits beyond its weight (headline: semibold) are not carried over.

## Measurements (iPhone 18 Pro simulator, iOS 27.0, 402 × 874 pt, plain list of 40 rows, default Dynamic Type)

`ListDensityLayoutTests` hosts these lists in a window and checks that compact shows more rows than regular; the table comes from the same harness.

| List | regular | compact |
|---|---|---|
| Topics 100 % (median row, rows fully visible) | 46.3 pt, 13 | 36.0 pt, 17 |
| MP 100 % | 66.3 pt, 10 | 36.0 pt, 19 |
| Topics 70 % | 44.0 pt, 15 | 28.0 pt, 23 |
| Topics 130 % | 56.0 pt, 10 | 45.0 pt, 13 |
| Legacy favourites row rebuilt from its code (above) | 49.0 pt, 13 | 47.0 pt, 13 |

Before this lot the default topic row measured 66.7 pt (9 rows): the default is now within 6 % of legacy's row height and shows as many rows.

## Intentional differences from legacy

- A percentage from 70 % (below the default), not four steps from 100 %; it applies to every screen, not only the lists and the message body (CHANGELOG-LEGACY 53).
- Compact mode applies to every list and also shortens titles, merges the MP meta lines and shrinks markers; legacy only tightened insets and spacing of the favourites and settings (CHANGELOG-LEGACY 54).
- The reader's size goes through a CSS variable set from the app's content world, not a `<style>` element injected into the page (the reader's CSP refuses `<style>` elements, LOT-083).

## Not in this lot

- Side-by-side screenshots against the running legacy app (#295 acceptance criterion, left open): the legacy row above is rebuilt from its code and measured in the same harness.
