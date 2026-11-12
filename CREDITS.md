# Credits

SwiftHFR exists because several generations of community developers built and maintained an iOS app for the HFR forum.
Code and knowledge from these projects are reused with gratitude.

## Lineage

| Project | Repository | Notes |
|---|---|---|
| HFR+ / SuperHFR+ | <https://github.com/FLKone/SuperHFRplus> | Original app by FLKone and contributors |
| HFRnow | <https://github.com/ezzz/HFRnow> | Continuation; introduced the SwiftUI layer reused here |
| SwiftHFR | this repository | Full Swift rewrite |

**App icon.** The main icon art (`App/SwiftHFR/Icon-RedFace3D.icon`) comes unchanged from the legacy HFR+ app (ezzz/HFRnow `master` @ `2440d79`, `SuperHFRplus/Assets/`): credit to FLKone and the HFR+ contributors, and to ezzz and the HFRnow contributors. The alternate icons are credited under [AlternativeIcons](#alternativeicons).

> Maintainers: complete this table with every fork in the chain and the names of their main contributors.

### AlternativeIcons

Alternate app icons, `App/SwiftHFR/Icon-*.icon`. The legacy art lives in `SuperHFRplus/Assets/AlternativeIcons/` (ezzz/HFRnow `master` @ `2440d79`).

| Icon | Source | Credit |
|---|---|---|
| `Icon-RedFace3DBig` | Legacy art, unchanged | FLKone and the HFR+ contributors, ezzz and the HFRnow contributors |
| `Icon-BLUE`, `Icon-WHITE` | Legacy 1024 px image, unchanged, in a one-layer `.icon` | FLKone and the HFR+ contributors, ezzz and the HFRnow contributors |
| `Icon-CLASSIC`, `Icon-CLASSIC-RED`, `Icon-REDFACE`, `Icon-REDFACEBLUE`, `Icon-BETA` | Legacy designs redrawn as SVG for SwiftHFR (the legacy images stop at 180 px), under this repository's licence | Designs by FLKone (`Icon-CLASSIC`, `Icon-REDFACE`, `Icon-BETA`, 2017) and by Bruno / ezzz (`Icon-CLASSIC-RED`, `Icon-REDFACEBLUE`, 2025), in the legacy history |
| `Icon-CLASSIC-BLUE` | Legacy 1024 px image, unchanged (`HFRswift/Swift/Assets.xcassets/Classic-Blue.appiconset`, ezzz/HFRnow `legacy/duo-inner-cover` @ `87fe0d1c`), in a one-layer `.icon` | FLKone and the HFR+ contributors, ezzz and the HFRnow contributors |
| `Icon-ORANGE`, `Icon-BETA-RED`, `Icon-XFACE`, `Icon-XFACE-*` (11 variations), `Icon-HALLOWEEN-JACK`, `Icon-HALLOWEEN-HFR`, `Icon-SPRING`, `Icon-SUMMER`, `Icon-WINTER` | Original art (#731, drawings validated by the operator 2026-11-10): the redface of `Icon-REDFACE` and the legacy Beta drawing (`Icon-BETA`) recoloured, the HFR letters on `orange-hfr`, generic Pride flag and season items; style 1 « digital sketching » ([THEMES.md](docs/THEMES.md) §6); masters in `docs/assets/themes/icons/`, under this repository's licence | Legacy par Ezzz (the redface and Beta designs); the new drawings by Claude Code for the operator |

**Category icons.** The icons of the Catégories list (`App/SwiftHFR/Assets.xcassets/CategoryIcons/`) are the legacy HFR+ images, unchanged (ezzz/HFRnow `legacy/duo-inner-cover` @ `87fe0d1c`, `SuperHFRplus/Assets/UI/`, `*Filled-40`, `Debian-40`, `cat-apple`): credit to FLKone and the HFR+ contributors, ezzz and the HFRnow contributors; the legacy README and credits page thank [icons8](https://icons8.com/) for its icons.

### Import worker

The construction worker shown while the first-launch import runs (#754, `App/SwiftHFR/Assets.xcassets/ImportWorker*.imageset`). Original drawing in the style 1 « digital sketching » ([THEMES.md](docs/THEMES.md) §6), generated from the committed script `tooling/art/import-worker/make.py` (hand-placed vector shapes, standard library only; no traced, downloaded or existing character), under this repository's licence. Made by Claude Code (Sonnet 5.5) for the operator; the previews are rendered by `tooling/art/import-worker/render.mjs`.

## Contributors

Everyone who contributed to the projects above, and every contributor listed in this repository's history.

| Contributor | Contribution |
|---|---|
| Bybifok ([`moust4ki`](https://github.com/moust4ki)) | Feature proposals, design boards, protocol findings and prototype [Ultra HFR](https://github.com/moust4ki/ultra-hfr): [FEATURES.md](docs/FEATURES.md), [research/bybifok-proposals.md](docs/research/bybifok-proposals.md), [HFR-PROTOCOL.md §7b](docs/HFR-PROTOCOL.md#7b-reported-by-bybifok-to-verify-with-our-fixtures) |

## Third-party software

| Component | License | Use |
|---|---|---|
| [SwiftSoup](https://github.com/scinfu/SwiftSoup) | MIT | HTML parsing in `HFRParsing` |

The legacy apps also credited Giphy, SDWebImage, ASIHTTPRequest, Objective-C-HTML-Parser, InAppSettingsKit, MBProgressHUD, MKStoreKit, RegexKitLite and icons8. None of them is used by SwiftHFR.
