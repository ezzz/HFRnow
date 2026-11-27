// Builds ../hero.jpg (2400×1200, at most 500 KB) and ../social-preview.png (1280×640) from hero.html and social.html.
// The phone screen of the hero is the simulator capture app-forums.png when it exists, else a stand-in drawn from the app's
// code (app-screen.html), rendered here to app-forums.standin.png.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

const here = (f) => path.join(__dirname, f);
const out = (f) => path.join(__dirname, '..', f);
const HERO_MAX_BYTES = 500 * 1000;

async function open(browser, file, width, height, dpr, query = '') {
  const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: dpr });
  await page.goto('file://' + here(file) + query);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForLoadState('networkidle');
  return page;
}

(async () => {
  for (const font of ['inter.woff2', 'jetbrains-mono.woff2']) {
    if (!fs.existsSync(here(font))) throw new Error(`${font} is missing: see README.md for the download line`);
  }
  const browser = await chromium.launch();

  let screen = 'app-forums.png';
  if (!fs.existsSync(here(screen))) {
    screen = 'app-forums.standin.png';
    const page = await open(browser, 'app-screen.html', 402, 874, 3);
    await page.screenshot({ path: here(screen) });
    console.log('no app-forums.png: the hero uses the stand-in', screen);
  }

  const hero = await open(browser, 'hero.html', 1280, 640, 1.875, '?screen=' + screen);
  await hero.waitForSelector('body[data-ready="1"]');
  for (let quality = 90; ; quality -= 2) {
    const jpeg = await hero.screenshot({ type: 'jpeg', quality });
    if (jpeg.length <= HERO_MAX_BYTES || quality <= 60) {
      fs.writeFileSync(out('hero.jpg'), jpeg);
      console.log(`wrote hero.jpg (quality ${quality}, ${jpeg.length} bytes, screen: ${screen})`);
      if (jpeg.length > HERO_MAX_BYTES) throw new Error('hero.jpg is over 500 KB at quality 60');
      break;
    }
  }

  const social = await open(browser, 'social.html', 1280, 640, 1);
  await social.screenshot({ path: out('social-preview.png') });
  console.log('wrote social-preview.png', fs.statSync(out('social-preview.png')).size, 'bytes');
  await browser.close();
})().catch((error) => { console.error(error.message); process.exit(1); });
