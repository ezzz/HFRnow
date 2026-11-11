# LOT-166 — Seasonal themes engine and the Noël themes

- **Module:** App (`Settings/Seasons/`, `ThemeSettingsModel.swift` `appTheme`, `ThemeSettingsView.swift`, `SwiftHFRApp.swift`); engine: the `season.*` keys of `SettingKey` (HFRStorage, `SettingKey+Seasons.swift`)
- **Difficulty / model:** difficult (Opus 5.5 author, Fable 5.1 review)
- **Issue:** [#256](https://github.com/ezzz/HFRnow/issues/256) (umbrella FEAT-010 [#154](https://github.com/ezzz/HFRnow/issues/154))
- **Depends on:** LOT-122 (appearance model); PR 4 only: LOT-188 (theme engine, #729)
- **Contract:** [THEMES.md](../THEMES.md) §4 (decorations), §5 (seasons and events), §6 (illustration style), §7 (layouts). This file says how the app does it and what each PR delivers; it does not repeat the contract.

Delivery, per the issue's minimal slice: **PR 1** scheduler, settings section, Noël soft, arrival alert; **PR 2** sleigh and crossing objects; **PR 3** elves (packing animation); **PR 4** Noël abusé (needs LOT-188).

## Legacy sources
All @ `87fe0d1c`:
- `Classes/HFRplusAppDelegate.m:627-677` (`applicationDidBecomeActive`): window 24/12/2022–09/01/2023 hard-coded (`:635-636`), `noel_first_time_2022` switches the theme on once (`:645-651`), alert « C'est bientôt Noël ! » (`:665-676`). Forced off at launch and in `setTheme` (`:103`, `:365`), so the theme never shows at the reference.
- `HFRswift/Swift/Common.swift:610-612, 625-627`: the accent is `UIColor.red` in both variants while `theme_noel_disabled` is off.
- `Classes/HFRNavigationController.m:85-90, 134-139`, `Classes/HFRplusAppDelegate.m:382-388`: an animated `snow` image tiled as the navigation bar's background; frames `SuperHFRplus/Assets/UI/snow/snow1…16.png` (added 2018-12-13, `43cf00cf`, no source or licence stated: not shipped, snow is drawn procedurally).
- `Classes/PlusSettingsViewController.m:112-115`: the Noël cell is shown only while `theme_noel_period`.

## Legacy counterpart (app lots)
| SwiftHFR | Legacy @ 87fe0d1c |
|---|---|
| `NoelCalendar` | `HFRplusAppDelegate.m:635-636` (the dates) |
| `SeasonalThemeModel` | `HFRplusAppDelegate.m:627-677` (`applicationDidBecomeActive`) |
| `ThemeAppearance.applying(_:)` | `Common.swift:610-612, 625-627` |
| `NoelSnowLayer`, `SnowField` | `HFRNavigationController.m:85-90, 134-139`, `HFRplusAppDelegate.m:382-388` |
| `SeasonalThemesSection` | `PlusSettingsViewController.m:112-115` |
| `SeasonalArrivalAlert` | `HFRplusAppDelegate.m:665-676` |

## UX evolutions (app lots)
All under GAP-147, class `b·operator` (operator, 2026-10-28; THEMES.md §5): yearly windows; Noël soft switched on once per season; « Désactiver » opts out for the year; previous theme restored; « Thèmes de saison automatiques » and « Animations de saison »; the operator's alert text. The theme is reachable at all, which legacy's forced-off flag prevented.

## Behaviour
- **Calendar** (`NoelCalendar`): Gregorian dates in the device's time zone (`TimeZone.autoupdatingCurrent`), whatever its calendar (a Buddhist or Japanese year would name other keys); a season is named after the year of its December (the 2026 season ends on 02/01/2027). Phases: 01/12–24/12 `switchOn`, 25–26/12 `arrivalOnly`, 27/12–02/01 `packing`, otherwise `outside`. Selectable = the first two.
- **State** (device-only, ADR 0013 matrix E): `season.noel.<year>.arrivalShown`, `.arrivalPending`, `.optedOut`, `.previousThemeID`, `.packingShown`; `season.noel.activeYear`, the season whose theme is on; toggles `season.automatic` and `season.animations` (both default on). A Noël theme of season Y is on exactly while `previousThemeID(Y)` is stored, and `activeYear` is Y then.
- **Scheduler** (`SeasonalThemeModel.sceneDidBecomeActive`, called on every scene activation): (1) a theme still on from any earlier season (`activeYear` < Y) is restored silently; (2) in a selectable phase, the first activation sets `arrivalShown` and `arrivalPending`, switches Noël soft on when the phase is `switchOn`, « Thèmes de saison automatiques » is on and the season is not opted out, and the alert stays pending until answered, across launches (dropped when the window closes); (3) in `packing` with a theme on, the first activation sets `packingShown` and restores (`packed`, animated only when animations are allowed: the elves of PR 3), later ones restore silently; (4) `outside` with a theme on: silent restore. Each activation returns the events it caused (`arrival`, `packed`, `restoredSilently`).
- **Noël soft**: the current look, the user's appearance and dark style, with legacy's red accent drawn over it (`ThemeAppearance.applying`). Nothing of the "Thème" settings is written, so restoring is dropping `previousThemeID` and gives the user's theme and accent back exactly. Until LOT-188 there is one theme, saved as `legacy`; with LOT-188 the saved id is the `theme_id` to write back.
- **Arrival alert** (`SeasonalArrivalAlert`): « Oh Oh Oh ! » / « Thème disponible dans les réglages » [OK] [Désactiver], a system alert (spoken by VoiceOver). Each scene asks the model every second while an arrival is pending; it is presented only when the app lock does not cover the screen, nothing is presented over the window's root (sheet, composer, cover, another alert) and the keyboard is down (THEMES.md §4 rule 5), and by one scene only (iPad with two windows: the other gets it if the first goes away unanswered). « Désactiver » restores and sets `optedOut`; either answer clears `arrivalPending`. PR 2 plays the sleigh before it when `sleigh` is true.
- **Snow**: 28 procedural flakes (`SnowField`, fixed seed) in a `Canvas` driven by `TimelineView(.animation(minimumInterval: 1/30, paused:))`. Drawn over the root content between a 56 pt top band and a 64 pt bottom band inside the safe area, so the navigation bar's buttons, the tab bar, the status bar and the home indicator stay clear (a large title is about 96 pt high: flakes may cross its text, not its buttons; PR 2 refines the band); sheets, the keyboard and the lock cover are above it. No hit testing, hidden from accessibility. Flakes fall only with animations allowed (setting on, Reduce Motion off); the timeline is paused while the scene is not active and in Low Power Mode.
- **Settings**: Réglages › Thème shows « Thèmes de saison » only in a selectable phase: « Thème habituel » / « Noël soft », then the two toggles.

## Edge cases
- Two activations the same day, or a cold launch after a background return: the arrival and the packing play once per season (`arrivalShown`, `packingShown`).
- App not opened during the packing days: silent restore at the next activation, however many seasons later (step 1, `activeYear`).
- App killed before the arrival alert was answered (or the alert held back by a sheet or the keyboard): it shows again at the next launch while the window is open.
- 25–26/12 first launch: the alert shows, nothing is switched on; Noël soft can still be picked by hand until 26/12 and is packed on 27/12.
- « Thèmes de saison automatiques » off: the arrival alert still shows (as on 25/12), nothing is switched on. *(to confirm with the operator, see the PR)*
- Reduce Motion or « Animations de saison » off: the arrival is the alert alone, packing restores without the elves, no snow is drawn.
- The first frame of a launch outside the window never shows a theme left on (`refresh` ignores it before the restore).

## Fixtures
None: no HFR page is read. Tests use an injected clock and a Europe/Paris Gregorian calendar.

## Intentional differences from legacy
See GAP-147 (edited in PR 1's ledger): yearly windows instead of hard-coded dates; opt-out per year; previous theme restored; the theme reachable; procedural snow over the content instead of the navigation bar frames (licence unknown); the operator's alert. Legacy's festive alert decorations (`ThemeManager.m:213-245`) and Noël tab icons are not ported (issue #256).

## Not yet (later PRs of this lot)
Sleigh and crossing objects (PR 2), snow piled on cards and the bottom edge (PR 2: a first drift drawn over the content crossed row text), elves (PR 3), Noël abusé (PR 4); pausing the snow while a list scrolls and the Instruments figures on a device (THEMES.md §4 rule 8) come with PR 2's overlay work.

## Learnings
To copy into AGENTS.md §11 when the lot closes.
