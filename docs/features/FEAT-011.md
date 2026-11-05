# FEAT-011 — Image loading setting

- **Issue:** [#155](https://github.com/ezzz/HFRnow/issues/155) · **Proposed by:** Bybifok (credit kept, see [CREDITS.md](../../CREDITS.md))
- **Lots:** [LOT-083](../lots/LOT-083-topic-reader.md) (policy C, `ImageAutoLoad`, `NetworkMonitor`), [LOT-107](../lots/LOT-107-image-loading-setting.md) (the setting screen; last lot)

## What and why
The reader chooses when third-party images load: always, on Wi-Fi only, or never by itself. Readers on mobile data control data use and privacy (≈20 user complaints "options removed in 3.0").

## Screens and states
- Réglages › Général › **Images externes**: Toujours / Wi-Fi uniquement (default) / Jamais (au toucher).
- Wi-Fi uniquement: automatic on unmetered Wi-Fi or Ethernet; on tap on cellular, expensive or Low Data Mode paths, or offline.
- Jamais: nothing third-party is requested before a tap on the placeholder (legacy `no`, kept as tap-to-load by LOT-083).
- HFR's own images (smileys, avatars, `forum-images.hardware.fr`) always load. Private/LAN/malformed hosts stay blocked whatever the setting or a tap (policy C, D-071-1 point 1).
- A change applies to the next page opened; images of an already open page that are not requested yet follow the new value (the reader reads the store per page and per image request).
- Light, dark, Dynamic Type XL, iPad: a standard `Picker` row, no custom layout.

## HFR facts
None new. Policy C is [LOT-071](../lots/LOT-071-third-party-services.md)/LOT-056; legacy values are `display_images` = `yes` / `no` / `wifi`.

## Edge cases
No stored value: `wifi`. A legacy value is read as is (same key, same raw values); legacy forced `yes` at launch without a UI, SwiftHFR does not.

## Legacy settings kept
`display_images` (`ImageDisplayMode`, LOT-060).
