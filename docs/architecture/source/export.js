const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');

(async () => {
  const dir = __dirname;
  const elements = JSON.parse(fs.readFileSync(path.join(dir, 'elements.json'), 'utf8'));
  const browser = await chromium.launch();
  const page = await browser.newPage();
  page.on('pageerror', (e) => console.error('pageerror', e.message));
  await page.goto('file://' + path.join(dir, 'export.html'));
  await page.evaluate((els) => window.run(els), elements);
  const { svg, file } = await page.evaluate(() => window.result);

  // Inline the Virgil font so the SVG renders identically on GitHub (no external font fetch).
  const font = fs.readFileSync(path.join(dir, 'Virgil-Regular.woff2')).toString('base64');
  const style = `<style>@font-face{font-family:"Virgil";src:url(data:font/woff2;base64,${font}) format("woff2");}</style>`;
  const inlined = svg
    .replace(/<style[^>]*>[\s\S]*?<\/style>/g, '')
    .replace(/<defs>/, '<defs>' + style);

  fs.writeFileSync(path.join(dir, 'architecture.svg'), inlined);
  fs.writeFileSync(path.join(dir, 'architecture.excalidraw'), file + '\n');

  const preview = await browser.newPage({ viewport: { width: 1200, height: 900 } });
  await preview.setContent('<body style="margin:0"><img src="file://' + path.join(dir, 'architecture.svg') + '" style="width:1200px"></body>'); await preview.waitForTimeout(1500);
  await preview.screenshot({ path: path.join(dir, 'preview.png'), fullPage: true });
  await browser.close();
  console.log('svg bytes', inlined.length, 'file bytes', file.length);
})();
