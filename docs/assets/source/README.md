# Visual sources

Two images are built here with `node render.js` (Node, Playwright with Chromium), art direction chosen by the operator on #1380:

| Output | Source | What it shows |
|---|---|---|
| `../hero.jpg` (2400×1200, at most 500 KB) | `hero.html` | « The lens »: the forum's home page (`hfr.webp`) as a printed sheet on an orange table, and a phone lying on it that shows the same categories in the app |
| `../social-preview.png` (1280×640) | `social.html` | « `:o` »: the forum's smiley code as a two-ink typographic poster, with the wordmark. The operator uploads it in the repository's Settings › Social preview |

## Regenerate

```sh
cd docs/assets/source
curl -o inter.woff2 https://fonts.gstatic.com/s/inter/v20/UcCo3FwrK3iLTcviYwY.woff2                        # Inter, SIL OFL 1.1
curl -o jetbrains-mono.woff2 https://fonts.gstatic.com/s/jetbrainsmono/v24/tDbV2o-flEEny0FZhsfKu5WU4xD7OwE.woff2   # JetBrains Mono, SIL OFL 1.1
node render.js      # writes ../hero.jpg and ../social-preview.png
```

`render.js` lowers the JPEG quality from 90 until the hero is at most 500 KB, and fails if a font file is missing.

## The phone screen of the hero

The screen is an image slot (`hero.html?screen=<file>`); the phone takes the image's aspect ratio.

- **`app-forums.png`** (expected, #1380): a simulator capture of the Catégories list of the current `dev-swift` build, default theme, light, status bar overridden (9:41, full signal and battery), public category names only, no account name or avatar. Once this file is here, `render.js` uses it.
- **Until then, a stand-in**: `app-screen.html` draws that screen from the app's code (the sources are listed at the top of the file) and `render.js` renders it to `app-forums.standin.png` (not committed). It is not a screenshot: Inter replaces the system font, the tab bar is approximate, the tab glyphs are redrawn, and the three categories whose icon is a third-party logo show the app's fallback folder. **The committed `hero.jpg` says which one it was built with in the PR that last changed it.**

## Assets and licences

| Asset | Origin | Licence |
|---|---|---|
| `hfr.webp` | Capture of the forum's public home page (logged out; category names and counters only, no member name) | The page and the HARDWARE.FR banner belong to their owner; shown to say which forum the app is a client of, no endorsement implied |
| Inter (`inter.woff2`), JetBrains Mono (`jetbrains-mono.woff2`) | Google Fonts, downloaded by the lines above, not committed | SIL Open Font License 1.1 |
| Category icons in the stand-in | Read at render time from `App/SwiftHFR/Assets.xcassets/CategoryIcons/` (nothing copied here) | Legacy HFR+ images, credit icons8: [CREDITS.md](../../../CREDITS.md) |
| Everything else (layout, phone slab, glyphs, text) | Drawn in the HTML sources | This repository's licence |

« A forum from 1997 » on the social preview: the copyright line at the bottom of the captured home page (`hfr.webp`) reads « Copyright © 1997-2025 ». « An app from 2026 »: this repository's history.

No real member name, avatar, post or cookie appears in either image.

The other files of this folder are the sources of the diagrams (`*.excalidraw`, `roadmap/`).
