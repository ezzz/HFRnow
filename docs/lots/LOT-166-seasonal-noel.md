# LOT-166 — Seasonal themes engine and the Noël themes

- **Module:** App (`Settings/Seasons/`, `ThemeSettingsModel.swift` `appTheme`, `ThemeSettingsView.swift`, `SwiftHFRApp.swift`; PR 2: `Assets.xcassets/Noel/`, the scroll reports of `ForumListView`, `TopicListView`, `MessageListView` and `ReaderWebController`); engine: the `season.*` keys of `SettingKey` (HFRStorage, `SettingKey+Seasons.swift`)
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
| `NoelCrossingModel`, `NoelCrossingLayer`, `CrossingPath` (sleigh and crossing objects), `SnowPileLayout` (piled snow) | none: legacy had no animation and no piled snow (GAP-147, THEMES.md §4–§5) |

## UX evolutions (app lots)
All under GAP-147, class `b·operator` (operator, 2026-10-28; THEMES.md §5): yearly windows; Noël soft switched on once per season; « Désactiver » opts out for the year; previous theme restored; « Thèmes de saison automatiques » and « Animations de saison »; the operator's alert text. The theme is reachable at all, which legacy's forced-off flag prevented.

## Behaviour
- **Calendar** (`NoelCalendar`): Gregorian dates in the device's time zone (`TimeZone.autoupdatingCurrent`, read at each use, so a zone change during a run is followed), whatever its calendar (a Buddhist or Japanese year would name other keys); a season is named after the year of its December (the 2026 season ends on 02/01/2027). Phases: 01/12–24/12 `switchOn`, 25–26/12 `arrivalOnly`, 27/12–02/01 `packing`, otherwise `outside`. Selectable = the first two.
- **State** (device-only, ADR 0013 matrix E): `season.noel.<year>.arrivalShown`, `.arrivalPending`, `.optedOut`, `.previousThemeID`, `.packingShown`; `season.noel.activeYear`, the season whose theme is on; toggles `season.automatic` and `season.animations` (both default on). A Noël theme of season Y is on exactly while `previousThemeID(Y)` is stored, and `activeYear` is Y then.
- **Scheduler** (`SeasonalThemeModel.sceneDidBecomeActive`, called on every scene activation): (1) a theme still on from any other season (`activeYear` ≠ Y: an earlier one, or a later one switched on under a clock that ran ahead and was set back) is restored silently; (2) in a selectable phase, the first activation sets `arrivalShown` and `arrivalPending`, switches Noël soft on when the phase is `switchOn`, « Thèmes de saison automatiques » is on and the season is not opted out, and the alert stays pending until answered, across launches (dropped when the window closes); (3) in `packing` with a theme on, the first activation sets `packingShown` and restores (`packed`, animated only when animations are allowed: the elves of PR 3), later ones restore silently; (4) `outside` with a theme on: silent restore. Each activation returns the events it caused (`arrival`, `packed`, `restoredSilently`).
- **Noël soft**: the current look, the user's appearance and dark style, with legacy's red accent drawn over it (`ThemeAppearance.applying`). Nothing of the "Thème" settings is written, so restoring is dropping `previousThemeID` and gives the user's theme and accent back exactly. The saved id is LOT-188's stored `theme_id` (`legacy` when none is stored; the first build always saved `legacy`, which reads the same). **Over a gallery theme** (operator decision (a), 2026-11-12): the red accent is drawn over Legacy only; a gallery theme keeps its own accent (its `accentText`, held to its contrast rules) and gets the snow and the crossings.
- **Arrival alert** (`SeasonalArrivalAlert`): « Oh Oh Oh ! » / « Thème disponible dans les réglages » [OK] [Désactiver], a system alert (spoken by VoiceOver). Each scene asks the model every second while an arrival is pending; it is presented only when the app lock does not cover the screen, nothing is presented over the window's root (sheet, composer, cover, another alert) and the keyboard is down (THEMES.md §4 rule 5), and by one scene only (iPad with two windows: the other gets it if the first goes away unanswered). « Désactiver » restores and sets `optedOut`; either answer clears `arrivalPending`. PR 2 plays the sleigh before it when `sleigh` is true.
- **Snow**: 28 procedural flakes (`SnowField`, fixed seed) in a `Canvas` driven by `TimelineView(.animation(minimumInterval: 1/30, paused:))`. Drawn over the root content in `NoelBand`: a 104 pt top band (the navigation bar with a large title, about 96 pt) and a 64 pt bottom band inside the safe area, so no large title, navigation button, tab bar, status bar or home indicator is crossed; sheets, the keyboard and the lock cover are above it. One band for the whole window: on an iPad split view the columns share it (an inline-title column keeps about 50 pt without snow under its bar). No hit testing, hidden from accessibility. Flakes fall only with animations allowed (setting on, Reduce Motion off); the timeline is paused while the scene is not active, in Low Power Mode and while a list or the reader scrolls (`SeasonalScrollActivity`: `onScrollPhaseChange` on the Catégories, topic and MP lists, the web view's pan gesture and deceleration for the reader).
- **Piled snow** (static, so it stays with Reduce Motion): the operator's snow-pile render as two caps on the top edge of the Catégories card, 11 pt high, reaching 3 pt below the card's top edge (behind the card, which covers their base; less than a Catégories row's 8 pt top padding in any case) (`SnowPileLayout.capFrames`); they are the header of the card's section (`SeasonalSnowCapSection`, Noël soft only: otherwise the rows are given as they are), since a cell clips what leaves it, so the card covers their base; and two drifts, at most 16 pt high, in the bottom safe area, in the corners either side of a 160 pt clearance for the home indicator (`bottomFrames`); none on a window without a bottom safe area. Neither reaches a line of text (THEMES.md §4 rule 7).
- **Arrival sleigh**: when the arrival fires with animations allowed, `NoelCrossingModel.queueArrival()`; the alert waits (`alert(for:screen:)` returns nil) while the sleigh is due or crossing. The sleigh is the render of Santa's sleigh pulled by two reindeer harnessed in front, drawn facing the trailing edge; it crosses one scene's band from one side to the other, a quarter of the window height (at most 240 pt), in 3 s, tilted by at most 15°, mirrored as a whole when it goes right to left and turned along its line (`CrossingPath.facing`), with one light haptic. It waits for a clear screen like the alert, stops when the keyboard, a sheet, an alert or the lock comes up, and a tap closes it (THEMES.md §4 rule 3). Without animations it is dropped and the alert comes alone. It is in-memory: an app killed before it played shows the pending alert alone at the next launch.
- **Crossing objects** (`NoelCrossingModel`, injected clock and random source): foreground time is counted from the scene phase (`foregroundChanged(active:)`), background time never counts; the gap is drawn uniformly in 20–90 min at launch and at each crossing, and restarts at each crossing, so two crossings are never less than 20 min of foreground time apart (a new launch starts from zero). Once spent, with Noël soft on, animations allowed and a clear screen, one scene gets one object, 64 pt high, for 2.2–3 s: the small sleigh (faces its travel), a star, a gift in three colours, an ornament or a snowflake (upright: no front). Its path (`CrossingPath.random`) enters by a random edge, fully outside, and leaves by the opposite one, fully outside, at a random tilt (at most 30°) inside the band, which clips it. One light haptic per crossing through `HapticFeedback` (the haptics setting applies; none without animations, so none with Reduce Motion). Each scene's layer asks every 15 s (every 0.5 s while the sleigh waits), never per frame, and draws a `TimelineView` only while its object crosses.
- **Settings**: Réglages › Thème shows « Thèmes de saison » only in a selectable phase: « Thème habituel » / « Noël soft », then the two toggles.

## Edge cases
- Two activations the same day, or a cold launch after a background return: the arrival and the packing play once per season (`arrivalShown`, `packingShown`).
- App not opened during the packing days: silent restore at the next activation, however many seasons later (step 1, `activeYear`).
- App killed before the arrival alert was answered (or the alert held back by a sheet or the keyboard): it shows again at the next launch while the window is open.
- 25–26/12 first launch: the alert shows, nothing is switched on; Noël soft can still be picked by hand until 26/12 and is packed on 27/12.
- « Thèmes de saison automatiques » off: the arrival alert still shows (as on 25/12), nothing is switched on. *(to confirm with the operator, see the PR)*
- Reduce Motion or « Animations de saison » off: the arrival is the alert alone, packing restores without the elves, no snow falls, nothing crosses and nothing buzzes; piled snow stays (static).
- A sheet or the keyboard comes up while an object crosses: it stops at once; the gap restarted when it began.
- A rotation, split view or Stage Manager resize during the arrival sleigh restarts the layer's watch: the sleigh is queued again (`interrupt`) and plays again before the alert, at most twice; after that the alert comes alone. An ordinary object cut that way just ends.
- iPad with two windows: one crossing at a time, in one scene; a scene that goes away stops its crossing.
- The first frame of a launch outside the window never shows a theme left on (`refresh` ignores it before the restore).

## Fixtures
None: no HFR page is read. Tests use an injected clock and a Europe/Paris Gregorian calendar.

## Intentional differences from legacy
See GAP-147 (edited in PR 1's ledger): yearly windows instead of hard-coded dates; opt-out per year; previous theme restored; the theme reachable; procedural snow over the content instead of the navigation bar frames (licence unknown); the operator's alert. Legacy's festive alert decorations (`ThemeManager.m:213-245`) and Noël tab icons are not ported (issue #256).

## Art
The operator's validated renders only (`docs/assets/themes/renders/`, 2026-11-10): `noel_sleigh` (reindeer in front, checked), `noel_star`, `noel_gift`, `noel_gift_blue`, `noel_gift_gold`, `noel_ornament`, `noel_snowflake`, `noel_snowpile`, trimmed and scaled into `Assets.xcassets/Noel/` by `tooling/art/noel-crossings/derive.swift` (no pixel drawn; CREDITS.md « Seasonal art »). The tokens' `gift-parachute` and `snowman-sled` have no render: plain gifts cross instead, and no snowman.

## Not yet (later PRs of this lot)
Elves (PR 3), Noël abusé (PR 4). The Instruments figures (THEMES.md §4 rule 8) are measured by the operator on a device (protocol in PR 2's description).

## Learnings
To copy into AGENTS.md §11 when the lot closes.
