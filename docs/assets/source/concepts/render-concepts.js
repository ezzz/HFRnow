// Renders each concept as a hero thumbnail (1600×800) and a social-preview crop (1280×640).
const { chromium } = require('playwright');
const path = require('path');
(async () => {
  const browser = await chromium.launch();
  for (const c of ['a-lens', 'b-smiley', 'c-skins']) {
    for (const [suffix, dpr] of [['hero', 1.25], ['social', 1]]) {
      const page = await browser.newPage({ viewport: { width: 1280, height: 640 }, deviceScaleFactor: dpr });
      await page.goto('file://' + path.join(__dirname, c + '.html') + '?mode=' + suffix);
      await page.evaluate(() => document.fonts.ready);
      await page.waitForTimeout(300);
      await page.screenshot({ path: path.join(__dirname, `${c}-${suffix}.png`) });
      await page.close();
    }
  }
  await browser.close();
})();
