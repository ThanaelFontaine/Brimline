// Brimline, deuxième tour : écrit les SVG de chaque piste et la planche autonome (un seul fichier, SVG en ligne).
// Usage : node design/brimline/v2/src/build.cjs

const fs = require('fs');
const path = require('path');
const { PISTES, C, appIcon, favicon, symbol, symbolCss, glyphSvg } = require('./pistes.cjs');

const ROOT = path.resolve(__dirname, '..');
const RECO = 'a';
const write = (f, s) => { fs.mkdirSync(path.dirname(path.join(ROOT, f)), { recursive: true }); fs.writeFileSync(path.join(ROOT, f), s.trim() + '\n'); };
const strip = (s) => s.replace(/<svg [^>]*>/, '').replace(/<\/svg>\s*$/, '');
const inner = (s) => strip(s.trim());

// Logotype : police système, semi-gras, comme l'en-tête du site. Piste C : le « l » est la colonne.
const FONT = "-apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Helvetica Neue', Helvetica, Arial, sans-serif";
const L_BOX = '21.75 2.75 20.5 58.5';
const L_OPTS = { s: 6.5, cw: 14, gap: 1.75 };
const lMark = (p, cls = 'l-mark') => `<svg class="${cls}" viewBox="${L_BOX}" aria-hidden="true">${p.mark({ structure: 'currentColor', fill: 'currentColor', ...L_OPTS })}</svg>`;
const word = (p) => p.wordmark === 'inline'
  ? `<span class="word" aria-label="Brimline">Brim${lMark(p)}ine</span>`
  : '<span class="word">Brimline</span>';
const sym = (p, cls = 'sym') => `<svg class="${cls}" viewBox="0 0 64 64" aria-hidden="true">${symbolCss(p)}</svg>`;
const lockup = (p) => p.wordmark === 'inline' ? `<span class="lockup inline">${word(p)}</span>` : `<span class="lockup">${sym(p)}${word(p)}</span>`;
const brand = (p) => p.wordmark === 'inline' ? `<a class="brand inline">${word(p)}</a>` : `<a class="brand">${sym(p, 'sym22')}${word(p)}</a>`;

// ---------- Fichiers de chaque piste ----------
for (const p of PISTES) {
  const d = p.dossier;
  write(`${d}/app-icon.svg`, appIcon(p));
  write(`${d}/app-icon-small.svg`, appIcon(p, { small: true }));
  write(`${d}/favicon.svg`, favicon(p));
  write(`${d}/menubar-template.svg`, glyphSvg(p, 0.6).replace(/currentColor/g, '#000000').replace('aria-label="Brimline">', 'aria-label="Brimline"><!-- Glyphe gabarit 18 pt, noir et transparence, niveau 60 %. -->'));
  write(`${d}/symbole.svg`, `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64" role="img" aria-label="Brimline"><style>g{color:${C.light.mark}}@media (prefers-color-scheme: dark){g{color:${C.dark.mark}}}</style><g>${symbolCss(p)}</g></svg>`);
  for (const theme of ['light', 'dark']) {
    const t = C[theme];
    const name = theme === 'light' ? 'clair' : 'sombre';
    const svg = p.wordmark === 'inline'
      ? `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 250 64" width="250" height="64" role="img" aria-label="Brimline">
<text x="4" y="47" font-family="${FONT.replace(/'/g, '&apos;')}" font-size="44" font-weight="600" fill="${t.text}" letter-spacing="-0.6">Brim</text>
<g transform="translate(103 13.6) scale(0.571)"><g transform="translate(-21.75 -2.75)">${p.mark({ structure: t.mark, fill: t.mark, ...L_OPTS })}</g></g>
<text x="117" y="47" font-family="${FONT.replace(/'/g, '&apos;')}" font-size="44" font-weight="600" fill="${t.text}" letter-spacing="-0.6">ine</text>
</svg>`
      : `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 270 64" width="270" height="64" role="img" aria-label="Brimline">
<g transform="translate(0 4) scale(0.875)">${symbol(p, theme)}</g>
<text x="66" y="46" font-family="${FONT.replace(/'/g, '&apos;')}" font-size="40" font-weight="600" fill="${t.text}" letter-spacing="-0.6">Brimline</text>
</svg>`;
    write(`${d}/logo-${name}.svg`, svg);
  }
}

// ---------- Planche ----------
const LEVELS = [[0, '0 %'], [0.3, '30 %'], [0.72, '72 %'], [0.95, '95 %'], [1, '100 %'], ['dim', 'expiré']];
const glyph = (p, level, cls = 'g18', live = false) => {
  const dim = level === 'dim';
  return `<svg class="${cls}${live ? ' live' : ''}" viewBox="0 0 18 18" fill="none" aria-hidden="true"${dim ? ' style="opacity:.45"' : ''}>${p.glyph(dim ? 0.34 : level, live)}</svg>`;
};

const neighbours = ['n1', 'n2', 'n3', 'n4', 'n5'];
const dock = (p, theme) => `<div class="desk ${theme}"><div class="dock">
  ${neighbours.slice(0, 3).map((c) => `<i class="app ${c}"></i>`).join('')}
  <span class="dock-item"><span class="tip">Brimline</span><svg class="dock-icon" viewBox="0 0 1024 1024" aria-label="Icône ${p.titre}">${inner(appIcon(p))}</svg><b class="dot"></b></span>
  ${neighbours.slice(3).map((c) => `<i class="app ${c}"></i>`).join('')}
  <span class="sep"></span><i class="app trash"></i>
</div></div>`;

const menubar = (p, theme) => `<div class="mb ${theme}"><div class="mb-bar">
  <span class="mb-menus"><b>Finder</b><span>Fichier</span><span>Édition</span><span class="hide-s">Présentation</span></span>
  <span class="mb-right"><i class="ph wifi"></i><i class="ph batt"></i><span class="mb-item">${glyph(p, 0.72, 'g18', true)}<span class="num lvl-num">72 %</span></span><span class="hide-s">lun. 27 oct.</span><span class="num">09:41</span></span>
</div></div>`;

const states = (p, theme) => `<div class="states ${theme}">${LEVELS.map(([l, t]) =>
  `<figure>${glyph(p, l, 'g54')}<figcaption>${t}</figcaption></figure>`).join('')}</div>`;

const tab = (p, theme) => `<div class="tabbar ${theme}"><div class="tab"><svg class="fav" viewBox="0 0 64 64" aria-hidden="true">${inner(favicon(p))}</svg><span>Brimline : chaque limite d'abonnement IA, compte par compte</span><i class="x">×</i></div><div class="tab off"><i class="fav-off"></i><span>Documentation</span></div></div>`;

const site = (p, theme, mobile) => `<div class="site-frame ${mobile ? 'mobile' : 'desktop'}"><div class="site ${theme}" style="width:${mobile ? 390 : 1440}px">
  <header class="topbar"><div class="wrap">${brand(p)}
  <nav><a>Docs</a><a>FAQ</a>${mobile ? '' : '<a>GitHub</a>'}<a class="lang">EN</a></nav></div></header>
  <div class="wrap hero"><h1>Voyez ce qu'il vous reste de chaque abonnement IA, compte par compte.</h1>
  <p class="lead">Brimline met côte à côte, dans la barre des menus de votre Mac, les limites de tous vos comptes Claude, chacun sous son adresse. Vos agents lisent les mêmes chiffres.</p>
  <p class="cta"><a class="btn primary">Installer depuis la source</a><a class="btn ghost">Lire la documentation</a></p></div>
</div></div>`;

const pisteCard = (p) => `<article class="piste${p.id === RECO ? ' reco' : ''}" id="carte-${p.id}">
  ${p.id === RECO ? '<p class="badge">Recommandée</p>' : ''}
  <svg class="hero-icon" viewBox="0 0 1024 1024" role="img" aria-label="Icône d'app, piste ${p.titre}">${inner(appIcon(p))}</svg>
  <h3>${p.titre}</h3>
  <p>${p.idee}</p>
  <h4>Pour</h4><p class="muted">${p.pour}</p>
  <h4>Contre</h4><p class="muted">${p.contre}</p>
  <div class="lockups"><div class="band light">${lockup(p)}</div><div class="band dark">${lockup(p)}</div></div>
  <p><a class="more" href="#piste-${p.id}">Voir en situation ↓</a></p>
</article>`;

const pixels = (p) => `<div class="pixels">
  <figure><canvas class="px" data-src="small-${p.id}" data-size="16"></canvas><figcaption>Icône 16 px, pixels réels ×4</figcaption></figure>
  <figure><canvas class="px" data-src="small-${p.id}" data-size="32"></canvas><figcaption>Icône 32 px, ×2</figcaption></figure>
  <figure><canvas class="px" data-src="fav-${p.id}" data-size="16"></canvas><figcaption>Favicon 16 px, ×4</figcaption></figure>
  <figure><canvas class="px dark-px" data-src="glyph-${p.id}" data-size="18" data-tint="#FFFFFF"></canvas><figcaption>Barre des menus 18 px (1x), ×4</figcaption></figure>
</div>`;

const section = (p) => `<section class="situ" id="piste-${p.id}">
<h2>${p.titre}${p.id === RECO ? ' <span class="badge inline-badge">Recommandée</span>' : ''}</h2>
<p class="sub">${p.idee}</p>

<h3 class="h3">Barre des menus</h3>
<p class="sub">Glyphe gabarit 18 pt, noir et transparence, teinté par macOS. Taille réelle, avec le pourcentage. Course du liquide : ${String(p.course).replace('.', ',')} pt (glyphe actuel : 11 pt). Le curseur en haut de page fait monter le niveau.</p>
<div class="pair">${menubar(p, 'light')}${menubar(p, 'dark')}</div>
<div class="pair">${states(p, 'light')}${states(p, 'dark')}</div>

<h3 class="h3">Dock</h3>
<div class="pair">${dock(p, 'light')}${dock(p, 'dark')}</div>

<h3 class="h3">Onglet du navigateur et petites tailles</h3>
<div class="pair">${tab(p, 'light')}${tab(p, 'dark')}</div>
${pixels(p)}

<h3 class="h3">En-tête du site</h3>
<p class="sub">brimline.thanaelfontaine.eu, textes réels de l'accueil. Bureau 1440 px (réduit) et téléphone 390 px, en clair et en sombre.</p>
<div class="pair">${site(p, 'light', false)}${site(p, 'dark', false)}</div>
<div class="pair mobiles">${site(p, 'light', true)}${site(p, 'dark', true)}</div>
</section>`;

// Sources des rendus en pixels réels (canvas), en données : rien n'est chargé du réseau.
const enc = (s) => 'data:image/svg+xml;base64,' + Buffer.from(s.trim()).toString('base64');
const sources = {};
for (const p of PISTES) {
  sources[`small-${p.id}`] = enc(appIcon(p, { small: true }));
  sources[`fav-${p.id}`] = enc(favicon(p));
  sources[`glyph-${p.id}`] = enc(glyphSvg(p, 0.72).replace('fill="none"', 'fill="none" color="#FFFFFF"').replace(/currentColor/g, '#FFFFFF'));
}

const CSS = `
:root{color-scheme:light dark;--bg:#F5F6F7;--surface:#FFFFFF;--text:#15191D;--text2:#56606A;--border:#D3D8DD;--accent:#0B6E7A;--font:${FONT}}
@media (prefers-color-scheme:dark){:root:not([data-theme=light]){--bg:#111315;--surface:#1B1E21;--text:#ECEFF2;--text2:#9BA5AF;--border:#30353A;--accent:#5CC8D0}}
:root[data-theme=dark]{--bg:#111315;--surface:#1B1E21;--text:#ECEFF2;--text2:#9BA5AF;--border:#30353A;--accent:#5CC8D0}
:root[data-theme=light]{color-scheme:light}:root[data-theme=dark]{color-scheme:dark}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--text);font:16px/1.55 var(--font);-webkit-font-smoothing:antialiased}
main{max-width:1240px;margin:0 auto;padding:48px 32px 96px}
h1{font-size:clamp(30px,4.6vw,46px);line-height:1.1;letter-spacing:-.02em;margin:0 0 12px}
h2{font-size:28px;letter-spacing:-.01em;margin:72px 0 6px;line-height:1.2}
.h3{font-size:17px;margin:32px 0 6px}
h3{margin:18px 0 6px;font-size:19px}h4{margin:12px 0 2px;font-size:14px}
p{margin:0 0 8px}.lead{font-size:18px;max-width:780px}.sub,.muted{color:var(--text2);font-size:14px;max-width:820px}
a{color:var(--accent)}
.controls{position:sticky;top:0;z-index:5;display:flex;flex-wrap:wrap;gap:12px 24px;align-items:center;padding:10px 32px;background:color-mix(in srgb,var(--bg) 88%,transparent);backdrop-filter:blur(12px);-webkit-backdrop-filter:blur(12px);border-bottom:1px solid var(--border);font-size:14px}
.seg{display:inline-flex;border:1px solid var(--border);border-radius:8px;overflow:hidden}.seg button{font:inherit;color:var(--text);background:transparent;border:0;padding:5px 12px;cursor:pointer}.seg button[aria-pressed=true]{background:var(--accent);color:var(--bg)}
.controls label{display:inline-flex;gap:10px;align-items:center}.controls input{accent-color:var(--accent);width:160px}
.controls nav{display:flex;gap:14px;margin-left:auto}.controls nav a{text-decoration:none;font-weight:600}
.box{background:var(--surface);border:1px solid var(--border);border-radius:12px;padding:18px 22px;margin:20px 0}
.box.reco-box{border-left:4px solid var(--accent)}
.grid2{display:grid;grid-template-columns:1fr 1fr;gap:16px}.grid2 .box{margin:0}
.box ul{margin:6px 0 0;padding-left:20px;color:var(--text2);font-size:14px}
.refs{display:flex;gap:18px;align-items:center;margin:8px 0 4px}.refs figure{margin:0;text-align:center;font-size:12px;color:var(--text2)}.refs svg{width:72px;height:72px;display:block;margin:0 auto 4px}
.pistes{display:grid;grid-template-columns:repeat(3,1fr);gap:18px;margin-top:18px}
.piste{position:relative;background:var(--surface);border:1px solid var(--border);border-radius:16px;padding:24px}
.piste.reco{border:2px solid var(--accent)}
.badge{position:absolute;top:14px;right:14px;margin:0;font-size:12px;font-weight:600;color:var(--accent);border:1.5px solid var(--accent);border-radius:99px;padding:2px 10px}
.inline-badge{position:static;vertical-align:middle;margin-left:8px}
.hero-icon{display:block;width:216px;height:216px;margin:0 auto}
.lockups{display:grid;gap:10px;margin:16px 0 8px}
.band{border-radius:10px;padding:16px 20px;display:flex}.band.light{background:#F5F6F7;color:#15191D;border:1px solid #D3D8DD;--mk:${C.light.mark}}.band.dark{background:#111315;color:#ECEFF2;--mk:${C.dark.mark}}
.lockup{display:inline-flex;align-items:center;gap:12px;font-weight:600;font-size:34px;letter-spacing:-.02em;line-height:1}
.lockup .sym{width:48px;height:48px;margin:-4px 0;color:var(--mk)}
.word{display:inline-flex;align-items:baseline;white-space:nowrap}
.l-mark{height:.76em;width:calc(.76em * 20.5 / 58.5);margin:0 .03em 0 .04em;color:var(--mk);align-self:baseline;transform:translateY(.02em)}
.more{font-size:14px;font-weight:600;text-decoration:none}
.situ{border-top:1px solid var(--border);margin-top:72px}.situ h2{margin-top:40px}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:16px;margin:10px 0}
/* Barre des menus */
.mb{border-radius:10px;overflow:hidden;height:92px;position:relative}
.mb.light{background:linear-gradient(135deg,#C9D6E3,#E9D9CF)}.mb.dark{background:linear-gradient(135deg,#1C2433,#2F2433)}
.mb-bar{height:24px;display:flex;justify-content:space-between;align-items:center;padding:0 10px;font:13px/1 ${FONT};gap:12px}
.mb.light .mb-bar{background:rgba(246,246,246,.72);color:#000}.mb.dark .mb-bar{background:rgba(22,22,24,.62);color:#fff}
.mb-menus,.mb-right{display:flex;gap:14px;align-items:center;white-space:nowrap}.mb-item{display:inline-flex;gap:4px;align-items:center}
.g18{width:18px;height:18px;display:block}
.ph{display:inline-block;opacity:.85}.ph.wifi{width:15px;height:11px;border-radius:15px 15px 0 0/12px 12px 0 0;border:2px solid currentColor;border-bottom:0;clip-path:polygon(0 0,100% 0,50% 100%)}.ph.batt{width:22px;height:10px;border:1.5px solid currentColor;border-radius:3px;position:relative}.ph.batt::after{content:"";position:absolute;inset:1.5px 6px 1.5px 1.5px;background:currentColor;border-radius:1px}
.num{font-variant-numeric:tabular-nums}
.states{display:flex;justify-content:space-around;gap:6px;border-radius:10px;padding:14px 8px}
.states.light{background:#ECEDEF;color:#000}.states.dark{background:#232427;color:#fff}
.states figure{margin:0;text-align:center}.states figcaption{font-size:12px;opacity:.7;margin-top:6px}.g54{width:54px;height:54px;display:block}
/* Dock */
.desk{border-radius:10px;height:150px;display:flex;align-items:flex-end;justify-content:center;padding-bottom:10px}
.desk.light{background:linear-gradient(160deg,#B9CCE0,#E6D3C6)}.desk.dark{background:linear-gradient(160deg,#141C2B,#2A1F2E)}
.dock{display:flex;align-items:flex-end;gap:7px;padding:6px 8px;border-radius:20px}
.desk.light .dock{background:rgba(255,255,255,.42);box-shadow:inset 0 0 0 1px rgba(255,255,255,.55)}.desk.dark .dock{background:rgba(40,40,46,.55);box-shadow:inset 0 0 0 1px rgba(255,255,255,.12)}
.app{width:52px;height:52px;border-radius:12px;display:block;margin:6px}
.n1{background:linear-gradient(#5AA9F5,#2C6FE0)}.n2{background:linear-gradient(#FDFDFD,#E3E3E3)}.n3{background:linear-gradient(#5DD36C,#2EA548)}.n4{background:linear-gradient(#FFB54A,#F07B22)}.n5{background:linear-gradient(#3A3A3C,#1C1C1E)}.trash{background:linear-gradient(#D9DCE0,#AEB3BA);border-radius:10px}
.sep{width:1px;align-self:stretch;margin:8px 2px;background:rgba(127,127,127,.4)}
.dock-item{position:relative;display:flex;flex-direction:column;align-items:center}.dock-icon{width:64px;height:64px;display:block}
.dot{width:4px;height:4px;border-radius:50%;background:currentColor;margin-top:1px}.desk.light .dot{color:#222}.desk.dark .dot{color:#ddd}
.tip{position:absolute;top:-30px;font:12px/1 ${FONT};padding:5px 9px;border-radius:6px;white-space:nowrap}.desk.light .tip{background:rgba(240,240,240,.92);color:#111}.desk.dark .tip{background:rgba(50,50,54,.92);color:#eee}
/* Onglets */
.tabbar{display:flex;gap:2px;padding:8px 8px 0;border-radius:10px 10px 0 0;font:12px/1 ${FONT};overflow:hidden}
.tabbar.light{background:#DEE1E6;color:#1F1F1F}.tabbar.dark{background:#1F2023;color:#E3E3E3}
.tab{display:flex;align-items:center;gap:8px;padding:9px 12px;border-radius:9px 9px 0 0;min-width:0;flex:0 1 300px}.tab span{overflow:hidden;text-overflow:ellipsis;white-space:nowrap}
.tabbar.light .tab:not(.off){background:#FFFFFF}.tabbar.dark .tab:not(.off){background:#35363A}.tab.off{opacity:.7;flex:0 1 150px}
.fav{width:16px;height:16px;flex:none;display:block}.fav-off{width:16px;height:16px;border-radius:4px;background:rgba(127,127,127,.4);flex:none}.x{margin-left:auto;font-style:normal;opacity:.6}
.pixels{display:flex;flex-wrap:wrap;gap:24px;margin:16px 0}.pixels figure{margin:0;font-size:12px;color:var(--text2)}
.px{width:64px;height:64px;image-rendering:pixelated;display:block;border:1px solid var(--border);border-radius:6px;background:repeating-conic-gradient(#e6e6e6 0 25%,#fff 0 50%) 0 0/8px 8px}
.px.dark-px{width:72px;height:72px;background:#2A2B2E}
/* Site */
.site-frame{border:1px solid var(--border);border-radius:10px;overflow:hidden;position:relative}
.site-frame.desktop{aspect-ratio:1440/470}.site-frame.desktop .site{transform:scale(var(--k,.4));transform-origin:0 0}
.site-frame.mobile{width:${Math.round(390 * 0.72)}px;height:${Math.round(520 * 0.72)}px;justify-self:center}.site-frame.mobile .site{transform:scale(.72);transform-origin:0 0}
.site{height:600px;font-family:${FONT};--mk:${C.light.mark}}.site.light{background:#F5F6F7;color:#15191D}.site.dark{background:#111315;color:#ECEFF2;--mk:${C.dark.mark}}
.site .wrap{max-width:1080px;margin:0 auto;padding:0 24px}
.topbar{border-bottom:1px solid #D3D8DD}.site.dark .topbar{border-color:#30353A}
.topbar .wrap{display:flex;justify-content:space-between;align-items:center;height:64px}
.brand{display:inline-flex;align-items:center;gap:9px;font-weight:600;font-size:19px;letter-spacing:-.01em;color:inherit}
.brand .sym22{width:28px;height:28px;margin:-2px 0;color:var(--mk)}.brand.inline{font-size:21px}
.topbar nav{display:flex;gap:22px;font-size:15px}.topbar nav a{color:inherit;opacity:.8}.lang{font-weight:600}
.hero{padding-top:72px}.hero h1{font-size:60px;line-height:1.08;letter-spacing:-.025em;max-width:860px;margin-bottom:20px}
.hero .lead{font-size:19px;max-width:640px;color:#56606A}.site.dark .hero .lead{color:#9BA5AF}
.cta{display:flex;gap:12px;margin-top:28px;flex-wrap:wrap}.btn{display:inline-block;padding:12px 20px;border-radius:8px;font-size:16px;font-weight:600}
.site.light .btn.primary{background:#0B6E7A;color:#fff}.site.dark .btn.primary{background:#5CC8D0;color:#111315}.btn.ghost{border:1px solid currentColor;color:inherit;opacity:.85}.site a{text-decoration:none}
.site-frame.mobile .topbar .wrap{height:56px;padding:0 18px}.site-frame.mobile .topbar nav{gap:16px}
.site-frame.mobile .hero{padding:36px 18px 0}.site-frame.mobile .hero h1{font-size:34px}.site-frame.mobile .hero .lead{font-size:17px}
.files{font:13px/1.6 ui-monospace,'SF Mono',Menlo,monospace;color:var(--text2)}
table{border-collapse:collapse;font-size:14px;width:100%}td,th{border-bottom:1px solid var(--border);padding:8px 10px;text-align:left;vertical-align:top}th{color:var(--text2);font-weight:600}
@media (max-width:900px){.pistes,.grid2,.pair{grid-template-columns:1fr}main{padding:28px 18px 64px}.controls{padding:10px 18px}.controls nav{margin-left:0}.hide-s{display:none}}
`;

const JS = `
const SRC=${JSON.stringify(sources)};
const root=document.documentElement;
document.querySelectorAll('[data-set-theme]').forEach(b=>b.addEventListener('click',()=>{const t=b.dataset.setTheme;if(t==='auto')root.removeAttribute('data-theme');else root.dataset.theme=t;document.querySelectorAll('[data-set-theme]').forEach(x=>x.setAttribute('aria-pressed',String(x===b)));}));
const lvl=document.getElementById('niveau'),out=document.getElementById('niveau-val');
function setLevel(v){const f=v/100;out.textContent=v+' %';document.querySelectorAll('.lvl-num').forEach(n=>n.textContent=v+' %');
document.querySelectorAll('svg.live rect.lvl').forEach(r=>{const b=+r.dataset.bottom,t=+r.dataset.top;let h=f*(b-t);if(f>0&&h<1)h=1;r.setAttribute('y',b-h);r.setAttribute('height',h+1);});}
lvl.addEventListener('input',()=>setLevel(+lvl.value));setLevel(+lvl.value);
document.querySelectorAll('canvas.px').forEach(c=>{const n=+c.dataset.size;c.width=n;c.height=n;const im=new Image();im.onload=()=>{const x=c.getContext('2d');x.imageSmoothingEnabled=true;x.drawImage(im,0,0,n,n);};im.src=SRC[c.dataset.src];});
function fit(){document.querySelectorAll('.site-frame.desktop').forEach(f=>f.style.setProperty('--k',f.clientWidth/1440));}
addEventListener('resize',fit);fit();
`;

// Références étudiées (redessinées à main levée en SVG simple, pour mémoire ; pas de fichier tiers chargé).
const refFirmea = `<svg viewBox="0 0 64 64" aria-hidden="true"><rect width="64" height="64" rx="14" fill="#0A0F22"/><g transform="translate(8 6) scale(.75)"><path d="M12 50V35a20 20 0 0 1 40 0V50" stroke="#F5C66B" stroke-width="4.5" fill="none" stroke-linecap="round"/><path d="M32 12C33.5 23 36.5 25.6 47 27C36.5 28.4 33.5 31 32 42C30.5 31 27.5 28.4 17 27C27.5 25.6 30.5 23 32 12Z" fill="#F5C66B"/></g></svg>`;

const html = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Brimline · icône et logo, deuxième tour</title>
<style>${CSS}</style>
</head>
<body>
<div class="controls">
  <span class="seg" role="group" aria-label="Thème de la planche"><button data-set-theme="auto" aria-pressed="true">Système</button><button data-set-theme="light" aria-pressed="false">Clair</button><button data-set-theme="dark" aria-pressed="false">Sombre</button></span>
  <label>Niveau du glyphe <input id="niveau" type="range" min="0" max="100" value="72"> <b id="niveau-val" class="num">72 %</b></label>
  <nav>${PISTES.map((p) => `<a href="#piste-${p.id}">${p.titre}</a>`).join('')}</nav>
</div>
<main>
<h1>Brimline · icône et logo, deuxième tour</h1>
<p class="lead">Trois pistes nouvelles, toutes bâties sur une colonne haute : la jauge monte vers sa limite. Chacune en icône d'app, en glyphe de la barre des menus, en favicon et en logo, montrée en situation, en clair et en sombre.</p>
<p class="sub">QUOTA-34 · THA-1412 · planche du 27/10/2026 · le premier tour (Ras, Le b, Cadran) est abandonné en entier.</p>

<div class="grid2">
  <div class="box"><h4>Ce qui change depuis le premier tour</h4><ul>
    <li>La barre est haute : une colonne deux fois plus haute que large dans chaque piste, au lieu d'une cuve trapue.</li>
    <li>Un seul aplat de couleur pour tout le symbole, sur une encre pétrole profonde : plus de dégradé dans la marque, plus de reflet, plus de verre de laboratoire.</li>
    <li>Une seule épaisseur de trait, des formes géométriques simples, une idée par symbole.</li>
  </ul></div>
  <div class="box"><h4>Ce qui reste du premier tour</h4><ul>
    <li>Lisible à 16 px : une version de l'icône aux traits épaissis pour 16 et 32 px.</li>
    <li>Aucune confusion avec la batterie de macOS : la jauge est verticale, la batterie horizontale.</li>
    <li>Glyphe gabarit sans couleur dans la barre des menus ; jetons de couleur de l'app inchangés.</li>
  </ul></div>
</div>

<div class="box"><h4>Les références</h4>
<div class="refs"><figure>${refFirmea}Firméa</figure>
<p class="sub" style="margin:0">Firméa tient sa beauté de peu de choses : une seule couleur chaude sur un fond profond, une seule épaisseur de trait aux bouts arrondis, deux formes (une arche, une étoile) et beaucoup d'air autour. Le symbole occupe le centre de la tuile, et le mot, en police système semi-grasse, reste sobre à côté. Vorssaint, le projet d'origine de Firméa, va dans le même sens : une seule silhouette noire, pleine, sur une tuile blanche. Brimline en reprend la méthode (un aplat, un trait, une idée), pas le dessin.</p></div></div>

<div class="box reco-box"><h4>Recommandation : piste A · Flottaison.</h4>
<p>C'est la seule des trois qui soit un emblème : une colonne et sa ligne de charge, comme la marque de Plimsoll sur la coque des cargos, la ligne jusqu'où l'on peut charger. Elle dit le nom (le bord, la ligne), elle a une histoire qu'on peut raconter sur le site, et elle se reconnaît de loin dans le Dock.</p>
<p class="muted">B est la plus lisible en très petit, C la plus liée au mot. Si la marque doit avant tout se lire comme un nom, C ; si elle doit se faire oublier dans la barre des menus, B.</p></div>

<h2>Les trois pistes, côte à côte</h2>
<p class="sub">Icône d'app (grille macOS 1024) et logo horizontal, en clair et en sombre. Le logotype est en police système semi-grasse, comme le site.</p>
<section class="pistes">${PISTES.map(pisteCard).join('\n')}</section>

${PISTES.map(section).join('\n')}

<h2>Fichiers</h2>
<table><tr><th>Fichier</th><th>Rôle</th></tr>
<tr><td class="files">app-icon.svg</td><td>Icône d'app, grille macOS 1024 (tuile de 824 à 100 du bord, rayon 185,4, ombre), pour 64 px et plus.</td></tr>
<tr><td class="files">app-icon-small.svg</td><td>Version pour 16 et 32 px : traits épaissis (7 au lieu de 4,5 sur 64), marque un peu agrandie, sans ombre ni reflet.</td></tr>
<tr><td class="files">menubar-template.svg</td><td>Glyphe gabarit 18 pt, noir et transparence, niveau 60 %.</td></tr>
<tr><td class="files">symbole.svg, logo-clair.svg, logo-sombre.svg</td><td>Symbole en accent (clair ou sombre selon le thème) et logo horizontal.</td></tr>
<tr><td class="files">favicon.svg</td><td>La tuile et le symbole, traits épais pour 16 px.</td></tr>
<tr><td class="files">png/</td><td>Rendus : icône 1024, 512, 64, 32, 16 ; favicon 32 et 16 ; glyphe 18 et 36.</td></tr></table>
<p class="sub" style="margin-top:12px">Couleurs : l'accent et le texte viennent des jetons de <span class="files">design/tokens.json</span>, inchangés. Seule l'encre pétrole de la tuile (#0F2F3B à #061319) et l'aqua du symbole sur la tuile (#7ADFE4) sont nouvelles, réservées à l'icône et au favicon. Logotype non vectorisé (licence de SF Pro) : le lot d'intégration choisit une police sous licence libre pour figer le mot, surtout pour la piste C.</p>
</main>
<script>${JS}</script>
</body>
</html>`;

write('planche.html', html);
console.log('SVG et planche écrits dans', ROOT);
