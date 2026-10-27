// Brimline : rend les PNG de chaque piste et les captures de la planche, par Chromium sans tête (Playwright).
// Usage : NODE_PATH=<dossier node_modules contenant playwright> node design/brimline/src/render.cjs
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
  console.log('PID du navigateur :', browser.process ? browser.process()?.pid : 'inconnu');
  try {
    // PNG des icônes, à la taille exacte (1x), fond transparent.
    const page = await browser.newPage({ deviceScaleFactor: 1 });
    const shot = async (svg, px, out) => {
      await page.setViewportSize({ width: px, height: px });
      // Page file:// (et non about:blank) : sinon Chromium refuse de charger l'image locale.
      const wrap = path.join(os.tmpdir(), 'brimline-shot.html');
      fs.writeFileSync(wrap, `<html><body style="margin:0;background:transparent"><img src="${url(svg)}" width="${px}" height="${px}" style="display:block"></body></html>`);
      await page.goto('file://' + wrap);
      await page.waitForFunction(() => document.images[0].complete && document.images[0].naturalWidth > 0);
      await page.screenshot({ path: path.join(ROOT, out), omitBackground: true });
    };
    for (const p of PISTES) {
      const d = p.dossier;
      await shot(`${d}/app-icon.svg`, 1024, `${d}/png/app-icon-1024.png`);
      await shot(`${d}/app-icon.svg`, 512, `${d}/png/app-icon-512.png`);
      await shot(`${d}/app-icon.svg`, 64, `${d}/png/app-icon-64.png`);
      await shot(`${d}/app-icon-small.svg`, 32, `${d}/png/app-icon-32.png`);
      await shot(`${d}/app-icon-small.svg`, 16, `${d}/png/app-icon-16.png`);
      await shot(`${d}/favicon.svg`, 32, `${d}/png/favicon-32.png`);
      await shot(`${d}/favicon.svg`, 16, `${d}/png/favicon-16.png`);
    }
    await page.close();

    // Captures de la planche, clair et sombre, 1440 px de large, écran Retina.
    fs.mkdirSync(path.join(ROOT, 'captures'), { recursive: true });
    for (const scheme of ['light', 'dark']) {
      const ctx = await browser.newContext({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, colorScheme: scheme });
      const pg = await ctx.newPage();
      await pg.goto(url('planche.html'));
      await pg.waitForLoadState('load');
      const name = scheme === 'light' ? 'clair' : 'sombre';
      await pg.screenshot({ path: path.join(ROOT, `captures/planche-${name}.png`), fullPage: true });
      // Vue d'ensemble : du titre jusqu'à la fin des trois pistes côte à côte.
      const bottom = await pg.evaluate(() => document.querySelector('.pistes').getBoundingClientRect().bottom + window.scrollY + 24);
      await pg.screenshot({ path: path.join(ROOT, `captures/pistes-${name}.png`), clip: { x: 0, y: 0, width: 1440, height: bottom }, fullPage: true });
      await ctx.close();
    }
  } finally {
    await browser.close();
  }
  console.log('PNG et captures écrits.');
})();
