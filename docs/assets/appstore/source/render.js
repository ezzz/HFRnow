// Frames each capture of screens.json with its French caption, at each App Store size marked "render" (or the sizes named
// on the command line: `node render.js iphone-large ipad-13`). Output: ../<size id>/<screen id>.png, opaque RGB.
// - Every capture must exist: otherwise nothing is written and the run fails with the list.
// - `--allow-placeholders` draws a labelled placeholder for a missing capture and writes the whole run to
//   ../preview/<size id>/ instead (git-ignored), so a placeholder never sits where a store image is expected.
// - `--sheet` also writes ../art-direction.jpg, a contact sheet of the first size rendered.
// A run that fails leaves the previous output as it was.
// A caption too long for a size, or a font that did not load, stops the run.
const { chromium } = require('playwright');
const fs = require('fs');
const path = require('path');
const zlib = require('zlib');
const { pathToFileURL } = require('url');

const here = (...p) => path.join(__dirname, ...p);
const args = process.argv.slice(2);
const allowPlaceholders = args.includes('--allow-placeholders');
const wantSheet = args.includes('--sheet');
const wanted = args.filter((a) => !a.startsWith('--'));
const { sizes, screens } = JSON.parse(fs.readFileSync(here('screens.json'), 'utf8'));
const screensFor = (size) => screens.filter((screen) => !screen.sizes || screen.sizes.includes(size.id));
const capture = (size, screen) => `captures/${size.id}/${screen.id}.png`;

// App Store Connect refuses an alpha channel, and Chromium writes RGBA: re-encode the screenshot as 8-bit RGB (PNG colour
// type 2) with Node alone. Every row uses filter 0.
function crcTable() {
  const table = new Uint32Array(256);
  for (let n = 0; n < 256; n++) { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; table[n] = c >>> 0; }
  return table;
}
const CRC = crcTable();
function chunk(type, data) {
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  let c = 0xffffffff;
  for (const byte of body) c = CRC[(c ^ byte) & 0xff] ^ (c >>> 8);
  const out = Buffer.alloc(body.length + 8);
  out.writeUInt32BE(data.length, 0); body.copy(out, 4); out.writeUInt32BE((c ^ 0xffffffff) >>> 0, body.length + 4);
  return out;
}
function opaquePNG(rgba, width, height) {
  const row = width * 3 + 1, raw = Buffer.alloc(row * height);
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) rgba.copy(raw, y * row + 1 + x * 3, (y * width + x) * 4, (y * width + x) * 4 + 3);
  }
  const header = Buffer.alloc(13);
  header.writeUInt32BE(width, 0); header.writeUInt32BE(height, 4); header[8] = 8; header[9] = 2;
  return Buffer.concat([Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', header), chunk('IDAT', zlib.deflateSync(raw, { level: 9 })), chunk('IEND', Buffer.alloc(0))]);
}

// The pixels of a PNG, read by the page itself: no PNG decoder is needed here to drop the alpha channel.
async function rgbaOf(page, png) {
  return Buffer.from(await page.evaluate(async (b64) => {
    const bitmap = await createImageBitmap(await (await fetch('data:image/png;base64,' + b64)).blob());
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d');
    context.drawImage(bitmap, 0, 0);
    const data = context.getImageData(0, 0, bitmap.width, bitmap.height).data;
    let binary = '';
    for (let o = 0; o < data.length; o += 0x8000) binary += String.fromCharCode.apply(null, data.subarray(o, o + 0x8000));
    return btoa(binary);
  }, png.toString('base64')), 'base64');
}

function frameURL(size, screen, index, total) {
  const url = pathToFileURL(here('frame.html'));
  url.search = new URLSearchParams({ shot: capture(size, screen), kicker: screen.kicker, caption: screen.caption, ink: screen.ink,
    index, total, ratio: size.width / size.height }).toString();
  return url.href;
}

(async () => {
  for (const font of ['inter.woff2', 'jetbrains-mono.woff2']) {
    if (!fs.existsSync(here(font))) throw new Error(`${font} is missing: see README.md for the download line`);
  }
  // A size id names an output folder that this script empties: only plain names, never a folder that holds sources.
  const unsafe = sizes.map((s) => s.id).filter((id) => !/^[a-z0-9-]+$/.test(id) || ['source', 'preview', 'captures'].includes(id));
  if (unsafe.length) throw new Error(`screens.json: size id not allowed: ${unsafe.map((id) => JSON.stringify(id)).join(', ')}`);
  const unknown = wanted.filter((id) => !sizes.some((s) => s.id === id));
  if (unknown.length) throw new Error(`unknown size: ${unknown.join(', ')}`);
  const chosen = sizes.filter((s) => (wanted.length ? wanted.includes(s.id) : s.render));
  const missing = chosen.flatMap((size) => screensFor(size).map((screen) => capture(size, screen))).filter((file) => !fs.existsSync(here(file)));
  if (missing.length && !allowPlaceholders) {
    throw new Error(`${missing.length} capture(s) missing, nothing written (--allow-placeholders renders previews):\n  ${missing.join('\n  ')}`);
  }
  const outRoot = missing.length ? here('..', 'preview') : here('..');
  // Everything is rendered into a staging folder and moved into place only once every size passed its checks: a failed
  // run leaves the previous images untouched.
  const staging = path.join(outRoot, '.staging');
  fs.rmSync(staging, { recursive: true, force: true });
  const browser = await chromium.launch();
  const sheet = [];
  for (const size of chosen) {
    const list = screensFor(size);
    fs.mkdirSync(path.join(staging, size.id), { recursive: true });
    const page = await browser.newPage({ viewport: { width: size.width, height: size.height }, deviceScaleFactor: 1 });
    for (const [i, screen] of list.entries()) {
      await page.goto(frameURL(size, screen, i + 1, list.length));
      await page.waitForSelector('body[data-ready="1"]');
      const flags = await page.evaluate(() => ({ ...document.body.dataset }));
      if (flags.fontsMissing) throw new Error('Inter or JetBrains Mono did not load: download the fonts again (README.md)');
      if (flags.wrapped) throw new Error(`${size.id}/${screen.id}: a caption line is too long, shorten it in screens.json`);
      const png = await page.screenshot({ type: 'png' });
      const rgba = await rgbaOf(page, png);
      if (rgba.length !== size.width * size.height * 4) throw new Error(`${screen.id}: unexpected bitmap size`);
      const target = path.join(staging, size.id, screen.id + '.png');
      fs.writeFileSync(target, opaquePNG(rgba, size.width, size.height));
      if (size === chosen[0]) sheet.push(pathToFileURL(path.join(outRoot, size.id, screen.id + '.png')).href);
      console.log('rendered', `${size.id}/${screen.id}.png`, `${size.width}x${size.height}`);
    }
    await page.close();
  }
  // Each folder holds this run only: an image of a screen since removed from the list does not stay behind.
  for (const size of chosen) {
    fs.rmSync(path.join(outRoot, size.id), { recursive: true, force: true });
    fs.renameSync(path.join(staging, size.id), path.join(outRoot, size.id));
  }
  fs.rmSync(staging, { recursive: true, force: true });
  console.log(`wrote ${chosen.map((size) => path.relative(here('..'), path.join(outRoot, size.id)) + '/').join(', ')}`);
  if (wantSheet) {
    // The frames of the first size side by side on the dark ink, 2800 px wide.
    const size = chosen[0], gap = 48, width = sheet.length * size.width + (sheet.length + 1) * gap, scale = 2800 / width;
    const page = await browser.newPage({ viewport: { width: 2800, height: Math.round((size.height + 2 * gap) * scale) } });
    // A file page, not setContent: a blank page may not load file images.
    const sheetPage = path.join(outRoot, 'sheet.html');
    fs.writeFileSync(sheetPage, `<!doctype html><body style="margin:0;background:#2b2621;display:flex;gap:${gap * scale}px;padding:${gap * scale}px">${
      sheet.map((src) => `<img src="${src}" style="width:${size.width * scale}px;height:${size.height * scale}px">`).join('')}</body>`);
    await page.goto(pathToFileURL(sheetPage).href);
    fs.rmSync(sheetPage);
    await page.waitForFunction(() => [...document.images].every((image) => image.complete && image.naturalWidth > 0));
    fs.writeFileSync(here('..', 'art-direction.jpg'), await page.screenshot({ type: 'jpeg', quality: 82 }));
    console.log(`wrote art-direction.jpg (${size.id}${missing.length ? ', placeholders' : ''})`);
  }
  await browser.close();
  if (missing.length) console.log(`previews only: ${missing.length} capture(s) missing`);
})().catch((error) => { console.error(error.message); process.exit(1); });
