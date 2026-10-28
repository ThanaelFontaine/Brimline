// Brimline, planche « Ranger la barre des menus » (QUOTA-73, lot L6) : rend les captures par Chromium sans tête (Playwright).
// Usage : NODE_PATH=<dossier node_modules contenant playwright> node design/src/render-barre.cjs
// Sortie : design/captures-barre/<langue>-<thème>-<partie>.png ; pages entières (1440 et 390 px) dans
// FULL (variable d'environnement, sinon le dossier des captures), non versionnées : trop lourdes pour le dépôt.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const DESIGN = path.resolve(__dirname, '..');
const OUT = path.join(DESIGN, 'captures-barre');
const PAGE = 'file://' + path.join(DESIGN, 'planche-barre.html');
const FULL = process.env.FULL || OUT;
const PARTS = { onglet: '#fig-tab', 'deux-apps': '#fig-partial', 'aucune-app': '#fig-empty', erreurs: '#fig-error', geste: '#fig-drag' };

(async () => {
  fs.mkdirSync(OUT, { recursive: true });
  const browser = await chromium.launch();
  console.log('PID du navigateur :', browser.process ? browser.process()?.pid : 'inconnu');
  try {
    for (const lang of ['fr', 'en']) {
      for (const theme of ['light', 'dark']) {
        const k = `${lang}-${theme}`;
        const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2, colorScheme: theme });
        await page.goto(`${PAGE}#${k}`);
        for (const [name, sel] of Object.entries(PARTS)) {
          await page.locator(sel).first().screenshot({ path: path.join(OUT, `${k}-${name}.png`) });
        }
        await page.close();
        const full = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1, colorScheme: theme });
        await full.goto(`${PAGE}#${k}`);
        await full.screenshot({ path: path.join(FULL, `${k}-planche-1440.png`), fullPage: true });
        await full.close();
      }
    }
    // Lisibilité sur un téléphone (390 px), une combinaison par thème suffit pour la mise en page.
    for (const k of ['fr-light', 'en-dark']) {
      const p = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, colorScheme: k.endsWith('dark') ? 'dark' : 'light' });
      await p.goto(`${PAGE}#${k}`);
      await p.screenshot({ path: path.join(FULL, `${k}-planche-390.png`), fullPage: true });
      await p.close();
    }
  } finally {
    await browser.close();
  }
})();
