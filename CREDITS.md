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

**Category icons.** The icons of the Catégories list (`App/SwiftHFR/Assets.xcassets/CategoryIcons/`) are the legacy HFR+ images, unchanged (ezzz/HFRnow `legacy/duo-inner-cover` @ `87fe0d1c`, `SuperHFRplus/Assets/UI/`, `*Filled-40`, `Debian-40`, `cat-apple`): credit to FLKone and the HFR+ contributors, ezzz and the HFRnow contributors; the legacy README and credits page thank [icons8](https://icons8.com/) for its icons.

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
