// Brimline, deuxième tour : géométrie des trois pistes (source unique).
// Le symbole est dessiné sur une grille de 64 unités ; le glyphe de la barre des menus sur 18 pt.
// Chaque fonction rend un fragment SVG (sans la balise <svg>), pour l'insérer en ligne.

// Couleurs. Le symbole de l'icône a sa propre encre (pétrole profond), les autres viennent de ../../tokens.json.
// Une seule couleur pour tout le symbole, comme Firméa : la marque est un aplat, pas un dessin en deux tons.
const C = {
  tileTop: '#0F2F3B',     // encre pétrole, haut de la tuile (nouvelle couleur de marque, réservée à l'icône)
  tileBot: '#061319',     // encre pétrole, bas de la tuile
  mark: '#7ADFE4',        // symbole sur la tuile
  light: { text: '#15191D', mark: '#0B6E7A' },     // jetons text, accent (clair)
  dark: { text: '#ECEFF2', mark: '#5CC8D0' },      // jetons text, accent (sombre)
};

let uid = 0;
const id = (p) => `${p}${++uid}`;

// Forme du liquide : rectangle à fond arrondi (rayon = demi-largeur), coupé par le haut au niveau voulu.
function liquid({ x, w, bottom, top, fill, extra = '' }) {
  const r = w / 2;
  const h = Math.max(0, bottom - top);
  if (h <= 0) return '';
  const cid = id('c');
  // Le fond arrondi entier, coupé par un rectangle depuis le niveau.
  return `<clipPath id="${cid}"><rect x="${x - 1}" y="${top}" width="${w + 2}" height="${h + 1}"/></clipPath>` +
    `<path clip-path="url(#${cid})" fill="${fill}"${extra} d="M${x} ${bottom - Math.max(r, h) - 0.01}V${bottom - r}a${r} ${r} 0 0 0 ${w} 0V${bottom - Math.max(r, h) - 0.01}Z"/>`;
}

// Liquide à niveau réglable dans la planche : le rectangle de coupe porte data-course, le script le déplace.
function liquidLive({ x, w, bottom, topMax, level, fill }) {
  const r = w / 2;
  const cid = id('c');
  const top = bottom - level * (bottom - topMax);
  return `<clipPath id="${cid}"><rect class="lvl" data-bottom="${bottom}" data-top="${topMax}" x="${x - 1}" y="${top}" width="${w + 2}" height="${bottom - top + 1}"/></clipPath>` +
    `<path clip-path="url(#${cid})" fill="${fill}" d="M${x} ${topMax}V${bottom - r}a${r} ${r} 0 0 0 ${w} 0V${topMax}Z"/>`;
}

const PISTES = [
  {
    id: 'a',
    dossier: 'piste-a-flottaison',
    titre: 'A · Flottaison',
    idee: 'Une colonne haute, traversée par sa ligne de charge, comme la marque de Plimsoll peinte sur la coque des navires : la ligne jusqu\'où l\'on peut charger, et pas plus. Le liquide monte vers elle.',
    pour: 'Un vrai emblème, avec une histoire juste (la ligne de charge des cargos) : il se retient et se reconnaît de loin. Colonne haute, ligne franche, une seule épaisseur de trait, comme Firméa.',
    contre: 'La ligne qui sort de la colonne élargit le glyphe : dans la barre des menus, la course du liquide est un peu plus courte (8,5 pt).',
    // Symbole, grille 64.
    mark({ structure, fill, s = 4.5, level = 0.7 }) {
      const k = s / 4.5;
      const x = 20, y = 8, w = 24, h = 48;
      const lx = 25.5 + (k - 1) * 1.5, lw = 13 - (k - 1) * 3;
      return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${w / 2}" fill="none" stroke="${structure}" stroke-width="${s}"/>` +
        `<path d="M9 21H55" stroke="${structure}" stroke-width="${s}" stroke-linecap="round"/>` +
        liquid({ x: lx, w: lw, bottom: 50.5 - (k - 1) * 1.5, top: 50.5 - level * (50.5 - 27), fill });
    },
    // Glyphe gabarit 18 pt, noir et transparence.
    glyph(level, live = false) {
      const geo = { x: 7, w: 4, bottom: 15, topMax: 6.5, level, fill: 'currentColor' };
      return `<rect x="5.25" y="1.25" width="7.5" height="15.5" rx="3.75" fill="none" stroke="currentColor" stroke-width="1.5"/>` +
        `<path d="M1.75 4.75H16.25" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>` +
        (live ? liquidLive(geo) : liquid({ ...geo, top: geo.bottom - Math.max(level > 0 ? 1 : 0, level * (geo.bottom - geo.topMax)) }));
    },
    course: 8.5,
    wordmark: 'side',
  },
  {
    id: 'b',
    dossier: 'piste-b-seuil',
    titre: 'B · Seuil',
    idee: 'Deux formes et rien d\'autre : une colonne pleine, haute, et au-dessus d\'elle le trait qu\'elle ne doit pas toucher. L\'écart entre les deux, c\'est ce qui reste.',
    pour: 'La plus simple et la plus forte en petit : deux aplats, lisibles à 16 px sans effort. La course est la plus haute des trois dans la barre des menus (12,5 pt).',
    contre: 'Très épurée : sa force tient aux proportions, à garder telles quelles (écart fixe sous le trait, colonne jamais collée).',
    mark({ structure, fill, s = 4.5, level = 0.78 }) {
      const top = 56 - level * (56 - 19);
      return `<path d="M17 10H47" stroke="${structure}" stroke-width="${s}" stroke-linecap="round"/>` +
        `<path d="M22 46a10 10 0 0 0 20 0V${top + 2.5}a2.5 2.5 0 0 0 -2.5 -2.5H24.5a2.5 2.5 0 0 0 -2.5 2.5Z" fill="${fill}"/>`;
    },
    glyph(level, live = false) {
      const geo = { x: 5.5, w: 7, bottom: 17, topMax: 4.5, level, fill: 'currentColor' };
      return `<path d="M2.75 1.75H15.25" stroke="currentColor" stroke-width="1.5" stroke-linecap="round"/>` +
        `<path d="M5.5 4.5V13.5a3.5 3.5 0 0 0 7 0V4.5Z" fill="currentColor" opacity=".25"/>` +
        (live ? liquidLive(geo) : liquid({ ...geo, top: geo.bottom - Math.max(level > 0 ? 1 : 0, level * (geo.bottom - geo.topMax)) }));
    },
    course: 12.5,
    wordmark: 'side',
  },
  {
    id: 'c',
    dossier: 'piste-c-le-l',
    titre: 'C · Le l',
    idee: 'La colonne devient le « l » du nom : Brim·l·ine. Une éprouvette haute et étroite, dont le haut est le bord (le brim), qui se remplit. Le symbole et le mot ne font qu\'un.',
    pour: 'Le lien le plus fort entre le nom et le symbole : le logo se lit comme un mot, et la colonne seule suffit en icône. Course haute dans la barre des menus (12 pt).',
    contre: 'Le trait de limite n\'est plus dessiné : c\'est le bord de la colonne qui le porte. Le logotype demande une police vectorisée pour le figer (lot d\'intégration).',
    // cw : largeur de la colonne ; le logotype en prend une plus étroite, pour que le « l » se lise comme une lettre.
    mark({ structure, fill, s = 4.5, level = 0.62, cw = 22, gap = 3.25 }) {
      const lw = cw - s - 2 * gap, lx = 32 - lw / 2;
      const bottom = 58 - s / 2 - gap, topMax = 6 + s / 2 + gap;
      return `<rect x="${32 - cw / 2}" y="6" width="${cw}" height="52" rx="${cw / 2}" fill="none" stroke="${structure}" stroke-width="${s}"/>` +
        liquid({ x: lx, w: lw, bottom, top: bottom - level * (bottom - topMax), fill });
    },
    glyph(level, live = false) {
      const geo = { x: 6.5, w: 5, bottom: 15, topMax: 3, level, fill: 'currentColor' };
      return `<rect x="4.75" y="1.25" width="8.5" height="15.5" rx="4.25" fill="none" stroke="currentColor" stroke-width="1.5"/>` +
        (live ? liquidLive(geo) : liquid({ ...geo, top: geo.bottom - Math.max(level > 0 ? 1 : 0, level * (geo.bottom - geo.topMax)) }));
    },
    course: 12,
    wordmark: 'inline',
  },
];

// Icône d'app, grille macOS 1024 : carré arrondi de 824 à 100 du bord, rayon 185,4, ombre portée.
function appIcon(p, { small = false } = {}) {
  const g = id('g'), sh = id('s'), hl = id('h');
  const s = small ? 7 : 4.5;
  const scale = small ? 14.2 : 12.875;     // la marque occupe un peu plus de la tuile en petit
  const off = 512 - 32 * scale;
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
<defs>
<linearGradient id="${g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.tileTop}"/><stop offset="1" stop-color="${C.tileBot}"/></linearGradient>
<radialGradient id="${hl}" cx=".5" cy=".0" r=".9"><stop offset="0" stop-color="#FFFFFF" stop-opacity=".10"/><stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/></radialGradient>
${small ? '' : `<filter id="${sh}" x="-20%" y="-20%" width="140%" height="150%"><feGaussianBlur in="SourceAlpha" stdDeviation="14"/><feOffset dy="12"/><feComponentTransfer><feFuncA type="linear" slope=".32"/></feComponentTransfer><feMerge><feMergeNode/><feMergeNode in="SourceGraphic"/></feMerge></filter>`}
</defs>
<g${small ? '' : ` filter="url(#${sh})"`}>
<rect x="100" y="100" width="824" height="824" rx="185.4" fill="url(#${g})"/>
${small ? '' : `<rect x="100" y="100" width="824" height="824" rx="185.4" fill="url(#${hl})"/>
<rect x="101" y="101" width="822" height="822" rx="184.4" fill="none" stroke="#FFFFFF" stroke-opacity=".10" stroke-width="2"/>`}
</g>
<g transform="translate(${off} ${off}) scale(${scale})">${p.mark({ structure: C.mark, fill: C.mark, s })}</g>
</svg>`;
}

// Favicon : la tuile et le symbole, traits épais pour 16 px.
function favicon(p) {
  const g = id('g');
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" width="64" height="64">
<defs><linearGradient id="${g}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.tileTop}"/><stop offset="1" stop-color="${C.tileBot}"/></linearGradient></defs>
<rect width="64" height="64" rx="14" fill="url(#${g})"/>
<g transform="translate(-3.2 -3.2) scale(1.1)">${p.mark({ structure: C.mark, fill: C.mark, s: 7.5 })}</g>
</svg>`;
}

// Symbole en couleur, pour le logo : tout en accent, le mot en couleur du texte.
function symbol(p, theme, { s = 4.5 } = {}) {
  const t = C[theme];
  return p.mark({ structure: t.mark, fill: t.mark, s });
}

// Symbole qui suit le thème par CSS (couleur courante).
function symbolCss(p, { s = 4.5 } = {}) {
  return p.mark({ structure: 'currentColor', fill: 'currentColor', s });
}

function glyphSvg(p, level, extra = '') {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="18" height="18" fill="none" role="img" aria-label="Brimline"${extra}>${p.glyph(level)}</svg>`;
}

module.exports = { PISTES, C, appIcon, favicon, symbol, symbolCss, glyphSvg };
