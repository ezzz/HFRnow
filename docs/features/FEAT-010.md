# FEAT-010 — Appearance

- **Issue:** [#154](https://github.com/ezzz/HFRnow/issues/154) · **Proposed by:** Bybifok (credit kept, see [CREDITS.md](../../CREDITS.md))
- **Lots:** [LOT-122](../lots/LOT-122-appearance.md) (darker dark, OLED black, separators; #213), LOT-166 (seasonal themes, #256), LOT-180 (single accent with a live preview, M5, #420), LOT-169 (compact mode, done); the one-line message header is LOT-106

## What and why
The dark theme gets a choice of depth: the colours the app always had, a near-black (#0B0B0C) that is softer than pure black, and pure OLED black. Readers on OLED screens and at night want a darker app; the legacy dark was a fixed #17181A.

## Screens and states
- Réglages › Thème › **Style du thème sombre**: Standard (default) / Plus sombre / Noir OLED, with a sample of the chosen surfaces (message, quote, accent, separator) drawn in the dark colours whatever the current theme.
- Only the dark theme changes. In light mode, and with **Standard**, every colour is what it was before this lot.
- Plus sombre / Noir OLED paint the screen background of every list and form (iPad split-view columns included, and the reader's page, quotes and image placeholders) in #0B0B0C / #000000. Rows and cards keep the system's raised colour.
- The brightness slider (LOT-121) still scales the reader's dark surfaces on top of the chosen style; at 0 % they are black.
- Separators: the reader's message rule and alternate surface are #568's tokens (`--separator-strong`, `--surface-alt`), derived from the text and background colours, so they follow the chosen background; there is no second separator setting. Native list separators are the system's hairline.
- Live: a change applies at once to every screen and to the open reader, no reload.

## HFR facts
None.

## Edge cases
- No stored value, or an unknown one: Standard. Creating the model writes nothing.
- Following iOS ("Automatique") shows the style only while iOS is dark.

## Legacy settings kept
`theme_night_brightness`, `auto_theme`, `theme` and the accent keys keep their meaning. New key `theme_dark_style` (device-only: black is a screen property).
