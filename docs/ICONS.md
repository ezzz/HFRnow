# App icons

How SwiftHFR's alternate app icons are drawn, named, delivered and chosen. This file owns the **icon contract**; the picker's code and the legacy port are specified in [LOT-123](lots/LOT-123-alternate-icons-haptics.md) and not repeated. Themes are in [THEMES.md](THEMES.md), whose illustration style (§6) also applies to drawings inside icons.

Source: the operator's requests of 2026-10-28 and his reviews that day (Legacy and Beta packs validated). **Reference visuals**: the icon boards and the 1024 px masters in [`docs/assets/themes/`](assets/themes/README.md), validated by the operator as the latest version (2026-11-10). Items marked *(to confirm)* are names or wordings not yet decided.

## 1. Model (as shipped by LOT-123)

- Réglages › Icône lists `AppIconOption`s; a choice calls `setAlternateIconName` and is stored under the legacy key `icon` only once the system accepted it.
- Each icon is an Icon Composer file `App/SwiftHFR/Icon-<NAME>.icon`, listed in `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in both configurations. The name lives only in `AppIconOption.alternateIconName`: a redrawn icon swaps in under the same name.
- Raw values of the legacy options are the legacy `icon` values (`HFRswift/Swift/AppSettingsView.swift:33-83` @ `87fe0d1c`), so the choice survives the update. New options use a kebab-case raw value and an `Icon-<PACK>-<NAME>` file name (`noel-hfr` → `Icon-NOEL-HFR`).
- Apple (HIG › App icons, read 2026-10-28, re-read before quoting): alternate icons need their own dark, clear and tinted variants and go through App Review; 1024 px masters; no baked highlights, shadows or bevels (<https://developer.apple.com/design/human-interface-guidelines/app-icons>).

## 2. Packs

The picker groups icons by pack ([LOT-189](LOTS.md)). *Shipped* = in `dev-swift` today.

| Pack | Name (UI) | Raw value | What it is | Window | Status |
|---|---|---|---|---|---|
| Legacy | Défaut | `superblue` | primary icon `Icon-RedFace3D` | all year | shipped |
| | REDFACE 3D Big | `redface3dbig` | legacy layered art | all year | shipped |
| | REDFACE, REDFACE Blue | `redface`, `redface-blue` | legacy designs redrawn as SVG (#623) | all year | shipped |
| | Blue, White | `blue`, `white` | legacy 1024 px art | all year | shipped |
| | Classique Yellow, Classique Red | `classic`, `classic-red` | legacy designs redrawn as SVG (#623) | all year | shipped |
| | Classique Blue | `classic-blue` | legacy `HFRswift/Swift/Assets.xcassets/Classic-Blue.appiconset` @ `87fe0d1c` (primary of the `hfrplus-legacy` target) | all year | LOT-190 |
| | Orange | `orange` | Blue's layout, white HFR on `orange-hfr` | all year | LOT-190 |
| Beta | Beta | `beta` | legacy art | all year | shipped |
| | Beta rouge | `beta-red` | the Beta drawing in black on red, strokes slightly thicker | all year | LOT-190 |
| X-face | X-face, Fierté, Fierté contour, Dégradé clair, Dégradé sombre, Or, Or sur noir, Or contour, Terminal 5250, Négatif, Négatif inversé, Coucher de soleil | `xface-…` | the redface `:o` with variations: Pride flag with **diagonal** stripes (solid face, or strokes only), light and dark gradients after the Swift theme, gold (gold background, gold drawing on black, black outline on gold), green face (Rétro 5250), white on black and black on white, red-to-yellow gradient; the plain « X-face » and the « Coucher de soleil » names are proposals *(names to confirm)*; drawings: `icons-xface.jpg` | all year | LOT-190 |
| Saisons | Noël REDFACE | `noel-redface` | redface on white with a Santa hat, a fir tree with gifts in a bottom corner | 01/12–26/12 | LOT-189 |
| | Noël HFR | `noel-hfr` | the simple HFR icon (white on `orange-hfr`) on fir green, snow on the letters, a garland at the top, a snowman and a gift at the bottom | 01/12–26/12 | LOT-189 |
| | Halloween citrouille | `halloween-pumpkin` | the redface turned orange, mouth changed but centred, pumpkin sides and orange gradient | 01/10–31/10 | LOT-190 |
| | Halloween HFR | `halloween-hfr` | the simple HFR icon with a spider web, a bat and a tiny witch on a broom | 01/10–31/10 | LOT-190 |
| | Printemps | `spring` | a cherry tree in bloom partly hidden by the redface, dense background | all year | LOT-190 |
| | Été | `summer` | blue background, a big sun, a small coconut palm in the opposite corner, the redface with sunglasses | all year | LOT-190 |
| | Hiver | `winter` | the redface with a scarf as on `icons-season.jpg` (operator 15:40: « la précédente était mieux ») | all year | LOT-190 |

**Dated icons** are listed only inside their window. At the end of the window the icon stays (a switch must be the user's): on the first launch after the window the app asks once « Revenir à l'icône précédente ? » (decision Q4, 2026-10-28); the buttons [Oui] [Garder] are a proposal *(to confirm)*.

## 3. `orange-hfr`

The orange of the forum logo, used as a fill (Orange, Noël HFR, Halloween HFR, the OG themes, the « Orange HFR » accent preset), never as text (about 2.4:1 on white). Value: the colour of the logo square and « .FR » of `/img/forum_logo.gif`, **pending capture** ([#728](https://github.com/ezzz/HFRnow/issues/728)); no value is decided before it.

## 4. Style rules

1. Readable at 29 pt (Settings) and 60 pt (Home Screen): one main glyph (the `:o` face or the HFR letters), at most three secondary items.
2. **One face for all**: every face icon derives from `App/SwiftHFR/Icon-REDFACE.icon/Assets/foreground.svg`, whose proportions match the legacy `SuperHFRplus/Assets/AlternativeIcons/Icon-REDFACE@3x.png` @ `87fe0d1c` (checked by LOT-190 first; operator 2026-10-28: faces must not be deformed). Never stretch it; accessories scale with it.
3. Flat colours and plain gradients; « shiny » gold is a gradient, never a baked highlight.
4. Season items follow THEMES.md §6; original art only, generic symbols (Pride flag, seasonal items).

## 5. Submitting an icon (agents and humans)

1. Open an issue `[SwiftHFR] Icon: <name>` (`### Summary`, pack, window), wait for `status: ready`, claim it.
2. Add `App/SwiftHFR/Icon-<PACK>-<NAME>.icon` with Default, Dark and Tinted annotations and its SVG master; add it to `AppIconOption` (pack, window) and to the alternate names in both configurations.
3. PR checklist:
   - [ ] screenshots at 1024 px and on light and dark Home Screens, in Clear and Tinted
   - [ ] readable at 29 pt
   - [ ] dated icon hidden outside its window (test with an injected calendar)
   - [ ] a legacy raw value kept when the icon replaces a legacy one
   - [ ] original art, [CREDITS.md](../CREDITS.md) AlternativeIcons table updated
