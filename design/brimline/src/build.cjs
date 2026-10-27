// Brimline : écrit les SVG de chaque piste et la planche (planche.html), depuis src/pistes.cjs.
// Usage : node design/brimline/src/build.cjs   (puis src/render.cjs pour les PNG et les captures)

const fs = require('fs');
const path = require('path');
const { PISTES, glyphSVG, glyphVarSVG, symbolSVG, logoSVG, faviconSVG, SYMBOL_STYLE } = require('./pistes.cjs');

const ROOT = path.resolve(__dirname, '..');
const RECO = 'a';

// ---------------------------------------------------------------- Fichiers SVG

for (const p of PISTES) {
  const dir = path.join(ROOT, p.dossier);
  fs.mkdirSync(path.join(dir, 'png'), { recursive: true });
  const files = {
    'app-icon.svg': p.icon(`${p.id}i`, true),
    'app-icon-small.svg': p.icon(`${p.id}s`, false),
    'menubar-template.svg': glyphSVG(p, 0.6),
    'glyph-level.svg': glyphVarSVG(p),
    'symbole.svg': symbolSVG(p),
    'logo.svg': logoSVG(p),
    'favicon.svg': faviconSVG(p),
  };
  for (const [name, body] of Object.entries(files)) fs.writeFileSync(path.join(dir, name), body);
}

// ---------------------------------------------------------------- Planche

const word = (p) => (p.id === 'b' ? 'brimline' : 'Brimline');
const glyph = (p, level, cls = 'g18', uid = '') =>
  `<svg class="${cls}" viewBox="0 0 18 18" fill="currentColor" aria-hidden="true"${level === 'dim' ? ' style="opacity:.45"' : ''}>${p.glyph(level === 'dim' ? 0.34 : level, `${p.id}${uid}`)}</svg>`;
let n = 0;
const sym = (p, cls = 'sym') => `<svg class="${cls}" viewBox="0 0 18 18" aria-hidden="true">${p.symbol(`${p.id}-sy${n++}`)}</svg>`;
const lockup = (p, size = 'm') => `<span class="lockup ${size}">${sym(p)}<span>${word(p)}</span></span>`;

const neighbours = ['n1', 'n2', 'n3', 'n4', 'n5'];
const dock = (p, theme) => `<div class="desk ${theme}"><div class="dock">
  ${neighbours.slice(0, 3).map((c) => `<i class="app ${c}"></i>`).join('')}
  <span class="dock-item"><img src="${p.dossier}/app-icon.svg" width="64" height="64" alt="Icône ${p.titre}"><b class="dot"></b></span>
  ${neighbours.slice(3).map((c) => `<i class="app ${c}"></i>`).join('')}
  <span class="sep"></span><i class="app trash"></i>
</div></div>`;

const menubar = (p, theme) => `<div class="mb ${theme}"><div class="mb-bar">
  <span class="mb-menus"><b>Finder</b><span>Fichier</span><span>Édition</span></span>
  <span class="mb-right"><i class="ph c"></i><i class="ph r"></i><span class="mb-item">${glyph(p, 0.72, 'g18', `mb${theme}`)}<span class="num">72 %</span></span><span>lun. 27 oct.</span><span class="num">09:41</span></span>
</div></div>`;

const STATES = [[0, '0 %'], [0.25, '25 %'], [0.72, '72 %'], [0.95, '95 %'], ['dim', 'expiré']];
const states = (p, theme) => `<div class="states ${theme}">${STATES.map(([l, t], i) =>
  `<figure>${glyph(p, l, 'g72', `st${theme}${i}`)}<figcaption>${t}</figcaption></figure>`).join('')}</div>`;

const site = (p, theme, mobile) => `<div class="site-frame ${mobile ? 'mobile' : 'desktop'} ${theme}"><div class="site ${theme}" style="width:${mobile ? 390 : 1440}px">
  <header class="topbar"><div class="wrap"><a class="brand">${sym(p, 'sym22')}<span>${word(p)}</span></a>
  <nav><a>Docs</a><a>FAQ</a>${mobile ? '' : '<a>GitHub</a>'}<a class="lang">FR</a></nav></div></header>
  <div class="wrap hero"><h1>See how much of every AI subscription you have left, account by account.</h1>
  <p>Brimline puts the limits of all your Claude accounts side by side in the menu bar of your Mac, each one under its email address.</p></div>
</div></div>`;

const tab = (p, theme) => `<div class="tabbar ${theme}"><div class="tab"><img src="${p.dossier}/favicon.svg" width="16" height="16" alt=""><span>Brimline: every AI subscription limit, account by account</span></div><div class="tab off"><i></i><span>Docs</span></div></div>`;

const pisteCard = (p) => `<article class="piste${p.id === RECO ? ' reco' : ''}">
  ${p.id === RECO ? '<p class="badge">Recommandée</p>' : ''}
  <img class="hero-icon" src="${p.dossier}/app-icon.svg" width="220" height="220" alt="Icône d'app, piste ${p.titre}">
  <h3>${p.titre}</h3>
  <p>${p.idee}</p>
  <dl><dt>Pour</dt><dd>${p.pour}</dd><dt>Contre</dt><dd>${p.contre}</dd></dl>
  <div class="lockups"><div class="band light">${lockup(p)}</div><div class="band dark">${lockup(p)}</div></div>
</article>`;

const small = (p) => `<div class="small-row">
  <h3>${p.titre}</h3>
  <figure><img src="${p.dossier}/png/app-icon-16.png" width="16" height="16" alt=""><figcaption>16 px</figcaption></figure>
  <figure><img src="${p.dossier}/png/app-icon-32.png" width="32" height="32" alt=""><figcaption>32 px</figcaption></figure>
  <figure><img src="${p.dossier}/png/app-icon-64.png" width="64" height="64" alt=""><figcaption>64 px</figcaption></figure>
  <figure><img class="px" src="${p.dossier}/png/app-icon-16.png" width="64" height="64" alt=""><figcaption>16 px agrandi ×4</figcaption></figure>
  <figure><img class="px" src="${p.dossier}/png/app-icon-32.png" width="64" height="64" alt=""><figcaption>32 px agrandi ×2</figcaption></figure>
  <figure><img class="px" src="${p.dossier}/png/favicon-16.png" width="64" height="64" alt=""><figcaption>favicon 16 px ×4</figcaption></figure>
  <div class="tabs">${tab(p, 'light')}${tab(p, 'dark')}</div>
</div>`;

const reco = PISTES.find((p) => p.id === RECO);

const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Brimline : planche icône et logo, trois pistes</title>
<!-- Planche autonome : aucun réseau, aucune police web. Générée par src/build.cjs depuis src/pistes.cjs : ne pas retoucher à la main.
     Couleurs : jetons de ../tokens.css (inchangés par le renommage). Le thème de la page suit prefers-color-scheme ;
     chaque mise en situation est montrée en clair et en sombre. -->
<link rel="stylesheet" href="../tokens.css">
<style>
  * { box-sizing: border-box; }
  body { margin: 0; background: var(--sg-bg); color: var(--sg-text); font: 15px/1.55 var(--sg-font-sans); }
  main { max-width: 1280px; margin: 0 auto; padding: 48px 32px 64px; }
  h1 { font-size: 40px; line-height: 1.15; margin: 0 0 8px; font-weight: 650; letter-spacing: -0.01em; }
  h2 { font-size: 22px; line-height: 1.15; margin: 56px 0 6px; }
  h2 + p.sub { margin: 0 0 20px; }
  h3 { font-size: 17px; margin: 0 0 6px; }
  .sub { color: var(--sg-text-2); font-size: 13px; }
  .lead { max-width: 760px; font-size: 17px; margin: 0 0 8px; }
  .num { font-variant-numeric: tabular-nums; }
  .light { --t: #15191D; --t2: #56606A; --bgc: #F5F6F7; --sf: #FFFFFF; --bd: #D3D8DD; --tr: #E7EAED; --ok: #127A82; --ac: #0B6E7A; }
  .dark { --t: #ECEFF2; --t2: #9BA5AF; --bgc: #111315; --sf: #1B1E21; --bd: #30353A; --tr: #2B3035; --ok: #3BBDC2; --ac: #5CC8D0; }
  .s { fill: var(--t, var(--sg-text)); } .l { fill: var(--ok, var(--sg-gauge-ok)); } .so { fill: none; stroke: var(--t, var(--sg-text)); stroke-width: 1; }

  .reco-box { margin: 24px 0 0; padding: 16px 20px; border-radius: 16px; background: var(--sg-surface); border: 1px solid var(--sg-border); border-left: 4px solid var(--sg-accent); max-width: 920px; }
  .reco-box p { margin: 4px 0; }
  .changes { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; max-width: 920px; margin-top: 16px; }
  .changes div { background: var(--sg-surface); border: 1px solid var(--sg-border); border-radius: 10px; padding: 12px 16px; font-size: 14px; }

  .pistes { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
  .piste { position: relative; background: var(--sg-surface); border: 1px solid var(--sg-border); border-radius: 16px; padding: 20px; }
  .piste.reco { border-color: var(--sg-accent); box-shadow: 0 0 0 1px var(--sg-accent); }
  .badge { position: absolute; top: 16px; right: 16px; margin: 0; font-size: 12px; font-weight: 600; color: var(--sg-accent); border: 1px solid var(--sg-accent); border-radius: 999px; padding: 2px 10px; }
  .hero-icon { display: block; margin: 0 auto 8px; }
  .piste p { margin: 0 0 8px; }
  dl { margin: 0 0 12px; font-size: 14px; } dt { font-weight: 600; margin-top: 6px; } dd { margin: 0; color: var(--sg-text-2); }
  .lockups { display: grid; gap: 8px; }
  .band { border-radius: 10px; padding: 18px 20px; background: var(--bgc); border: 1px solid var(--bd); }
  .lockup { display: inline-flex; align-items: center; gap: 10px; color: var(--t); font-weight: 650; letter-spacing: -0.01em; }
  .lockup.m { font-size: 28px; } .lockup.m .sym { width: 34px; height: 34px; }

  .grid2 { display: grid; grid-template-columns: 160px 1fr 1fr; gap: 12px 16px; align-items: center; }
  .grid2 > h3 { margin: 0; }
  .colhead { font-size: 13px; color: var(--sg-text-2); font-weight: 600; }

  /* Dock */
  .desk { border-radius: 12px; padding: 28px 16px 10px; display: flex; justify-content: center; }
  .desk.light { background: linear-gradient(160deg, #C9D6E2, #EEF2F5); }
  .desk.dark { background: linear-gradient(160deg, #1F262D, #0B0D10); }
  .dock { display: flex; align-items: flex-end; gap: 6px; padding: 6px 8px 8px; border-radius: 22px; }
  .light .dock { background: rgb(255 255 255 / .55); box-shadow: inset 0 0 0 .5px rgb(0 0 0 / .12), 0 6px 20px rgb(0 0 0 / .12); }
  .dark .dock { background: rgb(40 44 48 / .6); box-shadow: inset 0 0 0 .5px rgb(255 255 255 / .14), 0 6px 20px rgb(0 0 0 / .4); }
  .app { display: block; width: 52px; height: 52px; margin: 6px; border-radius: 12px; }
  .n1 { background: linear-gradient(#7FB2F0, #2F6FD6); } .n2 { background: linear-gradient(#FFFFFF, #DADDE0); } .n3 { background: linear-gradient(#FFB36B, #E5732B); }
  .n4 { background: linear-gradient(#8E959C, #4A5157); } .n5 { background: linear-gradient(#9EE3A0, #36A54A); } .trash { background: linear-gradient(#E8ECEF, #B7BEC4); border-radius: 10px; width: 44px; }
  .dock-item { position: relative; display: block; width: 64px; height: 64px; }
  .dot { position: absolute; left: 50%; bottom: -5px; width: 4px; height: 4px; margin-left: -2px; border-radius: 50%; }
  .light .dot { background: rgb(0 0 0 / .6); } .dark .dot { background: rgb(255 255 255 / .75); }
  .sep { width: 1px; align-self: stretch; margin: 8px 4px; }
  .light .sep { background: rgb(0 0 0 / .15); } .dark .sep { background: rgb(255 255 255 / .18); }

  /* Barre des menus */
  .mb { border-radius: 12px; overflow: hidden; height: 44px; }
  .mb.light { background: linear-gradient(160deg, #C9D6E2, #EEF2F5); color: rgb(0 0 0 / .85); }
  .mb.dark { background: linear-gradient(160deg, #1F262D, #0B0D10); color: rgb(255 255 255 / .92); }
  .mb-bar { display: flex; justify-content: space-between; align-items: center; height: 26px; padding: 0 12px; font-size: 13px; white-space: nowrap; }
  .light .mb-bar { background: rgb(246 246 246 / .78); } .dark .mb-bar { background: rgb(28 30 33 / .7); }
  .mb-menus { display: flex; gap: 16px; overflow: hidden; } .mb-menus b { font-weight: 700; }
  .mb-right { display: flex; align-items: center; gap: 14px; }
  .mb-item { display: inline-flex; align-items: center; gap: 4px; }
  .ph { display: block; width: 15px; height: 13px; border: 1.5px solid currentColor; border-radius: 3px; opacity: .85; }
  .ph.c { border-radius: 50%; width: 14px; height: 14px; }
  .g18 { width: 18px; height: 18px; flex: none; }
  .states { display: flex; gap: 22px; padding: 14px 18px; border-radius: 12px; justify-content: space-between; }
  .states.light { background: #FFFFFF; color: #15191D; border: 1px solid #D3D8DD; } .states.dark { background: #1B1E21; color: #ECEFF2; border: 1px solid #30353A; }
  .states figure { margin: 0; text-align: center; font-size: 12px; }
  .states figcaption { opacity: .75; }
  .g72 { width: 54px; height: 54px; display: block; }

  /* Petites tailles */
  .small-row { display: flex; align-items: flex-end; gap: 22px; padding: 16px 0; border-top: 1px solid var(--sg-border); flex-wrap: wrap; }
  .small-row h3 { width: 160px; align-self: center; margin: 0; }
  .small-row figure { margin: 0; text-align: center; font-size: 12px; color: var(--sg-text-2); }
  .small-row figure img { display: block; margin: 0 auto 4px; }
  .px { image-rendering: pixelated; }
  .tabs { display: grid; gap: 8px; margin-left: auto; }
  .tabbar { display: flex; gap: 2px; padding: 6px 8px 0; border-radius: 10px 10px 0 0; width: 440px; font-size: 12px; }
  .tabbar.light { background: #DFE3E7; color: #15191D; } .tabbar.dark { background: #0B0D10; color: #ECEFF2; }
  .tab { display: flex; align-items: center; gap: 8px; padding: 7px 10px; border-radius: 8px 8px 0 0; min-width: 0; flex: 1 1 auto; }
  .tab span { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .light .tab:not(.off) { background: #FFFFFF; } .dark .tab:not(.off) { background: #24282C; }
  .tab.off { flex: 0 0 110px; opacity: .7; } .tab.off i { width: 16px; height: 16px; border-radius: 4px; background: currentColor; opacity: .3; }

  /* En-tête de site */
  .sites { display: grid; gap: 12px; }
  .site-frame { overflow: hidden; border-radius: 10px; border: 1px solid var(--sg-border); background: var(--bgc); }
  .site-frame .site { -webkit-mask-image: linear-gradient(#000 0, #000 var(--fade, 130px), transparent var(--fade-end, 170px)); }
  .site-frame.mobile .site { --fade: 220px; --fade-end: 290px; }
  .site-frame.desktop { height: 150px; } .site-frame.desktop .site { --fade: 120px; --fade-end: 175px; } .site-frame.desktop .site { transform: scale(.8444); transform-origin: 0 0; }
  .site-frame.mobile { height: 240px; width: 312px; } .site-frame.mobile .site { transform: scale(.8); transform-origin: 0 0; }
  .mobiles { display: flex; gap: 12px; }
  .site { background: var(--bgc); color: var(--t); height: 400px; }
  .site .topbar { border-bottom: 1px solid var(--bd); background: var(--sf); }
  .site .wrap { max-width: 1080px; margin: 0 auto; padding: 0 16px; }
  .site .topbar .wrap { display: flex; align-items: center; justify-content: space-between; height: 60px; }
  .site .brand { display: inline-flex; align-items: center; gap: 8px; font-weight: 650; font-size: 1.05rem; color: var(--t); }
  .sym22 { width: 22px; height: 22px; }
  .site nav { display: flex; gap: 2px; } .site nav a { padding: 8px 10px; font-size: 15px; font-weight: 500; color: var(--t2); }
  .site nav .lang { border: 1px solid var(--bd); border-radius: 6px; padding: 5px 9px; margin-left: 4px; font-weight: 600; }
  .site .hero h1 { font-size: 56px; margin: 40px 0 16px; max-width: 900px; line-height: 1.1; }
  .mobile .site .hero h1 { font-size: 34px; margin-top: 24px; }
  .site .hero p { font-size: 17px; color: var(--t2); max-width: 680px; margin: 0; }
  .files { font-family: var(--sg-font-mono); font-size: 13px; color: var(--sg-text-2); }
</style>
</head>
<body>
<main>
<h1>Brimline · icône et logo</h1>
<p class="lead">Sightglass devient Brimline. <em>Brim</em>, le bord, le ras ; <em>line</em>, le trait de niveau. Trois pistes, dans l'esprit de l'actuel : un liquide qui monte vers une limite. Chacune est déclinée en icône d'app, en glyphe de la barre des menus, en favicon et en logo.</p>
<p class="sub">QUOTA-34 · planche du 27/10/2026 · à valider par Thanaël avant tout changement dans l'app et le site.</p>

<div class="changes">
  <div><strong>Ce qui change</strong><br>Le nom, le symbole, l'icône de l'app, le glyphe de la barre des menus, le favicon et le logo du site.</div>
  <div><strong>Ce qui ne change pas</strong><br>Les jetons (couleurs, jauges, typographie système, rayons) : la DA de Sightglass reste valable, seul le nom et le symbole bougent.</div>
</div>

<div class="reco-box">
  <p><strong>Recommandation : piste ${reco.titre}.</strong></p>
  <p>Elle dit le nom à la lettre (un bord, un trait) et garde le niveau vertical déjà appris dans la barre des menus, sans confusion possible avec la batterie de macOS.</p>
  <p>C'est la plus nette des trois à 16 px et dans la barre des menus, où les quatre états se distinguent encore d'un regard.</p>
</div>

<h2>Les trois pistes, côte à côte</h2>
<p class="sub">Icône d'app (source 1024 px) et logo horizontal, en clair et en sombre. Le logotype est en police système, comme le site.</p>
<section class="pistes">${PISTES.map(pisteCard).join('\n')}</section>

<h2>Dans la barre des menus</h2>
<p class="sub">Glyphe gabarit 18 pt, noir et transparence, teinté par macOS. Taille réelle, avec le pourcentage affiché. Le liquide monte vers la limite ; expiré : opacité 0,45.</p>
<div class="grid2"><span></span><span class="colhead">Clair</span><span class="colhead">Sombre</span>
${PISTES.map((p) => `<h3>${p.titre}</h3>${menubar(p, 'light')}${menubar(p, 'dark')}
<span class="sub">Niveaux, agrandis ×3</span>${states(p, 'light')}${states(p, 'dark')}`).join('\n')}
</div>

<h2>Dans le Dock</h2>
<p class="sub">Icône d'app 64 px parmi des voisines neutres.</p>
<div class="grid2"><span></span><span class="colhead">Clair</span><span class="colhead">Sombre</span>
${PISTES.map((p) => `<h3>${p.titre}</h3>${dock(p, 'light')}${dock(p, 'dark')}`).join('\n')}
</div>

<h2>Petites tailles et favicon</h2>
<p class="sub">Version simplifiée de l'icône en 16 et 32 px (pas de reflet, de ménisque ni de boulons, traits plus épais). Favicon : le symbole sur une tuile graphite.</p>
${PISTES.map(small).join('\n')}

<h2>En-tête du site</h2>
<p class="sub">brimline.thanaelfontaine.eu, textes réels de l'accueil. Bureau 1440 px (réduit à 84 %, haut de page) et téléphone 390 px (réduit à 80 %), en clair et en sombre.</p>
${PISTES.map((p) => `<h3 style="margin-top:20px">${p.titre}</h3>
<div class="sites">${site(p, 'light', false)}${site(p, 'dark', false)}</div>
<div class="mobiles" style="margin-top:12px">${site(p, 'light', true)}${site(p, 'dark', true)}</div>`).join('\n')}

<h2>Fichiers</h2>
<p class="files">design/brimline/&lt;piste&gt;/ : app-icon.svg (1024), app-icon-small.svg (16 et 32 px), menubar-template.svg, glyph-level.svg, symbole.svg, logo.svg, favicon.svg, png/</p>
</main>
</body>
</html>
`;

fs.writeFileSync(path.join(ROOT, 'planche.html'), html);
console.log('SVG et planche écrits dans', ROOT);
