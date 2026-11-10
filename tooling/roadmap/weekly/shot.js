// Renders OUTDIR/slides/*.html (from build.py) to OUTDIR/swifthfr-semaine-NN.jpg at 2880x1620, and checks each slide:
// no overflow of the 1920x1080 page or of an element's own box, no visible text under 20 px at the 1920 base, and
// never the word « legacy » (the legacy app is « l'app courante »). A failed check is printed and exits 1.
// Playwright: pre-installed in the cloud sessions (`require('playwright')` works, Chromium included, do not run
// `playwright install`). Elsewhere: `npm i playwright && npx playwright install chromium` in a scratch directory.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const { pathToFileURL } = require('url');

const MIN_PX = 20;

function audit(minPx) {
  const issues = [];
  const de = document.documentElement;
  if (de.scrollHeight > 1080 || de.scrollWidth > 1920 || document.body.scrollHeight > 1080) issues.push(`page ${de.scrollWidth}x${de.scrollHeight}`);
  const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
  const small = new Map();
  for (let n = walker.nextNode(); n; n = walker.nextNode()) {
    if (!n.textContent.trim()) continue;
    const el = n.parentElement;
    if (!el || el.closest('style,title')) continue;
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') continue;
    let px = parseFloat(cs.fontSize);
    if (el instanceof SVGElement && el.ownerSVGElement) {
      const m = el.getScreenCTM();
      if (m) px *= Math.hypot(m.a, m.b);
    }
    if (px < minPx - 0.25) small.set(n.textContent.trim().slice(0, 30), px.toFixed(1));
    if (/legacy/i.test(n.textContent)) issues.push(`"legacy" in: ${n.textContent.trim().slice(0, 60)}`);
    // text cut by its own box: a block whose content is taller than itself (ellipsis on one line is allowed)
    const r = el.getBoundingClientRect();
    if (r.bottom > 1080 + 1 || r.right > 1920 + 1) issues.push(`off page: ${n.textContent.trim().slice(0, 40)}`);
  }
  for (const el of document.querySelectorAll('.card,.hero,.body')) {
    if (el.scrollHeight > el.clientHeight + 2) issues.push(`content taller than its box (${el.className}): +${el.scrollHeight - el.clientHeight}px`);
  }
  // blocks of the slide body never overlap each other (a grid that grew past its row lands on the next block)
  const blocks = [...document.querySelectorAll('.body > *')].filter(e => e.tagName !== 'STYLE').map(e => e.getBoundingClientRect());
  for (let i = 1; i < blocks.length; i++) if (blocks[i].top < blocks[i - 1].bottom - 1) issues.push(`block ${i + 1} overlaps block ${i} by ${Math.round(blocks[i - 1].bottom - blocks[i].top)}px`);
  for (const [t, px] of small) issues.push(`text ${px}px < ${minPx}: "${t}"`);
  return issues;
}

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
        const issues = await p.evaluate(audit, MIN_PX);
        console.log(f, issues.length ? 'FAIL' : 'ok');
        for (const i of issues) console.log('   ', i);
        if (issues.length) process.exitCode = 1;
        await p.screenshot({ path: path.join(dir, f.replace('slide-', 'swifthfr-semaine-').replace('.html', '.jpg')), type: 'jpeg', quality: 92 });
      } finally {
        await p.close();
      }
    }
  } finally {
    await b.close();
  }
})().catch(e => { console.error(e); process.exit(1); });
