// node shot.js OUTDIR : OUTDIR/slides/slide-N.html -> OUTDIR/swifthfr-semaine-N.jpg, 2880x1620 (1920x1080 at 1.5x)
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
(async () => {
  const dir = path.resolve(process.argv[2]);
  const b = await chromium.launch();
  for (const f of fs.readdirSync(path.join(dir, 'slides')).filter(x => x.endsWith('.html')).sort()) {
    const p = await b.newPage({ viewport: { width: 1920, height: 1080 }, deviceScaleFactor: 1.5 });
    await p.goto('file://' + path.join(dir, 'slides', f), { waitUntil: 'networkidle' }).catch(() => {});
    await p.waitForTimeout(600);
    const ov = await p.evaluate(() => ({ sh: document.body.scrollHeight, sw: document.body.scrollWidth }));
    console.log(f, JSON.stringify(ov), ov.sh > 1080 || ov.sw > 1920 ? 'OVERFLOW' : 'ok');
    await p.screenshot({ path: path.join(dir, f.replace('slide-', 'swifthfr-semaine-').replace('.html', '.jpg')), type: 'jpeg', quality: 92 });
    await p.close();
  }
  await b.close();
})();
