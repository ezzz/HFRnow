const { chromium } = require('playwright');
const path = require('path');

const shots = [
  { name: 'social-preview.png', w: 1280, h: 640, mode: 'social', dpr: 1 },
  { name: 'hero.jpg', w: 1600, h: 800, mode: 'hero', dpr: 1.5 },
];

(async () => {
  const browser = await chromium.launch();
  for (const s of shots) {
    const page = await browser.newPage({ viewport: { width: s.w, height: s.h }, deviceScaleFactor: s.dpr });
    const url = 'file://' + path.join(__dirname, 'scene.html') + `?w=${s.w}&h=${s.h}&mode=${s.mode}`;
    await page.goto(url);
    await page.waitForSelector('body[data-ready="1"]');
    await page.evaluate(() => document.fonts.ready);
    await page.screenshot(s.name.endsWith('.jpg') ? { path: path.join(__dirname, s.name), type: 'jpeg', quality: 88 } : { path: path.join(__dirname, s.name) });
    console.log('wrote', s.name);
  }
  await browser.close();
})();
