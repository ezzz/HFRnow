# LOT-123 — Alternate app icons and haptics

- **Module:** App
- **Difficulty / model:** easy (Sonnet 5.5 → Opus 5.5)
- **Issue:** #214

## Legacy sources
- `HFRswift/Swift/AppSettingsView.swift:40-80` @ 2440d79: `AppIconOption` (eight values, `alternateIconName`), `:92` `@AppStorage("haptics")` (default true), `:94` `@AppStorage("icon")` (default `superblue`), `:178` `hasAlternateIconSupport`, `:213-224` `applyIconSelection` (`UIApplication.setAlternateIconName`, error shown in an alert), `:357-365` the toggle and the picker, `:524` `onChange(of: iconValue)`.
- `HFRswift/Swift/Common.swift:50-85` @ 2440d79: `AppHaptics` (`isEnabled` tolerant of Bool, number and string; `impact`, `notification`).
- `SuperHFRplus/Helpers/UIImpactFeedbackGenerator+UserDefaults.m` @ 2440d79: `impactOccurredWithDefaults` plays only when `haptics` is on.
- `HFRswift/Info.plist:37-137` @ 2440d79: the alternates are loose PNGs (`Icon-CLASSIC`, `-RED`, `-BLUE`, iPad variants) listed under `CFBundleAlternateIcons`. Art: `SuperHFRplus/Assets/AlternativeIcons/` (PNG sets `BETA`, `BLUE`, `CLASSIC`, `CLASSIC-RED`, `REDFACE`, `REDFACE-BLUE`, `WHITE`, plus the layered `Icon-RedFace3DBig.icon`).

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ 2440d79 |
|---|---|
| `Settings/AppIconSettingsModel.swift` (`AppIconOption`, `AppIconSettingsModel`) | `AppSettingsView.swift` (`AppIconOption`, `applyIconSelection`) |
| `Settings/AppIconSettingsView.swift` | `AppSettingsView.swift` (icon `Picker`) |
| `Common/HapticFeedback.swift` | `Common.swift` (`AppHaptics`), `UIImpactFeedbackGenerator+UserDefaults.m` |
| `GeneralSettingsModel.hapticsEnabled` + toggle in `SettingsView` | `AppSettingsView.swift` (`Toggle("Retours haptiques")`) |

## UX evolutions (app lots)
- The picker is a screen behind the "Icône" row (LOT-119 shell), not an inline picker: same class as the other LOT-119 rows, no new GAP row.
- Legacy's eight options plus `REDFACE 3D Big` (new). The art is the layered `.icon` of each set from the Mac art PR (#623: five redone, `Icon-BLUE` and `Icon-WHITE` reused); icon art, its credits and `CREDITS.md` come from that work, not from this lot.

## Behaviour
- **Haptics.** Key `haptics` (already `SettingKey.haptics`, bool, default on, tolerant of strings and numbers). `HapticFeedback` reads the store at every call, so a change applies at once; `GeneralSettingsModel.hapticsEnabled` writes the same key. Every haptic of the app must call `HapticFeedback.live.impact(_:)` / `.notification(_:)` and never a UIKit generator directly.
- **Call sites.** `grep` of `App/` for `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`, `UISelectionFeedbackGenerator`, `sensoryFeedback`: none exist in the SwiftUI app today, so nothing is rewired. The ~35 legacy call sites (`refreshStarted`, `refreshCompleted`, `impact(.light)` on favourites, search, profile, composer result) are ported with their screens and must use `HapticFeedback` (reviewers check it).
- **Icon.** Key `icon` (`SettingKey.appIconName`, default `superblue`), same key and values as legacy. `AppIconSettingsModel.select(_:)` calls `setAlternateIconName` first and writes the key only when the system accepted; a refusal keeps both and shows a French alert. `superblue` is the primary icon (`Icon-RedFace3D`, #581), each other legacy value maps to its legacy name (`Icon-CLASSIC` …, `Icon-WHITE`), and `redface3dbig` to `Icon-RedFace3DBig`; all are in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in both configurations. Names live in `AppIconOption.alternateIconName` only: a redrawn `.icon` swaps in under the same name. Unsupported devices (`supportsAlternateIcons` false): the rows are disabled with a footer.

## Edge cases
- Every legacy value is an option, so the update keeps the choice (same key). An unknown stored value shows "Défaut" and is **left in the store**. The home-screen icon the system kept from the legacy app is not touched at launch.
- Choosing the option already shown does nothing (no system alert about the icon change).

## Fixtures
None (no HFR page involved). Tests: `AppIconSettingsModelTests`, `HapticFeedbackTests` (App).

## Intentional differences from legacy
- The checked row follows the icon the system shows, not only the key: legacy wrote the key before applying, so a refused switch left them apart.
- No `applyIconSelection` on every `onChange` as in legacy: the store is written only after success.

## Learnings
- A setting seam (`AlternateIconSwitching`) keeps `UIApplication` out of tests; a stored value the app cannot show must not be rewritten.
