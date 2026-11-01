const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const f = process.argv[2], out = process.argv[3];
  for (const [n,w,h] of [['16x9',1920,1080]]) {
    const p = await b.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1.5 });
    await p.goto('file://' + f, { waitUntil: 'networkidle' }).catch(()=>{});
    await p.waitForTimeout(800);
    const ov = await p.evaluate(() => ({sh: document.body.scrollHeight, ch: innerHeight, sw: document.body.scrollWidth, cw: innerWidth, font: getComputedStyle(document.body).fontFamily}));
    console.log(n, JSON.stringify(ov));
    await p.screenshot({ path: `${out}/swifthfr-avancement-${n}.jpg`, type: 'jpeg', quality: 92 });
    await p.close();
  }
  await b.close();
})();
