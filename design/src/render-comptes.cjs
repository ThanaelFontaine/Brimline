// Brimline, planche des comptes (QUOTA-70, 71, 72, lot D) : rend les captures par Chromium sans tête (Playwright).
// Usage : NODE_PATH=<dossier node_modules contenant playwright> node design/src/render-comptes.cjs
// Sortie : design/captures-comptes/<langue>-<thème>-<partie>.png, en 2x (les éléments « 1x » de la planche montrent
// les vrais pixels d'un écran 1x, agrandis sans lissage), plus barre-1x.png rendue avec un écran 1x.
// Pages entières (1440 et 390 px) dans FULL (variable d'environnement, sinon le dossier des captures), non versionnées.

const fs = require('fs');
const path = require('path');
const { chromium } = require('playwright');

const DESIGN = path.resolve(__dirname, '..');
const OUT = path.join(DESIGN, 'captures-comptes');
const PAGE = 'file://' + path.join(DESIGN, 'planche-comptes.html');
const FULL = process.env.FULL || OUT;
const PARTS = {
  barre: '[data-render="mainBars"]', cas: '[data-render="cases"]', mesures: '[data-render="zoom"]', variantes: '[data-render="variants"]',
  panneau: '#fig-panel', 'barre-panneau': '[data-render="panelBar"]', reglages: '#fig-settings', palette: '[data-render="palette"]',
};

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
          // Les barres et les variantes ne dépendent pas du thème de la page : une seule fois par langue.
          if (theme === 'dark' && ['barre', 'cas', 'mesures', 'variantes', 'barre-panneau'].includes(name)) continue;
          await page.locator(sel).first().screenshot({ path: path.join(OUT, `${lang}-${name}.png`.replace(`${lang}-`, ['barre', 'cas', 'mesures', 'variantes', 'barre-panneau'].includes(name) ? `${lang}-` : `${k}-`)) });
        }
        await page.close();
        const full = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1, colorScheme: theme });
        await full.goto(`${PAGE}#${k}`);
        await full.screenshot({ path: path.join(FULL, `${k}-planche-1440.png`), fullPage: true });
        await full.close();
      }
    }
    // La barre vue par un écran 1x, sans agrandissement.
    const one = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
    await one.goto(`${PAGE}#fr-light`);
    await one.locator(PARTS.barre).first().screenshot({ path: path.join(OUT, 'fr-barre-ecran-1x.png') });
    await one.close();
    // Lisibilité sur un téléphone (390 px).
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
