# LOT-122 — Appearance: darker dark, OLED black, separators

- **Module:** App (`Settings/ThemeAppearance.swift`, `ThemeSettingsModel.swift`, `ThemeSettingsView.swift`); engine: `DarkStyle` (HFRModels) and `SettingKey.darkStyle` (HFRStorage)
- **Difficulty / model:** medium (Sonnet 5.5 author, Opus 5.5 review)
- **Issue:** [#213](https://github.com/ezzz/HFRnow/issues/213) (umbrella FEAT-010 [#154](https://github.com/ezzz/HFRnow/issues/154), UXD-22, M4)
- **Depends on:** LOT-121 (theme parity), LOT-083 (reader), #568/PR #577 (message separation tokens), #570/PR #576 (`RowTint`)
- **Feature spec:** [FEAT-010](../features/FEAT-010.md); this file is the lot's side of it.

## Legacy sources
- `Classes/ThemeColors.m:164` @ `2440d79`: the dark background, `rgb(23, 24, 26)` = #17181A, scaled by the brightness setting. `Classes/Constants.h:52-55`: the `Theme` enum (light, dark only: no OLED).
- `HFRswift/Swift/AppSettingsView.swift:370-399` (`themeSection`, the Thème section, kept by LOT-121) @ `2440d79`. Bybifok PR #5: ideas only (#0B0B0C, OLED, 1 pt separators), no code taken.

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `ThemeAppearance.readerDarkSurfaces(_:)`, `darkScreenBackground` | `ThemeColors.m:164` (one dark background) |
| `ThemeSettingsView` "Style du thème sombre" + preview | none @ 2440d79 (new, FEAT-010) |
| `appScreenBackground()`, `ThemedNavigationStack` (in `ThemeSettingsModel.swift`) | none @ 2440d79 |

## UX evolutions (app lots)
| Change | Class | Reason |
|---|---|---|
| New picker "Style du thème sombre" (Standard / Plus sombre / Noir OLED), default Standard | `a` (as the GAP-145 row; new UX, Bybifok FEAT-010; UXD-22 (a)) | Optional: a setting, never the default; defaults unchanged. |
| Sample of the chosen dark surfaces in the settings | `a` (GAP-145) | Live preview asked by the issue. |
| Separators: no new setting; the reader's rule is #568's `--separator-strong` | `a` (GAP-145) | One separator spec (the sub-orchestrator's rule). |

The single accent with a live preview is LOT-180 (M5), not here. Compact mode is LOT-169, the one-line header LOT-106.

## Behaviour
- **`DarkStyle`** (`theme_dark_style`, integer 0 standard, 1 darker, 2 OLED; device-only in ADR 0013 matrix E; unknown value reads as standard).
- **Reader.** The style picks the four `--app-dark-*` variables LOT-121 already sets (`ThemeAppearance.readerVariables`): background, quote, placeholder, separator. Standard is the LOT-083 palette (#000, #1C1C1E, #2C2C2E, #38383A); darker #0B0B0C, #17181A (the legacy dark), #232326, #2E2E31; OLED #000, #111113, #1C1C1E, #38383A. The brightness multiplier applies on top, except that darker and OLED never lift the page background above their own value (at 150 % #0B0B0C would put a continuation date under 4.5:1; `ThemeAppearanceTests` checks it at every brightness). `reader.css` is not touched: #568's `--surface-alt` and `--separator-strong` are derived from `--text` and `--background`, so the alternate message surface and the 1 px rule follow the style, one separator spec.
- **Native screens.** `appScreenBackground()`: in dark and only for darker / OLED, `scrollContentBackground(.hidden)` and `containerBackground` for `.navigation` and `.navigationSplitView` (the iPad columns). **Standard applies nothing at all**: measured on d66cf402, an always-applied `containerBackground` with an empty builder is not "no modifier": it clears the opaque fill of the stack's own hosting controller (white or black as the system sets it, `backgroundColor` nil instead), so a pushed screen that does not paint itself (a loading or empty state) is transparent over whatever is behind it, mid-push and mid-swipe-back. A fallback fill does not restore it everywhere: `.background` (or `systemBackground`) restores stacks but breaks the split view's sidebar material and the medium sheet's own fill. So **only the style chooses the structure** and the appearance only changes values: a flip between light and dark (iOS's sunset schedule, Control Center) rebuilds nothing below it (a conditional on the appearance gave the wrapped screen, the reader's web view and the composer included, a new identity: measured on 76ded38f, 2 views made per dark, light, dark round trip), while a change of style in Settings rebuilds the screens it wraps (the user's own change; transient state resets). Measured with a counted `UIViewRepresentable` under a themed stack and under a split column (`AppThemeTests`: 1 view after dark, light, dark, and after Darker, OLED, Darker; Standard likewise) and, against a control without the modifier over a red host view, pixel for pixel over the whole window in Standard (dark and light) on a list, a screen that is not a list, a pushed screen that is not a list, three split columns with the sidebar material and a medium sheet (the test fails on d66cf402: 14 of its 20 cases).
  - **Trade-off, Darker and OLED in light:** stacks keep the system's background (pixel-identical to no modifier: list, other screen, pushed screen), but a split column and a sheet lose their own fill there (the iPad sidebar's material, the sheet's shade), which no empty or fallback form avoids while keeping one structure. Not claimed by a test; in the Mac check.
  - A root-level modifier does not reach a navigation container (measured: the screen stayed black), so it is applied where a container or a pushed screen starts: `ThemedNavigationStack` replaces `NavigationStack` in every stack that is not a media viewer (image, video), and the pushed destinations (topic list, reader, offline list, Plus entries, search's "topic not found", Settings screens) carry it. A screen pushed without it keeps the system fill (`AppThemeTests`). Split-view columns (iPad and wide layouts: forum list, topics, reader, Messages, Plus sidebar and detail) carry it on each column root (operator decision: in scope); collapsed on an iPhone the column shown carries it (`AppThemeTests`, compact width). A modifier on the `NavigationSplitView` itself does not reach its columns (measured: only the sidebar changed, to a material grey), so it is applied per column (`AppThemeTests`, three-column pixel test on an iPad simulator).
- **Reader web view.** Its own layer (`underPageBackgroundColor`) follows the style, so the bounce past the page's ends does not show a different black.
- **Settings preview.** Drawn from `ThemeAppearance.readerSurfaces`, the surfaces the reader receives (same brightness, same cap), with Dynamic Type metrics.
- **Contrast** (WCAG formula, `ThemeAppearanceTests`, on the surfaces the reader shows): text (#F2F2F7) and secondary text (#A1A1A6) are at least 4.5:1 on every dark surface of every style at 100 %, and in darker and OLED at 125 % and 150 % too (secondary also on the alternate message surface and on quotes); the light theme's text and secondary text on white and on the quote grey. **The accent is checked for the default hue (190°) only**: the hue slider's night tint (saturation 0.70, brightness 0.95, LOT-121 and legacy) is below 4.5:1 on black for blues (3.5:1 at 240°; red is 5.8:1, purple 4.7:1) and lower on the lighter surfaces (blue on `#2C2C2E` is about 2.3:1 at 100 %), which this lot does not change; LOT-180 (single accent) owns it. Standard above 100 % is LOT-121's slider (legacy surfaces scaled up) and is not claimed.
- #577 and #576 are merged: the reader's tokens above are #577's, reused as they are (`ThemeAppearanceTests` checks the secondary text on the alternate surface and on quotes); `RowTint` (#570) draws its tint over the system row colour and is not changed: native rows keep the system's raised colour in every style.

## Edge cases
- Following iOS: the style shows while iOS is dark; going back to light removes the background at once.
- Brightness 0 % makes every reader dark surface black, in every style (as LOT-121).

## Fixtures
None; no HFR page is read, `HFR-PROTOCOL.md` unchanged. **Pending capture:** none.
Tests: `SettingKeyTests`, `SettingScopeTests`, `SettingsEnumsTests` (key, scope, raw values), `ThemeSettingsModelTests` (default, persistence, appearance), `ThemeAppearanceTests` (palettes, contrast, preview surfaces), `ReaderThemeTests` (computed background, quote colours and under-page colour in the real reader, live), `AppThemeTests` (a real window: the screen behind a list and behind a pushed screen is #0B0B0C in dark, pixel-identical to a control without the modifier in Standard and in light, an unthemed pushed screen keeps the system fill; every column of a three-column split view and a collapsed one at compact width; no view below the modifier is rebuilt by a flip of appearance or style).

## Intentional differences from legacy
- Legacy had one dark (#17181A, scaled by the brightness setting). SwiftHFR's Standard keeps the system's dark on native screens and #000 in the reader; the legacy grey is now the darker style's quote surface.
- Rows and cards of native lists keep the system's raised colour (not scaled by the brightness setting, as LOT-121).

## Not in this lot
Single accent colour and its live preview (LOT-180, M5); seasonal themes (LOT-166); compact mode (LOT-169); one-line header (LOT-106).

## Learnings
- Mac check needed: darker and OLED on a real iPhone and iPad (navigation bars, sheets, scroll-edge effects of #545), including a background to foreground trip with a reader and a composer open; tests assert the list, form and split-view column backgrounds only. #572 defines native lists as system backgrounds: the darker and OLED styles hide the list background (rows keep the system raised colour), an exception to note there.
- A conditional view modifier changes the structural identity of what it wraps: keep one structure per appearance and vary the values (measure with a counted `UIViewRepresentable`, not by reading the code). An empty `containerBackground` is not "no modifier": compare against a control over a host view that is not `systemBackground`.
