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
- Only `Défaut` and `REDFACE 3D Big` are offered for now (see below): a subset of legacy's eight, listed as a GAP row in the PR ledger (`b`, optional).

## Behaviour
- **Haptics.** Key `haptics` (already `SettingKey.haptics`, bool, default on, tolerant of strings and numbers). `HapticFeedback` reads the store at every call, so a change applies at once; `GeneralSettingsModel.hapticsEnabled` writes the same key. Every haptic of the app must call `HapticFeedback.live.impact(_:)` / `.notification(_:)` and never a UIKit generator directly.
- **Call sites.** `grep` of `App/` for `UIImpactFeedbackGenerator`, `UINotificationFeedbackGenerator`, `UISelectionFeedbackGenerator`, `sensoryFeedback`: none exist in the SwiftUI app today, so nothing is rewired. The ~35 legacy call sites (`refreshStarted`, `refreshCompleted`, `impact(.light)` on favourites, search, profile, composer result) are ported with their screens and must use `HapticFeedback` (reviewers check it).
- **Icon.** Key `icon` (`SettingKey.appIconName`, default `superblue`), same key and values as legacy. `AppIconSettingsModel.select(_:)` calls `setAlternateIconName` first and writes the key only when the system accepted; a refusal keeps both and shows a French alert. `superblue` is the primary icon (`Icon-RedFace3D`, #581), `redface3dbig` is `Icon-RedFace3DBig`, wired by `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in both app configurations. Unsupported devices (`supportsAlternateIcons` false): the rows are disabled with a footer.

## Edge cases
- A stored legacy value whose art is not shipped (`classic`, `classic-red`, `redface`, `redface-blue`, `beta`, `blue`, `white`) shows "Défaut" and is **left in the store**: nothing is lost and a later release can honour it. The home-screen icon the system kept from the legacy app is not touched at launch.
- Choosing the option already shown does nothing (no system alert about the icon change).

## Fixtures
None (no HFR page involved). Tests: `AppIconSettingsModelTests`, `HapticFeedbackTests` (App).

## Intentional differences from legacy
- Alternates restricted to art that is a layered `.icon` in the target. **Pending asset / Mac work:** the seven loose-PNG legacy sets (iPhone `@2x/@3x`, iPad `@1x/@2x`) need the legacy `CFBundleAlternateIcons` plist route, whose merge with the actool-generated `CFBundleIcons` cannot be checked from the Linux cloud; follow-up issue to open for the Mac. No icon was drawn or converted here.
- No preview thumbnails in the picker: a compiled `.icon` cannot be loaded as an image; text rows with a check mark. Previews are a pending asset.
- No `applyIconSelection` on every `onChange` as in legacy: the store is written only after success.

## Learnings
- A setting seam (`AlternateIconSwitching`) keeps `UIApplication` out of tests; a stored value the app cannot show must not be rewritten.
