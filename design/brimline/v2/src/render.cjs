// Brimline, deuxième tour : rend les PNG de chaque piste et les captures de la planche (Chromium sans tête, Playwright).
// Usage : NODE_PATH=<dossier node_modules contenant playwright> node design/brimline/v2/src/render.cjs
// À lancer après src/build.cjs.

const fs = require('fs');
const os = require('os');
const path = require('path');
const { chromium } = require('playwright');
const { PISTES } = require('./pistes.cjs');

const ROOT = path.resolve(__dirname, '..');
const url = (f) => 'file://' + path.join(ROOT, f);

(async () => {
  const browser = await chromium.launch();
  try {
    const page = await browser.newPage({ deviceScaleFactor: 1 });
    const shot = async (svg, px, out) => {
      await page.setViewportSize({ width: px, height: px });
      const wrap = path.join(os.tmpdir(), 'brimline-v2-shot.html');
      fs.writeFileSync(wrap, `<html><body style="margin:0;background:transparent"><img src="${url(svg)}" width="${px}" height="${px}" style="display:block"></body></html>`);
      await page.goto('file://' + wrap);
      await page.waitForFunction(() => document.images[0].complete && document.images[0].naturalWidth > 0);
      fs.mkdirSync(path.dirname(path.join(ROOT, out)), { recursive: true });
      await page.screenshot({ path: path.join(ROOT, out), omitBackground: true });
    };
    for (const p of PISTES) {
      const d = p.dossier;
      for (const px of [1024, 512, 64]) await shot(`${d}/app-icon.svg`, px, `${d}/png/app-icon-${px}.png`);
      for (const px of [32, 16]) await shot(`${d}/app-icon-small.svg`, px, `${d}/png/app-icon-${px}.png`);
      for (const px of [32, 16]) await shot(`${d}/favicon.svg`, px, `${d}/png/favicon-${px}.png`);
      for (const px of [36, 18]) await shot(`${d}/menubar-template.svg`, px, `${d}/png/menubar-${px}.png`);
    }
    await page.close();

    fs.mkdirSync(path.join(ROOT, 'captures'), { recursive: true });
    for (const [w, tag] of [[1440, ''], [390, '-390']]) {
      for (const scheme of ['light', 'dark']) {
        const ctx = await browser.newContext({ viewport: { width: w, height: 900 }, deviceScaleFactor: 2, colorScheme: scheme });
        const pg = await ctx.newPage();
        await pg.goto(url('planche.html'));
        await pg.waitForLoadState('load');
        await pg.waitForTimeout(300);
        const name = scheme === 'light' ? 'clair' : 'sombre';
        await pg.screenshot({ path: path.join(ROOT, `captures/planche${tag}-${name}.png`), fullPage: true });
        if (!tag) {
          const box = (sel) => pg.evaluate((s) => { const r = document.querySelector(s).getBoundingClientRect(); return { top: r.top + window.scrollY, bottom: r.bottom + window.scrollY }; }, sel);
          const pistes = await box('.pistes');
          await pg.screenshot({ path: path.join(ROOT, `captures/pistes-${name}.png`), clip: { x: 0, y: 0, width: w, height: pistes.bottom + 24 }, fullPage: true });
          for (const p of PISTES) {
            const s = await box(`#piste-${p.id}`);
            await pg.screenshot({ path: path.join(ROOT, `captures/situation-${p.id}-${name}.png`), clip: { x: 0, y: s.top, width: w, height: s.bottom - s.top }, fullPage: true });
          }
        }
        await ctx.close();
      }
    }
  } finally {
    await browser.close();
  }
  console.log('PNG et captures écrits.');
})();
