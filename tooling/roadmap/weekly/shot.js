// node shot.js OUTDIR : OUTDIR/slides/slide-N.html -> OUTDIR/swifthfr-semaine-N.jpg, 2880x1620 (1920x1080 at 1.5x)
// Playwright: pre-installed in the cloud sessions (`require('playwright')` works, Chromium included, do not run
// `playwright install`). Elsewhere: `npm i playwright && npx playwright install chromium` in a scratch directory.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

(async () => {
  const dir = path.resolve(process.argv[2] || '');
  if (!process.argv[2]) throw new Error('usage: node shot.js OUTDIR');
  const b = await chromium.launch();
  try {
    for (const f of fs.readdirSync(path.join(dir, 'slides')).filter(x => x.endsWith('.html')).sort()) {
      const p = await b.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1.5 });
      try {
        await p.goto(pathToFileURL(path.join(dir, 'slides', f)).href, { waitUntil: 'networkidle' });
        await p.waitForTimeout(600);
        const ov = await p.evaluate(() => ({ sh: document.body.scrollHeight, sw: document.body.scrollWidth }));
        const over = ov.sh > 1080 || ov.sw > 1920;
        console.log(f, JSON.stringify(ov), over ? 'OVERFLOW' : 'ok');
        if (over) process.exitCode = 1;
        await p.screenshot({ path: path.join(dir, f.replace('slide-', 'swifthfr-semaine-').replace('.html', '.jpg')), type: 'jpeg', quality: 92 });
      } finally {
        await p.close();
      }
    }
  } finally {
    await b.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
