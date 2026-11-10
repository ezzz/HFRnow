# Illustration tooling (themes and icons)

Generators that produced [`docs/assets/themes/`](../../docs/assets/themes/README.md) on 2026-10-28, kept so the lots can redraw a subject in the same style (style 1, « digital sketching », [THEMES.md](../../docs/THEMES.md) §6).

| File | Role |
|---|---|
| `art.py`, `png_art.py`, `icons.py`, `build.py` | illustration library, PNG placement, icon masters (SVG), board builder (headless Chrome) |
| `contrast.py`, `contrast-report.txt` | WCAG contrast check of the token draft |
| `px.swift`, `orange.swift`, `cc.swift` | pixel and colour sampling helpers |
| `da.py`, `da2.py` | art-direction candidates (v1 rejected, v2 = the `da-styles` board) |

The Blender scripts that rendered `docs/assets/themes/renders/` are not in this repository: scripts using Blender's Python API must be published under a GPL-compatible licence ([blender.org/about/license](https://www.blender.org/about/license/), read 2026-11-10) and this repository is PolyForm Noncommercial (operator, 2026-11-10). A lot that needs new renders raises that question again. As committed, the scripts here still expect the design session's folder layout (`tokens/`, `boards/`, `legacy-ref/`, `src/blender/out/`): a lot that uses them adapts the paths first. The app ships rendered PNG or PDF only.
