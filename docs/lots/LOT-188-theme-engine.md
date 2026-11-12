# LOT-188 — Theme engine (token files) and the theme gallery

- **Module:** HFRModels (`Theme/`: `ThemeRGB`, `ThemeTokens`, `ThemeDefinition`, `ThemeCatalog`), HFRStorage (`SettingKey.themeID`), App (`Settings/ThemeAppearance.swift`, `ThemeSettingsModel.swift`, `ThemeCatalog+Bundle.swift`, `ThemeGallery.swift`, `ThemeSettingsView.swift`, `Common/AccessibleColors.swift`, `Reader/Resources/reader.css`, `Themes/`)
- **Difficulty / model:** difficult (Opus 5.5 → Fable 5.1)
- **Issue:** [#729](https://github.com/ezzz/HFRnow/issues/729) · **Contract:** [THEMES.md](../THEMES.md) §1–§3, §8
- **Depends on:** LOT-121 (#212), LOT-122 (#213), THEMES.md (#727)
- **Unblocks:** LOT-191 (Samain), LOT-192 (Swift, Rétro 5250), LOT-193 (OG Web), Noël abusé in LOT-166; LOT-180 (#420) turns the gallery into its « Thème » sub-menu.

## Legacy sources
- `Classes/Constants.h` `Theme` enum (light, dark) and `HFRswift/Swift/AppSettingsView.swift:421-466` (`themeSection`) @ `87fe0d1c`: legacy has two themes, no gallery.
- `HFRswift/Swift/Common.swift:813-938` (`AppThemePalette`) and `Classes/ThemeColors.m` @ `87fe0d1c`: legacy's colours, which SwiftHFR already draws through LOT-121/122; the Legacy theme keeps that code, it is not re-expressed as tokens.

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ 87fe0d1c |
|---|---|
| `ThemeGallery`, `ThemeGalleryRow`, `ThemeSwatch` | none (two themes, `AppSettingsView.swift:421-466`) |
| Legacy theme | `Common.swift:813-938` (`AppThemePalette`), `ThemeColors.m`, through LOT-121/122 unchanged |

## UX evolutions (app lots)
| Change | Class | Reason |
|---|---|---|
| Theme gallery below the shipped pickers in Réglages › Thème; Legacy is the default | `b·operator` (operator 2026-10-28), GAP-729 (`gap-new` in the PR's `### Ledger`) | Themes asked by the operator; defaults unchanged. |
| The hue slider, dark style and brightness show only while Legacy is the theme | `b·operator` (operator 2026-11-11 on #729: « the other themes have fixed colours and no slider ») | A theme's colours are its tokens. |

## Behaviour
### Theme file
- One folder per theme: `App/SwiftHFR/Themes/<id>/<id>.theme.json`. **Not `theme.json`**: Xcode copies a folder-synchronized group's resources flat into the app bundle (ADR 0012; `Bundle.main.url(forResource: "reader", withExtension: "js")` finds `Reader/Resources/reader.js` at the bundle root), so two `theme.json` would be two outputs of one name. THEMES.md §3 is updated to say so. The art of a theme's `Decorations/` (LOT-166) must have unique names for the same reason. *Mac check:* a build with two themes.
- Keys: `id` (kebab-case, the folder name and the stored id), `name`, `family`, `author` (optional: no « par » line), `fontDesign` (`default` / `rounded` / `monospaced`, default `default`), `decorations` (id or null, LOT-166), `variants`: `{ "light": {…}, "dark": {…} }` or `{ "any": {…} }`, nothing else.
- Colours are `#RRGGBB` or `#RRGGBBAA`. Every variant defines the 21 required tokens of THEMES.md §3; the five optional table tokens (`headerBand` → `surfaceRaised`, `alternateCell` → `surface`, `meta` → `textSecondary`, `pageBar` → `surfaceRaised`, `counter` → `textSecondary`) fall back as written. An unknown token name is an error (a typo of an optional token would otherwise be ignored silently).
- **Legacy** (`legacy.theme.json`) carries no `variants`: it is today's app, drawn by LOT-121/122 (hue slider, dark style, brightness), and the engine overrides nothing for it. Every other theme must have variants. A missing Legacy file is replaced by the same built-in entry, so the app always has it.
- `ThemeCatalog`: Legacy first, then by family (`Classiques`, `Rétro`, `OG Web`, then others by name), then by name. A file that does not decode, or whose id was already seen, is left out and logged; the HFRKit test fails on it first.

### Contrast test (THEMES.md §3)
WCAG 2.x relative luminance, 4.5:1, no large-text exception, on opaque colours (a translucent colour in a pair fails its rule). Each variant is checked in the appearance it shows in: a `light` slot in light, a `dark` slot in dark, an `any` variant in the appearance its background reads as. Rules (`ThemeTokens.contrastRules`):
- THEMES.md §3: `title`, `sectionHeader` on `background`; `textPrimary`, `textSecondary`, `accentText`, `link` on `surface`; `onAccent` on `accent`; `textPrimary` and `textSecondary` on `quoteBackground` (a quote's text and its header); `codeText` on `codeBackground`; `spoilerText` on `spoilerBackground`; `onUnread` on `unread`.
- Native screens: `systemText` (the system label of the appearance, black or white) on `background` and `surface`; `accentText` (the tint) on `systemCard` (the system list card, #FFFFFF or #1C1C1E) and on `background` (toolbar and plain buttons, empty-state actions).
- The reader: `link` on `quoteBackground`, `spoilerBackground`, `codeBackground`; `textSecondary` (the « Code : » header) and `accentText` (code keywords) on `codeBackground`; `accentText` on `quoteBackground`; `textPrimary`, `textSecondary`, `link`, `accentText` on `readerAlternate` (the even message: `textPrimary` mixed into `surface` at the Increase Contrast strength, 7 % light, 16 % dark).
- Optional tokens: `meta`, `counter` on `surface` and `alternateCell`; `textPrimary` on `alternateCell`, `headerBand`, `pageBar`.

Theme files are strict: an unknown key, variant or token name is an error. `ThemeDefinitionTests` (HFRKit, Linux) decodes every bundled `*.theme.json` and checks it; it fails on the broken fixture.

### Setting
`theme_id` (`SettingKey.themeID`, optional string, **device-only**, ADR 0013 matrix E row added). Nil or an id no bundled theme has (a theme a later version added, or one removed) reads as Legacy and is left in the store. Selecting Legacy stores `legacy`.

### What a theme changes
- **Tint** (`.tint` and the window's `tintColor`): the theme's `accentText`, per appearance. SwiftUI's one tint colours text and glyphs (buttons, links, check marks), which §3 holds to 4.5:1 on `surface`; `accent` (fills) is read by the views that fill.
- **Screen background** (`appScreenBackground()`, every stack, pushed screen, split column and themed sheet LOT-122 covers): the theme's `background` in both appearances, through one dynamic colour. `ThemeAppearance.screenFill` decides the structure (`system`, Legacy's `darkOnly` style, `theme`): a change of theme or dark style may rebuild the screens it wraps (the user's own change), an appearance flip never does.
- **Font design**: `.fontDesign(…)` at the app root, `nil` for Legacy and `default` (no change); the reader gets it as `--app-theme-font` (`ui-rounded` or `ui-monospace` families; `[code]` keeps its monospace rule).
- **Prominent buttons** (`appProminentButtonStyle()`, the five `.borderedProminent` buttons): under a theme, `ThemedProminentButtonStyle` draws an `accent` capsule and an `onAccent` label itself (the tint is a text colour, on which the system style's white label need not be legible; `ThemeEngineWindowTests` reads both pixels); Legacy keeps `.borderedProminent`.
- **Appearance**: a single-variant theme (« clair = sombre ») imposes the appearance its background reads as (black text contrasts more → light), so the system's text and chrome match its one palette; the « Thème » picker then has no effect, and the screen says so. Legacy and two-variant themes follow the picker.
- **Reader**: `ThemeAppearance.readerVariables` adds `--app-theme-light-*` and `--app-theme-dark-*` (`text`, `secondary`, `background` = `surface`, `separator`, `quote-border`, `quote-background`, `placeholder` = `quoteBackground`, `action` = `accentText`, `link`, `code-*`, `spoiler-*`), and `readerScript` sets `data-app-theme` on `<html>` (Legacy removes it). `reader.css` reads them only under `:root[data-app-theme]`, so Legacy's page is today's. #568's `--surface-alt` and `--separator-strong` stay derived. The page is the theme's `surface`: the reader is a list of messages, the rows of §3, where its text rules hold. The web view's under-page layer is `surface` too.
- **Unread capsule** (#646): `BadgeCapsule` fills with `unread` and writes with `onUnread`; its outlined state stays on `AccessibleColors`, since it sits on the row's system card.

### What a theme does not change (this lot)
**Narrower than the issue's « those definitions read tokens » bullet: operator decision of 2026-11-12: (a); native rows, separators, selection and text are #842 (Fable round 1, finding 3; #729).** Native list rows and cards keep the system raised colour of the appearance in force, and native text keeps the system label colours: #572's one row, separator and state-tint definition, and #651's read and unread title tones, read the system colours, unchanged by a theme; what a theme decides for them is the appearance (its own for a single variant), and its tint is checked on the system card. Recolouring rows, separators, selection and native text means touching every list (`listRowBackground` is per row), which this lot leaves to #842 (once the shared list component of #836 lands). `title`, `sectionHeader`, `textPrimary`, `textSecondary`, `separator`, `selection`, `surfaceRaised` reach native screens through `ThemeAppearance.themeColor(_:)` for the views that adopt them; a theme lot that needs rows or text recoloured natively (LOT-192's Rétro 5250, LOT-193's table look) opens that change against this model, not a second one.

### Gallery
`ThemeGallery` (its own view, so LOT-180 moves it into the « Thème » sub-menu with previews instead of building another): one section per family (seasonal families hidden: their window is LOT-166's), each row a light and a dark swatch in the colours the app draws (background, a card of the reader's page `surface`, a dot of the tint `accentText`; Legacy's from the user's hue and dark style), or one swatch and « clair = sombre », the name, « par <auteur> », a check mark; footer « Envie de proposer un thème ? Les règles sont dans le dépôt : docs/THEMES.md (voir le README). » The seasonal toggles of THEMES.md §1 are LOT-166's.

## Edge cases
- No theme file but Legacy's: the gallery shows Legacy alone (today, until LOT-191/192/193).
- A theme removed by an update while selected: Legacy is shown, the id stays, and the theme comes back if a later version bundles it again.
- Switching from a theme back to Legacy, live: the reader removes `data-app-theme` and shows Legacy's page without a reload (`ReaderThemeTests`).

## Fixtures
`App/SwiftHFRTests/Settings/ThemeFixtures/test-theme.theme.json` (meets every rule; light background #E6EEF8, dark #101820, distinct from the system's for the pixel tests) and `broken-theme.theme.json` (its dark `link` is 1.64:1 on `surface`). Read by HFRKit's `ThemeDefinitionTests` and the app tests. No HFR page; `HFR-PROTOCOL.md` unchanged. **Pending capture:** none.

Tests: `ThemeDefinitionTests` (HFRKit: colours, WCAG reference values, decoding rules, contrast rules on both fixtures and on every bundled theme, catalog order and unknown id), `SettingKeyTests`, `SettingScopeTests`; app: `ThemeEngineTests` (stored theme, relaunch, unknown id kept, Legacy changes nothing, a theme's tint, fill, font and reader variables, every reader variable read by `reader.css`, single variant imposes its appearance, #651 tones in every bundled theme), `ThemeEngineWindowTests` (real windows: list in light and dark and back to Legacy, pushed screen, sheet, three split columns, a flip rebuilds nothing), `ReaderThemeTests` (a theme recolours the page, Legacy restores it live), `ThemeAppearanceTests` (Legacy's script).

## Intentional differences from legacy
The gallery and every theme beyond Legacy are new (GAP-729). Legacy is unchanged.

## Learnings
- Folder-synchronized groups flatten resources into the bundle: a per-folder file name (`theme.json`) cannot repeat; name resources after their folder.
- Keep Legacy outside the token model when its look is code (hue slider, styles): a token file for it would either lie (tokens not applied) or fail its own contrast test (the default accent as text is 1.6:1 on white, LOT-122).
- *Mac check:* the app with the test theme copied into `Themes/` — lists, a topic, Settings, a sheet, iPad split view, light, dark, Dynamic Type XL; two theme folders build; selecting a theme in Réglages › Thème does not pop the screen or reset its scroll (the stack root's `appScreenBackground()` branch changes); VoiceOver reads and activates a gallery row.
