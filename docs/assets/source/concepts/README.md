# Hero concepts (#1380)

Three art-direction candidates for the README hero and the GitHub social preview, for the operator to choose from.
One-off folder: it is deleted once the chosen concept becomes `../scene.html` (AGENTS.md §2).

| Files | Concept |
|---|---|
| `a-lens.html` | The lens: the phone lies on the printed forum page (`../hfr.webp`) and shows the same categories natively |
| `b-smiley.html` | `:o`: the forum's smiley code set as a two-ink typographic poster |
| `c-skins.html` | One list, six skins: a single invented topic list re-skinned band by band with the app's themes (`../../themes/tokens/themes.json`) |

Render: `node render-concepts.js` (Playwright with Chromium) writes `<concept>-hero.png` (1600×800) and `<concept>-social.png` (1280×640).

Fonts, read from the system and not committed: Inter and Inter Display (SIL OFL 1.1), JetBrains Mono (SIL OFL 1.1).
Content: category names as on the current hero; topic titles are invented; no member name, avatar or post.
