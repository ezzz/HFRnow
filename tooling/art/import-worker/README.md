# Import worker art (#754)

Original construction worker of the first-launch import screen, style 1 « digital sketching » ([THEMES.md](../../../docs/THEMES.md) §6).

| File | Role |
|---|---|
| `make.py` | Draws three SVG layers (body, arm, spark), light and dark, into `App/SwiftHFR/Assets.xcassets/ImportWorker*.imageset` (`--assets`) or into a loose folder (`--preview`) |
| `render.mjs` | Renders the A and B previews (light, dark) with Playwright's Chromium into `docs/assets/import-worker/` |

```
python3 tooling/art/import-worker/make.py --assets App/SwiftHFR/Assets.xcassets --preview /tmp/layers
node tooling/art/import-worker/render.mjs /tmp/layers docs/assets/import-worker
```

`SHOULDER` and `IMPACT_ANGLE` in `make.py` mirror `LegacyImportProgressView.shoulder` and `.impactAngle`: change both together.
