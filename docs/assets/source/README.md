# Visual sources

`scene.html` builds the README hero (`../hero.jpg`) and the GitHub social preview (`../social-preview.png`):
the HFR forum home page (`hfr.webp`) is pulled into an iPhone with a genie effect, revealing a SwiftUI-style forum list.

Regenerate (Node + Playwright with Chromium):

```sh
cd docs/assets/source
curl -o inter.woff2 https://fonts.gstatic.com/s/inter/v20/UcC73FwrK3iLTeHuS_nVMrMxCp50SjIa1ZL7.woff2   # Inter, SIL OFL
node render.js && mv hero.jpg social-preview.png ..
```

The phone screen is an illustration, not a screenshot of the app.
