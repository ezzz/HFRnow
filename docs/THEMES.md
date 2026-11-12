# Themes

How a SwiftHFR theme is built, scheduled, credited and submitted. This file owns the **theme contract**: lot specs link here instead of repeating it. App icons are in [ICONS.md](ICONS.md). What already ships is specified elsewhere and not repeated: appearance, accent hue and dark brightness in [LOT-121](lots/LOT-121-theme-parity.md), dark styles in [LOT-122](lots/LOT-122-appearance.md) and [FEAT-010](features/FEAT-010.md), text size and density in LOT-169.

Source: the operator's requests of 2026-10-28 and the decisions taken that day. **Reference visuals**: the boards, icons and renders in [`docs/assets/themes/`](assets/themes/README.md), validated by the operator as the latest version (2026-11-10); where this text and a board differ, ask the operator. Items marked *(to confirm)* are rules or wordings not yet decided.

## 1. What the user sees

- **Réglages › Thème** keeps its shipped pickers (« Thème » Automatique (iOS) / Clair / Sombre, « Teinte d'accent », « Style du thème sombre », « Luminosité du thème sombre »; the last three are Legacy's and show while Legacy is the theme) and adds a **gallery** below them ([LOT-188](lots/LOT-188-theme-engine.md); [LOT-180](lots/LOT-180-single-accent.md) moves it into a « Thème » sub-menu with a light and dark preview per theme):
  - themes grouped by **family** (Classiques, Rétro, OG Web, and a seasonal family only inside its window, §5);
  - each row: a light and a dark swatch (one swatch and *clair = sombre* for a single-variant theme), the name, *par &lt;auteur&gt;*, a check mark on the active theme;
  - toggles « Thèmes de saison automatiques » and « Animations de saison » (both on by default, §4–§5);
  - footer: *Envie de proposer un thème ? Les règles sont dans le dépôt : docs/THEMES.md (voir le README).*
- The appearance (light / dark / follow iOS) is a general setting, independent of the theme. A single-variant theme looks the same in both.

**Apple's position** (read 2026-10-28; re-read before quoting it in a PR): the App Review Guidelines have no Dark Mode rule (<https://developer.apple.com/app-store/review/guidelines/>); the HIG advises against an app-specific appearance setting (<https://developer.apple.com/design/human-interface-guidelines/dark-mode>). SwiftHFR keeps it for legacy parity (LOT-121, operator 2026-10-28): a HIG deviation, not a rejection risk.

## 2. Built-in themes

| Theme | Family | Credit (as shown) | Variants | Lot | Notes |
|---|---|---|---|---|---|
| Legacy | Classiques | par Ezzz | light, dark | 188 | Today's app, unchanged: LOT-121/122 colours, hue slider, dark styles. Default. Accent presets: [LOT-180](LOTS.md) |
| Swift | Classiques | — | light, dark | 192 | Night-blue background, soft cards, halos, violet accent (board `theme-swift.jpg`) |
| Rétro 5250 | Rétro | — | single | 192 | Green on black, monospace, inspired by IBM 5250 terminals (no trademark in the name) |
| OG clair, OG gris | OG Web | — | single each | 193 | The web forum's two skins; colours only from the captured stylesheets |
| Noël soft | Noël | — | light, dark | 166 | Light snow, snow piled here and there, a Christmas item crossing now and then |
| Noël abusé | Noël | — | single | 166 | Lots of colour and Christmas drawings |
| Spooktober soft | Samain | — | light, dark | 191 | A bit of spider web, a candelabra, a small bat; crossing ghost, witch, lightning |
| Spooktober abusé | Samain | — | single | 191 | Lots of Halloween colour and drawings, dominant orange, black, purple |

Authors also go to [CREDITS.md](../CREDITS.md).

## 3. Theme model

A theme is a folder `App/SwiftHFR/Themes/<theme-id>/` (folder-synchronized group, [ADR 0012](adr/0012-app-project-file-strategy.md)). Xcode copies the resources of such a folder flat into the app bundle, so every file name is unique across themes: the token file is `<theme-id>.theme.json`, never `theme.json`, and art files carry the theme id too ([LOT-188](lots/LOT-188-theme-engine.md)).

| File | Content |
|---|---|
| `<theme-id>.theme.json` | `id` (kebab-case, the folder name), `name`, `family`, `author` (optional), `fontDesign` (`default` / `rounded` / `monospaced`, default `default`), `decorations` (id or null), `variants` (`light` + `dark`, or `any`); colours `#RRGGBB` or `#RRGGBBAA` |
| `Decorations/` | optional art (PDF or PNG); sources next to the scripts that make them |

**Legacy** is the exception: its file names it and carries no `variants`, because its look is LOT-121/122's code (hue slider, dark styles, brightness), which the engine leaves untouched. Every other theme defines every token. A test fixture is in `App/SwiftHFRTests/Settings/ThemeFixtures/test-theme.theme.json`: copy it to start a theme.

**Tokens** (every variant defines all of them; the contrast rule is a unit test of LOT-188, WCAG 2.x relative luminance, no 3:1 large-text exception):

| Token | Use | Rule |
|---|---|---|
| `background`, `surface`, `surfaceRaised` | screen, rows and cards, bars and sheets | `accentText` ≥ 4.5:1 on `background`; `textPrimary` ≥ 4.5:1 on `surfaceRaised` (the header band and page bar fall back to it) |
| `title`, `sectionHeader` | text drawn on `background` | ≥ 4.5:1 on `background` |
| `textPrimary`, `textSecondary` | body text; dates, counters, read MP titles (#651) | ≥ 4.5:1 on `surface` |
| `accent`, `onAccent` | fills only (badges, toggles, selection); content on them | `onAccent` ≥ 4.5:1 on `accent` |
| `accentText` | accent used as text or glyph | ≥ 4.5:1 on `surface` |
| `link` | links in messages | ≥ 4.5:1 on `surface` |
| `separator`, `selection` | separators (one definition, #572), selected row | — |
| `quoteBackground`, `quoteBorder`, `codeBackground`, `codeText`, `spoilerBackground`, `spoilerText` | reader blocks (`[code]` always monospace) | text ≥ 4.5:1 on its background |
| `unread`, `onUnread` | unread badge and capsule (#646) | ≥ 4.5:1 |

The quote rule is `textPrimary` and `textSecondary` (a quote's header) on `quoteBackground`. The test also checks every other pair the app draws ([LOT-188](lots/LOT-188-theme-engine.md) lists them): links and accents on quotes, spoilers, code and the reader's even message, the optional tokens, and, since native list rows and text keep the system colours of the appearance a theme shows in, the system text of that appearance (black in light, white in dark; a `light` slot always shows in light) on `background` and `surface`, and `accentText` (the tint) on the system card and on `background`. A colour in a contrast pair is opaque.

**Where LOT-188 draws each token.** Tint: `accentText`; prominent buttons: `accent` and `onAccent`; every themed screen: `background`; unread capsule: `unread`, `onUnread`; the reader: `surface` (its page), `textPrimary`, `textSecondary`, `link`, `accentText`, `separator`, the quote, code and spoiler tokens. Not drawn yet: `surfaceRaised`, `title`, `sectionHeader`, `selection` and the optional tokens; native rows and text keep the system's (operator decision of 2026-11-12: (a); native rows, separators, selection and text are #842). A single-variant theme shows in the appearance its background reads as (light when black text contrasts more), whatever the « Thème » picker says.

Optional tokens for table-like themes fall back to the tokens above, so a theme that omits them is unchanged (LOT-193): `headerBand` → `surfaceRaised`, `alternateCell` → `surface`, `meta` → `textSecondary`, `pageBar` → `surfaceRaised`, `counter` → `textSecondary`. Any other name is an error.

The reader receives tokens through CSS variables on the LOT-121/122 path (LOT-188 adds `--app-theme-light-*`, `--app-theme-dark-*` and `--app-theme-font`, read only while `<html>` carries `data-app-theme`; the page is `surface`); #568's derived tokens (`--surface-alt`, `--separator-strong`) stay derived. User colours of the reader (`theme_*_color_love`, `_superfavori`) remain user settings, not tokens.

## 4. Decorations

Optional, drawn in two layers: behind the content and in front of it. Rules, enforced in review and by tests where possible:

1. **Reduce Motion** on: no animation and no haptic; static decorations may stay; arrival = the alert alone; packing and 14 July skipped.
2. **« Animations de saison »** off: same as Reduce Motion.
3. **Overlays** (arrival, packing, 14 July) last at most 5 s (14 July: 3–5 s), close on a tap, play once.
4. **Crossing objects** (operator, 2026-10-28): at most one every 20–90 min of foreground time, never sooner than 20 min; enter by one edge and leave by the opposite one along a straight line at a random angle and direction; face the direction of travel; cross in ≤ 3 s, about a quarter of the screen for arrivals (operator 2026-10-28: 1/5, then « légèrement plus gros »; board `events.jpg`); a light haptic while crossing through `HapticFeedback.live` (the haptics setting applies, LOT-123). **Lightning** is the exception: 5 flashes of about 0.3 s at random places within 3 s.
5. **Never over input**: nothing appears while the keyboard is up, the composer, a sheet or an alert is shown.
6. **VoiceOver-silent**: decorations are hidden from accessibility; the arrival popup is a normal, spoken alert.
7. **Text keeps its contrast**: art behind text is faded or kept out of text columns; any decoration on a dark background is ≥ 3:1 (WCAG 1.4.11; the Spooktober soft bat in grey or violet, operator 2026-10-28).
8. **Performance** (LESSONS 49): no per-frame work when nothing moves; falling snow paused when inactive, in Low Power Mode and while scrolling; the PR quotes Instruments numbers (target: idle CPU ≤ 3 %, no hitch scrolling a list).
9. Decorations never cover the status bar, the home indicator, navigation buttons or a badge.

## 5. Seasons and events

Local calendar dates; "first launch" = first scene activation on or after the date, once per year. State in the settings store (new `SettingKey`s, device scope).

| Family / event | Selectable | Switched on automatically | Arrival (first launch) | Packing (first launch) |
|---|---|---|---|---|
| Noël | 01/12–26/12 | Noël soft, 01/12–24/12, unless opted out this year or « Thèmes de saison automatiques » is off | 01/12–26/12: Santa's sleigh **pulled** by its reindeer crosses the screen, then « Oh Oh Oh ! Thème disponible dans les réglages » [OK] [Désactiver]. Operator 2026-10-28: arrival on the first launch 01/12–24/12, Noël soft « s'active par défaut le 01/12 »; decision Q2 of the same day kept the arrival animation on 25–26/12 without switching anything on | 27/12–02/01, if a Noël theme is active: elves take the decorations down (≤ 5 s), « Allez on remballe » (operator: « premier lancement après le 26/12 »); the 7-day bound and the silent restore after it are decision Q3 of 2026-10-28 *(to confirm)* |
| Samain | 01/10–31/10 | Spooktober soft, 01/10–31/10, same conditions | 01/10–31/10: a witch on a broom, a ghost or a bat/vampire crosses, then « Spooktober est là ! Thème disponible dans les réglages » [OK] [Désactiver] | from 01/11 (operator, 2026-10-28: « Pour la fin d'Halloween, je prends le 01/11 »), 7-day bound as Noël *(to confirm)*, if a Samain theme is active: a witch sweeps the decorations away (≤ 5 s), « Allez on remballe »; later: silent restore |
| Fête nationale | — | — | 14/07: statue-like bust of Marianne with fireworks, « Fête nationale », 3–5 s, any theme | — |

- Switching a seasonal theme on saves the current theme; **Désactiver** restores it and opts out for the year; **OK** keeps the seasonal theme. Packing always restores it (fallback: Legacy).
- A seasonal theme picked by hand is packed the same way.
- Legacy @ `87fe0d1c` had a Christmas mode (red accent, snow in the navigation bar, a one-time alert; `Classes/HFRplusAppDelegate.m:627-677`), hard-coded to 24/12/2022–09/01/2023 and forced off at launch (`:103`, `:365`). The windows, opt-out and animations above are intentional differences (GAP-147).
- A new season (the PO's wish for one theme per season, #256) is a new family: add its row here in the PR that adds it.

## 6. Illustration style

One family for every drawing (Noël, Samain, 14 July and whatever comes next), so that a new theme matches:

1. Style 1, « digital sketching » (operator's choice, 2026-10-28): flat colour areas, little worked shading (« aplats de couleurs sans ombrage vraiment travaillé », his references: statues); contours as on the boards (`style-charter.jpg`, `blender-closeup.jpg`); the same level of realism for every subject (the Marianne bust is the reference) *(details to confirm with the operator's latest artwork)*.
2. Each family has a small palette, written in its theme's spec; a new family adds its own.
3. Every crossing object faces where it goes; the sleigh is pulled, reindeer in front (operator, 2026-10-28). A mirrored object is mirrored as a whole.
4. Readable at 64 pt; silhouettes still clear on both variants.
5. **Original work only**: no copyrighted character, mascot, font or logo, no downloaded model or texture; generic public symbols only (never the French government's Marianne logo). Say in the PR how the art was made; scripts that make it are committed with it.

## 7. Layouts to check

Every theme and decoration: iPhone (standard and Pro Max, portrait and landscape), iPad (split view, every column, Stage Manager resize), iPhone Duo inner and outer screens, Dynamic Type XL and AX5. Decorations are placed in fractions of their container and respect safe areas; on iPad each column keeps its own decorations.

## 8. Submitting a theme (agents and humans)

1. Open an issue first: `[SwiftHFR] Theme: <name>`, `### Summary`, family, variants, author as it should be shown; wait for `status: ready` ([AGENTS.md §7–§8](../AGENTS.md)).
2. Claim it, branch from `dev-swift` (`feat/theme-<id>`).
3. Add `App/SwiftHFR/Themes/<theme-id>/<theme-id>.theme.json` with every token, its decorations and the sources of its art.
4. Add the author to [CREDITS.md](../CREDITS.md).
5. PR checklist:
   - [ ] contrast test green, every token present
   - [ ] screenshots of a list and a topic page, light and dark (or single), Dynamic Type XL; only `user1`… pseudos and invented titles
   - [ ] decorations follow §4 and §6; Reduce Motion behaviour shown; Instruments numbers for anything that moves
   - [ ] seasonal: window, automatic switch and packing covered by tests with an injected calendar
   - [ ] checked on the layouts of §7
   - [ ] art original, credited, under the repository's [licence](../LICENSE)
