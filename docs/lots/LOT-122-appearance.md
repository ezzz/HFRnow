# LOT-122 — Appearance: darker dark, OLED black, separators

- **Module:** App (`Settings/ThemeAppearance.swift`, `ThemeSettingsModel.swift`, `ThemeSettingsView.swift`); engine: `DarkStyle` (HFRModels) and `SettingKey.darkStyle` (HFRStorage)
- **Difficulty / model:** medium (Sonnet 5.5 author, Opus 5.5 review)
- **Issue:** [#213](https://github.com/ezzz/HFRnow/issues/213) (umbrella FEAT-010 [#154](https://github.com/ezzz/HFRnow/issues/154), UXD-22, M4)
- **Depends on:** LOT-121 (theme parity), LOT-083 (reader), #568/PR #577 (message separation tokens), #570/PR #576 (`RowTint`)
- **Feature spec:** [FEAT-010](../features/FEAT-010.md); this file is the lot's side of it.

## Legacy sources
- `Classes/ThemeColors.m:164` @ `2440d79`: the dark background, `rgb(23, 24, 26)` = #17181A, scaled by the brightness setting. `Classes/Constants.h:52-55`: the `Theme` enum (light, dark only: no OLED).
- `HFRswift/Swift/AppSettingsView.swift:422-468` (Thème section, kept by LOT-121). Bybifok PR #5: ideas only (#0B0B0C, OLED, 1 pt separators), no code taken.

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `ThemeAppearance.readerDarkSurfaces(_:)`, `darkScreenBackground` | `ThemeColors.m:164` (one dark background) |
| `ThemeSettingsView` "Style du thème sombre" + preview | none @ 2440d79 (new, FEAT-010) |
| `appScreenBackground()`, `ThemedNavigationStack` (in `ThemeSettingsModel.swift`) | none @ 2440d79 |

## UX evolutions (app lots)
| Change | Class | Reason |
|---|---|---|
| New picker "Style du thème sombre" (Standard / Plus sombre / Noir OLED), default Standard | `b` (GAP-145, new UX, Bybifok FEAT-010; UXD-22 (a)) | Optional: a setting, never the default; defaults unchanged. |
| Sample of the chosen dark surfaces in the settings | `b` (GAP-145) | Live preview asked by the issue. |
| Separators: no new setting; the reader's rule is #568's `--separator-strong` | `b` (GAP-145) | One separator spec (the sub-orchestrator's rule). |

The single accent with a live preview is LOT-180 (M5), not here. Compact mode is LOT-169, the one-line header LOT-106.

## Behaviour
- **`DarkStyle`** (`theme_dark_style`, integer 0 standard, 1 darker, 2 OLED; device-only in ADR 0013 matrix E; unknown value reads as standard).
- **Reader.** The style picks the four `--app-dark-*` variables LOT-121 already sets (`ThemeAppearance.readerVariables`): background, quote, placeholder, separator. Standard is the LOT-083 palette (#000, #1C1C1E, #2C2C2E, #38383A); darker #0B0B0C, #17181A (the legacy dark), #232326, #2E2E31; OLED #000, #111113, #1C1C1E, #38383A. The brightness multiplier applies on top. `reader.css` is not touched: #568's `--surface-alt` and `--separator-strong` are derived from `--text` and `--background`, so the alternate message surface and the 1 px rule follow the style, one separator spec.
- **Native screens.** `appScreenBackground()` (`scrollContentBackground(.hidden)` and `containerBackground(for: .navigation)`), only in dark and only for darker / OLED; in light or Standard it applies the defaults. A root-level modifier does not reach a navigation container (measured: the screen stayed black), so it is applied where a container or a pushed screen starts: `ThemedNavigationStack` replaces `NavigationStack` in every stack that is not a media viewer (image, video), and the pushed destinations (topic list, reader, offline list, Plus entries, Settings screens) carry it. A screen pushed without it keeps the system fill (`AppThemeTests`). iPad split-view columns are not covered (Mac check).
- **Contrast.** Text (#F2F2F7), secondary text (#A1A1A6) and the night accent are at least 4.5:1 on every dark surface of every style, and the light theme's text and secondary text on white and on the quote grey (`ThemeAppearanceTests`, WCAG formula, measured not assumed).
- `RowTint` (#570) draws its tint over the system row colour and is not changed: native rows keep the system's raised colour in every style.

## Edge cases
- Following iOS: the style shows while iOS is dark; going back to light removes the background at once.
- Brightness 0 % makes every reader dark surface black, in every style (as LOT-121).

## Fixtures
None; no HFR page is read, `HFR-PROTOCOL.md` unchanged. **Pending capture:** none.
Tests: `SettingKeyTests`, `SettingScopeTests`, `SettingsEnumsTests` (key, scope, raw values), `ThemeSettingsModelTests` (default, persistence, appearance), `ThemeAppearanceTests` (palettes, contrast), `ReaderThemeTests` (computed background and quote colours in the real reader, live), `AppThemeTests` (a real window: the screen behind a list is #0B0B0C in dark, untouched in Standard, OLED and light).

## Intentional differences from legacy
- Legacy had one dark (#17181A, scaled by the brightness setting). SwiftHFR's Standard keeps the system's dark on native screens and #000 in the reader; the legacy grey is now the darker style's quote surface. CHANGELOG-LEGACY row added.
- Rows and cards of native lists keep the system's raised colour (not scaled by the brightness setting, as LOT-121).

## Not in this lot
Single accent colour and its live preview (LOT-180, M5); seasonal themes (LOT-166); compact mode (LOT-169); one-line header (LOT-106).

## Learnings
- Mac check needed: darker and OLED on a real iPhone and iPad (navigation bars, sheets, split-view columns); only the list and form backgrounds are asserted in tests.
