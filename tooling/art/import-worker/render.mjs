// Renders the preview PNGs of the animated worker and of the Reduce Motion form (light and dark) from the generated layers (#754).
// Usage: node render.mjs <layers-dir> <out-dir>   (Playwright's Chromium is enough; no dependency added)
import { createRequire } from 'node:module';
const { chromium } = createRequire(import.meta.url)('playwright');
import { readFileSync, mkdirSync, writeFileSync } from 'node:fs';

const [layers, out] = process.argv.slice(2);
mkdirSync(out, { recursive: true });
const SHOULDER = [72, 62], IMPACT = 58;
const inline = (n, s) => readFileSync(`${layers}/${n}-${s}.svg`, 'utf8').replace(/<svg[^>]*>/, '<svg viewBox="0 0 128 128" width="100%" height="100%">');
const strip = (n, s) => readFileSync(`${layers}/${n}-${s}.svg`, 'utf8').replace(/<\/?svg[^>]*>/g, '');
const worker = (s, angle, spark) => `<svg viewBox="0 0 128 128" width="100%" height="100%">${strip('body', s)}
  <g transform="rotate(${angle} ${SHOULDER[0]} ${SHOULDER[1]})">${strip('arm', s)}</g>${spark ? strip('spark', s) : ''}</svg>`;
const theme = { light: { bg: '#F2F2F7', card: '#FFFFFF', fg: '#000', sec: '#6C6C70' }, dark: { bg: '#000', card: '#1C1C1E', fg: '#FFF', sec: '#98989D' } };

function page(s) {
  const t = theme[s];
  const phone = (angle, spark, caption, spin = false) => `<div class="col"><div class="phone"><div class="stack">
    <div class="w">${worker(s, angle, spark)}</div>
    ${spin ? '<div class="spin"></div>' : ''}
    <div class="txt">Import de vos données HFR+…</div>
  </div></div><div class="cap">${caption}</div></div>`;
  const frames = phone(0, false, 'marteau levé') + phone(IMPACT, true, 'impact (étincelle)')
    + phone(IMPACT * 0.5, false, 'Réduire les animations: dessin fixe + indicateur', true);
  return `<html><body style="margin:0;background:${t.bg};font-family:-apple-system,Helvetica,Arial,sans-serif;color:${t.fg}">
  <style>.row{display:flex;gap:28px;padding:28px;justify-content:center}.col{text-align:center}.cap{margin-top:10px;font-size:14px;color:${t.sec}}
  .phone{width:300px;height:420px;border-radius:36px;background:${t.bg};border:1px solid ${t.sec}55;display:flex;align-items:center;justify-content:center}
  .stack{display:flex;flex-direction:column;align-items:center;gap:14px}.w{width:128px;height:128px}.txt{font-size:15px;color:${t.sec}}
  .spin{width:22px;height:22px;border-radius:50%;border:3px solid ${t.sec}55;border-top-color:${t.sec}}</style>
  <div class="row">${frames}</div>
  <div class="row" style="padding-top:0"><div class="col"><div style="width:64px;height:64px;background:${t.card};border-radius:12px">${worker(s, IMPACT * 0.5, false)}</div><div class="cap">64 pt</div></div></div>
  </body></html>`;
}

const browser = await chromium.launch();
for (const s of ['light', 'dark']) {
  const ctx = await browser.newContext({ viewport: { width: 1060, height: 600 }, deviceScaleFactor: 2 });
  const p = await ctx.newPage();
  await p.setContent(page(s));
  await p.screenshot({ path: `${out}/import-worker-${s}.png`, fullPage: true });
  await ctx.close();
}
await browser.close();
