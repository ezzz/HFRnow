// Renders gap.html into docs/assets/gap-legacy-vs-swift-1-iphone.png and gap-legacy-vs-swift-2-duo.png at device scale 3.
// Usage (repo root): node docs/assets/gap/render.js   — needs Playwright with Chromium.
const { chromium } = require('playwright');
const path = require('path');

(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 2400, height: 1200 }, deviceScaleFactor: 3 });
  await page.goto('file://' + path.join(__dirname, 'gap.html'));
  await page.evaluate(() => document.fonts.ready);
  for (const [id, name] of [['#part1', 'gap-legacy-vs-swift-1-iphone.png'], ['#part2', 'gap-legacy-vs-swift-2-duo.png']]) {
    const out = path.join(__dirname, '..', name);
    await page.locator(id).screenshot({ path: out });
    console.log('wrote', out);
  }
  await browser.close();
})();
