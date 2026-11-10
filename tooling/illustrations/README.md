# Illustration tooling (themes and icons)

Generators that produced [`docs/assets/themes/`](../../docs/assets/themes/README.md) on 2026-10-28, kept so the lots can redraw a subject in the same style (style 1, « digital sketching », [THEMES.md](../../docs/THEMES.md) §6).

| File | Role |
|---|---|
| `blender/common.py`, `blender/marianne.py`, `blender/subjects/*.py` | one script per subject: cel materials, Freestyle ink, primitives, framing |
| `blender/render_all.sh`, `blender/preview.py` | render every subject to transparent PNG; contact sheet |
| `art.py`, `png_art.py`, `icons.py`, `build.py` | illustration library, PNG placement, icon masters (SVG), board builder (headless Chrome) |
| `contrast.py`, `contrast-report.txt` | WCAG contrast check of the token draft |
| `px.swift`, `orange.swift`, `cc.swift` | pixel and colour sampling helpers |
| `da.py`, `da2.py` | art-direction candidates (v1 rejected, v2 = the `da-styles` board) |

As committed, the scripts still expect the design session's folder layout (`tokens/`, `boards/`, `legacy-ref/`, `src/blender/out/`): a lot that uses them adapts the paths first. Blender 5.x (GPL) is a tool, not a dependency of the app; the app ships the rendered PNG or PDF only.
