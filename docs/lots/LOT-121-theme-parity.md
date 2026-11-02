# LOT-121 — Theme parity (appearance, accent, dark brightness)

- **Module:** App (`App/SwiftHFR/Settings/ThemeSettingsModel.swift`, `ThemeAppearance.swift`, `ThemeSettingsView.swift`; app root, reader)
- **Difficulty / model:** medium (Opus 5.5 author, Sonnet 5.5 adversarial review)
- **Issue:** [#212](https://github.com/ezzz/HFRnow/issues/212)
- **Depends on:** LOT-060 (theme keys in `SettingKey`, `ThemeColor`, the `auto_theme` clamp), LOT-119 (settings shell, "Thème" row), LOT-083 (reader, CSP), LOT-169 (CSS variable path into the reader)

## Legacy sources
Read-only, `origin/master` of ezzz/HFRnow at `21173e77` (the same theme code is at `2440d79`, a few lines higher in `AppSettingsView.swift`).

| Legacy | Used for |
|---|---|
| `HFRswift/Swift/AppSettingsView.swift:16-18` | default hue 190°, default dark brightness 1.0, maximum 1.5 |
| `HFRswift/Swift/AppSettingsView.swift:101-102, 140-148` | keys `auto_theme` (3 iOS, 0 manual), `theme` (0 light, 1 dark); options "Automatique (iOS)", "Manuel", "Clair", "Sombre" |
| `HFRswift/Swift/AppSettingsView.swift:304-352` | hue slider: shows the hue of `theme_day_color_action`; a change writes day = (hue, s 0.65, b 1.0) and night = (hue, s 0.70, b 0.95); brightness stored in `theme_night_brightness`, clamped 0...1.5 |
| `HFRswift/Swift/AppSettingsView.swift:421-466` | "Thème" section: "Changement de thème", "Luminosité du thème" (manual only), "Teinte d'accent" (2 decimals, slider 0...1 step 0.001, tinted), "Luminosité du thème sombre" (percent, slider 0...1.5 step 0.01) |
| `HFRswift/Swift/Common.swift:320-415` | `AppThemeResolver`: manual scheme, or the system's; `setUsesSystemColorScheme` keeps `theme`; `setManualLegacyThemeValue` writes both keys |
| `HFRswift/Swift/Common.swift:460-643` | `ThemeUserColorStore`: `{r, g, b, a}` colours, default tints, `adjustedDarkThemeColor` (brightness' = m × (b − min) + min, m clamped 0...1.5) |
| `HFRswift/Swift/Common.swift:726-800` | `AppThemePalette`: the accent per scheme; dark surfaces through `adjustedDarkThemeColor` |
| `HFRswift/Swift/MainWindow.swift:1616-1618` | the root applies `.preferredColorScheme` and `.tint(actionTintColor)` |
| `Classes/HFRplusAppDelegate.m:358-393` | window `tintColor` = action tint, `overrideUserInterfaceStyle` from the resolver; `theme_noel_disabled` forced on (so the seasonal red never shows) |
| `Classes/ThemeColors.m:1123-1133` | ObjC screens call the same brightness formula (`adjustDarkThemeBrightnessOfColor:withMin:`) |
| `Classes/LuminosityHandler.m` | camera-based luminosity: no caller left in legacy (dead code), not ported |

## Behaviour

- **`ThemeSettingsModel`** (`@Observable @MainActor`, one instance owned by `SwiftHFRApp`, tests in `App/SwiftHFRTests/Settings/`): reads the legacy keys at creation, writes nothing then, and writes each change back under its legacy key and shape. `mode` (system / light / dark), `accentHue`, `darkBrightness`; `preferredColorScheme` and `appearance` (`ThemeAppearance`) are what the root applies.
- **Appearance.** One picker "Thème": "Automatique (iOS)", "Clair", "Sombre" (ADR 0013 §8). System writes `auto_theme` = 3 and keeps `theme`; Clair / Sombre write `auto_theme` = 0 and `theme` = 0 / 1. An `auto_theme` other than 0 or 3 is read as system (LOT-060 clamp at launch). The manual theme survives a relaunch: it is the stored value.
- **One scheme for every screen.** `View.appTheme(_:)` at the app root sets the hosting window's `overrideUserInterfaceStyle` (`.unspecified` follows iOS), as legacy's app delegate did: sheets, native screens and the reader's `WKWebView` (whose `prefers-color-scheme` reads the same trait) always agree; its `tintColor` is the accent too, for UIKit chrome (alerts). Going back to "Automatique (iOS)" follows iOS at once. It is a UIKit override rather than SwiftUI's `.preferredColorScheme`, whose return to nil (follow iOS) is applied by SwiftUI only to the windows it manages: the window override is the legacy mechanism and is checked in a real window (`AppThemeTests`).
- **Accent.** `.tint` at the root with a dynamic colour: the stored day accent in light mode, the night accent in dark mode, or the defaults (hue 190°). The slider shows the hue of the day accent (a colour an older version stored keeps its hue); moving it writes both accents. The slider is tinted with the day accent of its value, as legacy.
- **Dark brightness.** `ThemeAppearance.adjustedDark` is legacy's formula. The reader's dark surfaces (background, quote background, image placeholders, separators) go through it: at 100 % they are the LOT-083 palette unchanged; black stays black whatever the value, as in legacy's formula; at 0 % every dark surface of the reader is black (quotes and separators included), as legacy.
- **Reader.** `reader.css` reads `--app-action-light`, `--app-action-dark` and `--app-dark-*`, with the old values as fallbacks. `ReaderWebController.theme` sets them on `<html>` from the reader's content world exactly as `textScale` does (LOT-169): a document-start user script, again at `ready`, and a script on the shown document when the value changes (live, no reload). Every value is an `rgb()` the app formats from numbers; the CSP and script policy are unchanged.

## Edge cases

- A stored colour that does not parse (`{…}` with four numbers) reads as the default accent.
- A brightness outside 0...1.5 is shown and applied clamped; it is written back only when the user moves the slider.
- Hue 1.0 and 0.0 are the same red; the slider keeps the value the user chose.
- A theme change while the reader loads a page reaches the previous document; `ready` sets it again on the new one.

## Fixtures

None: no HFR page is read and no HFR fact is added (`HFR-PROTOCOL.md` unchanged). Tests: `ThemeSettingsModelTests` (legacy raw values over `InMemorySettingsStore`), `ThemeAppearanceTests` (the colour rules against `UIColor` and legacy values), `ReaderThemeTests` (computed colours in the real reader, dark and light, live), `AppThemeTests` (a manual theme overrides iOS in a real window and "Automatique" follows iOS again). **Pending capture:** none.

## Intentional differences from legacy

- One "Thème" picker (Automatique (iOS) / Clair / Sombre) instead of "Changement de thème" + "Luminosité du thème" (ADR 0013 §8; CHANGELOG-LEGACY 56). Same keys, same values.
- The settings sit on the screen behind the "Thème" row (LOT-119 shell), not inline in the form.
- Native screens keep the system's dark surfaces: the brightness slider applies to the reader. Legacy's Swift layer also scaled grouped-list rows and the editor background (`AppThemePalette`); those native surfaces belong to LOT-122 (darker dark, OLED, separators), which redraws them (CHANGELOG-LEGACY 56).
- Creating the model writes nothing; legacy wrote the brightness default on its first read.
- Not ported: the seasonal red accent (`theme_noel_disabled`, LOT-166), the camera luminosity handler (dead code), the time-based theme (UXD-23, dropped on record).

## Not in this lot

- "Style des messages" (`theme_style`): LOT-106 (GAP-052, UXD-09), not here; LOT-119's table is corrected.
- `theme_*_color_love` and `theme_*_color_superfavori` are read by the lots that draw those rows (reader quotes of my messages, super-favourites); they keep their keys (ADR 0013 §8).
- iCloud sync of the theme keys (ADR 0013): LOT-172.
