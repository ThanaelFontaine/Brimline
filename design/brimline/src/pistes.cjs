// Brimline : géométrie des trois pistes de symbole (source unique des SVG et de la planche).
// Glyphe : grille 18 x 18 pt de la barre des menus, géométrie 2x (traits de 1,5 pt), noir et transparence.
// Icône : grille macOS 1024, carré arrondi de 824 à 100 du bord, rayon 185,4.

const C = {
  bgTop: '#2C333A', bgBottom: '#111417', frame: '#14181B',
  liquidTop: '#4FD0D6', liquidBottom: '#0E7C86', meniscus: '#A6ECEE', ok: '#3BBDC2',
  ivoryTop: '#FFFFFF', ivoryBottom: '#C9D1D8', metalTop: '#E6EAED', metalBottom: '#8C959D',
  textLight: '#15191D', textDark: '#ECEFF2', okLight: '#127A82', okDark: '#3BBDC2',
};

const r = (n) => Math.round(n * 100) / 100;

/** Hauteur de liquide pour un niveau : au moins un trait dès que le niveau dépasse 0, course pleine réservée à 100 %. */
function course(level, full, min = 1) {
  if (level <= 0) return 0;
  if (level >= 1) return full;
  return Math.min(Math.max(full * level, min), full - 0.5);
}

// Cadre commun des icônes : ombre, fond graphite, halo, liseré. `body` est dessiné dans le carré arrondi.
function iconFrame(id, body, { halo = true } = {}) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <title>Brimline</title>
  <defs>
    <linearGradient id="${id}-bg" x1="0" y1="100" x2="0" y2="924" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${C.bgTop}"/><stop offset="1" stop-color="${C.bgBottom}"/></linearGradient>
    <radialGradient id="${id}-halo" cx="512" cy="560" r="420" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${C.ok}" stop-opacity="0.18"/><stop offset="1" stop-color="${C.ok}" stop-opacity="0"/></radialGradient>
    <linearGradient id="${id}-liquid" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.liquidTop}"/><stop offset="1" stop-color="${C.liquidBottom}"/></linearGradient>
    <linearGradient id="${id}-ivory" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.ivoryTop}"/><stop offset="1" stop-color="${C.ivoryBottom}"/></linearGradient>
    <linearGradient id="${id}-metal" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="${C.metalTop}"/><stop offset="1" stop-color="${C.metalBottom}"/></linearGradient>
    <filter id="${id}-shadow" x="-10%" y="-10%" width="120%" height="125%"><feDropShadow dx="0" dy="10" stdDeviation="12" flood-color="#000" flood-opacity="0.32"/></filter>
    <filter id="${id}-glow" x="-30%" y="-200%" width="160%" height="500%"><feGaussianBlur stdDeviation="16"/></filter>
    <clipPath id="${id}-sq"><rect x="100" y="100" width="824" height="824" rx="185.4"/></clipPath>
  </defs>
  <rect x="100" y="100" width="824" height="824" rx="185.4" fill="${C.frame}" filter="url(#${id}-shadow)"/>
  <g clip-path="url(#${id}-sq)">
    <rect x="100" y="100" width="824" height="824" fill="url(#${id}-bg)"/>
    ${halo ? `<rect x="100" y="100" width="824" height="824" fill="url(#${id}-halo)"/>` : ''}
${body}
    <rect x="102" y="102" width="820" height="820" rx="183.4" fill="none" stroke="#FFFFFF" stroke-opacity="0.10" stroke-width="4"/>
  </g>
</svg>
`;
}

// ---------------------------------------------------------------- Piste A : Ras

const A = {
  id: 'a', dossier: 'piste-a-ras', nom: 'Ras', titre: 'A · Ras',
  idee: 'Une cuve ouverte et, au-dessus de son bord, un trait libre : la limite. Le liquide monte vers le trait.',
  pour: 'Garde le geste vertical de Sightglass, déjà appris. Dit le nom à la lettre (le bord, le trait). Très net à 16 px.',
  contre: 'Moins singulière comme marque seule : sa force vient du trait, à protéger (jamais collé à la cuve).',
  // Glyphe : trait de limite, cuve en U, liquide.
  glyph(level) {
    const h = course(level, 8);
    const liquid = h > 0 ? `<rect x="7" y="${r(13 - h)}" width="4" height="${r(h)}" rx="0.5"/>` : '';
    return `<rect x="2" y="2" width="14" height="1.5" rx="0.75"/><path d="M4 5H5.5V13.5A1 1 0 0 0 6.5 14.5H11.5A1 1 0 0 0 12.5 13.5V5H14V13.5A2.5 2.5 0 0 1 11.5 16H6.5A2.5 2.5 0 0 1 4 13.5Z"/>${liquid}`;
  },
  glyphVar: `<rect x="2" y="2" width="14" height="1.5" rx="0.75"/>
  <path d="M4 5H5.5V13.5A1 1 0 0 0 6.5 14.5H11.5A1 1 0 0 0 12.5 13.5V5H14V13.5A2.5 2.5 0 0 1 11.5 16H6.5A2.5 2.5 0 0 1 4 13.5Z"/>
  <rect x="7" y="5" width="4" height="8" rx="0.5" style="transform-origin: 0 13px; transform: scaleY(var(--level, 0.6))"/>`,
  // Symbole en couleur : structure en couleur du texte, liquide en sarcelle (niveau 62 %).
  symbol: () => `<rect class="s" x="2" y="2" width="14" height="1.5" rx="0.75"/><path class="s" d="M4 5H5.5V13.5A1 1 0 0 0 6.5 14.5H11.5A1 1 0 0 0 12.5 13.5V5H14V13.5A2.5 2.5 0 0 1 11.5 16H6.5A2.5 2.5 0 0 1 4 13.5Z"/><rect class="l" x="7" y="8" width="4" height="5" rx="0.5"/>`,
  icon(id, detail) {
    if (detail) {
      const inner = 'M380 388H644V668A68 68 0 0 1 576 736H448A68 68 0 0 1 380 668Z';
      const top = 736 - 0.62 * 348;
      return iconFrame(id, `    <g transform="translate(0 -20)">
      <clipPath id="${id}-in"><path d="${inner}"/></clipPath>
      <!-- verre de la cuve -->
      <path d="${inner}" fill="#FFFFFF" fill-opacity="0.06"/>
      <!-- liquide à 62 %, ménisque -->
      <g clip-path="url(#${id}-in)">
        <rect x="380" y="${r(top)}" width="264" height="${r(736 - top)}" fill="url(#${id}-liquid)"/>
        <rect x="380" y="${r(top)}" width="264" height="10" fill="${C.meniscus}" fill-opacity="0.85"/>
      </g>
      <!-- reflet -->
      <rect x="404" y="410" width="20" height="270" rx="10" fill="#FFFFFF" fill-opacity="0.18"/>
      <!-- cuve ouverte : parois de verre -->
      <path d="M352 388A14 14 0 0 1 380 388V668A68 68 0 0 0 448 736H576A68 68 0 0 0 644 668V388A14 14 0 0 1 672 388V668A96 96 0 0 1 576 764H448A96 96 0 0 1 352 668Z" fill="#FFFFFF" fill-opacity="0.34"/>
      <!-- le trait : la limite, au-dessus du bord -->
      <rect x="282" y="300" width="460" height="44" rx="22" fill="${C.ok}" fill-opacity="0.45" filter="url(#${id}-glow)"/>
      <rect x="282" y="300" width="460" height="44" rx="22" fill="url(#${id}-ivory)"/>
    </g>`);
    }
    const inner = 'M388 400H636V670A54 54 0 0 1 582 724H442A54 54 0 0 1 388 670Z';
    const top = 724 - 0.62 * 324;
    return iconFrame(id, `    <g transform="translate(0 -18)">
      <clipPath id="${id}-in"><path d="${inner}"/></clipPath>
      <rect x="388" y="${r(top)}" width="248" height="${r(724 - top)}" fill="${C.ok}" clip-path="url(#${id}-in)"/>
      <path d="M332 400H388V670A54 54 0 0 0 442 724H582A54 54 0 0 0 636 670V400H692V670A110 110 0 0 1 582 780H442A110 110 0 0 1 332 670Z" fill="#E6EAED"/>
      <rect x="272" y="280" width="480" height="72" rx="36" fill="#FFFFFF"/>
    </g>`, { halo: false });
  },
};

// ---------------------------------------------------------------- Piste B : Le b

const B_OUT = 'M3 1.75A0.75 0.75 0 0 1 4.5 1.75V5H11A4 4 0 0 1 15 9V13A4 4 0 0 1 11 17H3Z';
const B_IN = 'M4.5 6.5H11A2.5 2.5 0 0 1 13.5 9V13A2.5 2.5 0 0 1 11 15.5H4.5Z';

const Bp = {
  id: 'b', dossier: 'piste-b-monogramme', nom: 'Le b', titre: 'B · Le b',
  idee: 'Un « b » minuscule : la hampe est la règle de niveau, la panse est la cuve qui se remplit.',
  pour: 'La plus « marque » des trois : une initiale qu\'on retient, forte en icône et en favicon.',
  contre: 'Course de liquide plus courte dans la barre des menus (6 pt contre 8) : 70 et 95 % se distinguent moins. Les monogrammes en « b » sont nombreux.',
  glyph(level) {
    const h = course(level, 6);
    const liquid = h > 0 ? `<rect x="6" y="${r(14 - h)}" width="6" height="${r(h)}" rx="0.75"/>` : '';
    return `<path fill-rule="evenodd" d="${B_OUT}${B_IN}"/>${liquid}`;
  },
  glyphVar: `<path fill-rule="evenodd" d="${B_OUT}${B_IN}"/>
  <rect x="6" y="8" width="6" height="6" rx="0.75" style="transform-origin: 0 14px; transform: scaleY(var(--level, 0.6))"/>`,
  symbol: () => `<path class="s" fill-rule="evenodd" d="${B_OUT}${B_IN}"/><rect class="l" x="6" y="10.25" width="6" height="3.75" rx="0.75"/>`,
  icon(id, detail) {
    if (detail) {
      const inner = 'M378 476H552A94 94 0 0 1 646 570V654A94 94 0 0 1 552 748H378Z';
      const top = 748 - 0.62 * 272;
      return iconFrame(id, `    <clipPath id="${id}-in"><path d="${inner}"/></clipPath>
    <path d="${inner}" fill="#FFFFFF" fill-opacity="0.06"/>
    <g clip-path="url(#${id}-in)">
      <rect x="378" y="${r(top)}" width="268" height="${r(748 - top)}" fill="url(#${id}-liquid)"/>
      <rect x="378" y="${r(top)}" width="268" height="10" fill="${C.meniscus}" fill-opacity="0.85"/>
      <rect x="400" y="496" width="18" height="230" rx="9" fill="#FFFFFF" fill-opacity="0.16"/>
    </g>
    <!-- le b : hampe (la règle) et panse (la cuve) -->
    <path fill-rule="evenodd" fill="url(#${id}-ivory)" d="M322 248A28 28 0 0 1 378 248V420H552A150 150 0 0 1 702 570V654A150 150 0 0 1 552 804H322ZM378 476H552A94 94 0 0 1 646 570V654A94 94 0 0 1 552 748H378Z"/>
    <!-- graduations sur la hampe -->
    <g fill="${C.bgBottom}" fill-opacity="0.35"><rect x="350" y="300" width="28" height="6"/><rect x="350" y="360" width="28" height="6"/></g>`);
    }
    const inner = 'M382 480H552A90 90 0 0 1 642 570V650A90 90 0 0 1 552 740H382Z';
    const top = 740 - 0.62 * 260;
    return iconFrame(id, `    <clipPath id="${id}-in"><path d="${inner}"/></clipPath>
    <rect x="382" y="${r(top)}" width="260" height="${r(740 - top)}" fill="${C.ok}" clip-path="url(#${id}-in)"/>
    <path fill-rule="evenodd" fill="#FFFFFF" d="M302 240A40 40 0 0 1 382 240V400H552A170 170 0 0 1 722 570V650A170 170 0 0 1 552 820H302ZM382 480H552A90 90 0 0 1 642 570V650A90 90 0 0 1 552 740H382Z"/>`, { halo: false });
  },
};

// ---------------------------------------------------------------- Piste C : Cadran

/** Secteur de couronne entre les rayons r et R, de l'angle a0 à a1 (radians, sens horaire à l'écran). */
function band(cx, cy, R, rr, a0, a1) {
  const P = (rad, a) => `${r(cx + rad * Math.cos(a))} ${r(cy + rad * Math.sin(a))}`;
  const large = a1 - a0 > Math.PI ? 1 : 0;
  return `M${P(R, a0)}A${R} ${R} 0 ${large} 1 ${P(R, a1)}L${P(rr, a1)}A${rr} ${rr} 0 ${large} 0 ${P(rr, a0)}Z`;
}
const PI = Math.PI;
const C_TRACK = band(9, 12, 7.5, 4.5, PI, 2 * PI);
const C_BAR = '<rect x="12.5" y="13" width="5" height="1.5" rx="0.75"/>';

const Cp = {
  id: 'c', dossier: 'piste-c-cadran', nom: 'Cadran', titre: 'C · Cadran',
  idee: 'Un cadran en demi-cercle qui se remplit de gauche à droite jusqu\'à une butée : le trait au bout de la course.',
  pour: 'La plus différente de l\'actuel : une forme qui se reconnaît de loin, et un remplissage qu\'on lit comme une aiguille.',
  contre: 'Rompt avec le tube vertical déjà appris, évoque le compteur de vitesse (« tableau de bord » que la DA évite). Dans la barre des menus, la butée à droite déséquilibre un peu le glyphe.',
  glyph(level) {
    const f = course(level, 1, 0.06);
    const fill = f > 0 ? `<path d="${band(9, 12, 7.5, 4.5, PI, PI + PI * f)}"/>` : '';
    return `<path d="${C_TRACK}" fill="none" stroke="currentColor" stroke-width="1"/>${fill}${C_BAR}`;
  },
  glyphVar: `<!-- Le remplissage suit --level par un tracé en pointillés sur l'arc médian (rayon 6, longueur 6 pi). -->
  <path d="${C_TRACK}" fill="none" stroke="currentColor" stroke-width="1"/>
  <path d="M3 12A6 6 0 0 1 15 12" fill="none" stroke="currentColor" stroke-width="3" pathLength="100" style="stroke-dasharray: calc(var(--level, 0.6) * 100) 100"/>
  ${C_BAR}`,
  symbol: () => `<path class="so" d="${C_TRACK}"/><path class="l" d="${band(9, 12, 7.5, 4.5, PI, PI + PI * 0.62)}"/><rect class="s" x="12.5" y="13" width="5" height="1.5" rx="0.75"/>`,
  icon(id, detail) {
    if (detail) {
      const cx = 512, cy = 640, R = 330, rr = 215, a1 = PI + PI * 0.62;
      const ticks = [0.25, 0.5, 0.75].map((t) => {
        const a = PI + PI * t, c = Math.cos(a), s = Math.sin(a);
        return `<line x1="${r(cx + (R + 22) * c)}" y1="${r(cy + (R + 22) * s)}" x2="${r(cx + (R + (t === 0.5 ? 58 : 44)) * c)}" y2="${r(cy + (R + (t === 0.5 ? 58 : 44)) * s)}"/>`;
      }).join('');
      const e = (rad) => `${r(cx + rad * Math.cos(a1))} ${r(cy + rad * Math.sin(a1))}`;
      return iconFrame(id, `    <defs><linearGradient id="${id}-arc" x1="182" y1="0" x2="640" y2="0" gradientUnits="userSpaceOnUse"><stop offset="0" stop-color="${C.liquidBottom}"/><stop offset="1" stop-color="${C.liquidTop}"/></linearGradient></defs>
    <g transform="translate(0 60)">
      <!-- piste de verre -->
      <path d="${band(cx, cy, R, rr, PI, 2 * PI)}" fill="#FFFFFF" fill-opacity="0.07" stroke="#FFFFFF" stroke-opacity="0.22" stroke-width="4"/>
      <!-- remplissage à 62 %, front clair -->
      <path d="${band(cx, cy, R, rr, PI, a1)}" fill="url(#${id}-arc)"/>
      <path d="M${e(rr + 4)}L${e(R - 4)}" stroke="${C.meniscus}" stroke-opacity="0.85" stroke-width="10"/>
      <!-- graduations 25, 50, 75 % -->
      <g stroke="#FFFFFF" stroke-opacity="0.45" stroke-width="8" stroke-linecap="round">${ticks}</g>
      <!-- la butée : le trait au bout de la course -->
      <rect x="700" y="662" width="170" height="40" rx="20" fill="${C.ok}" fill-opacity="0.45" filter="url(#${id}-glow)"/>
      <rect x="700" y="662" width="170" height="40" rx="20" fill="url(#${id}-ivory)"/>
    </g>`);
    }
    const cx = 512, cy = 670, R = 340, rr = 190;
    return iconFrame(id, `    <path d="${band(cx, cy, R, rr, PI, 2 * PI)}" fill="#FFFFFF" fill-opacity="0.2"/>
    <path d="${band(cx, cy, R, rr, PI, PI + PI * 0.62)}" fill="${C.ok}"/>
    <rect x="680" y="692" width="210" height="72" rx="36" fill="#FFFFFF"/>`, { halo: false });
  },
};
const PISTES = [A, Bp, Cp];

/** Glyphe gabarit autonome (barre des menus), niveau fixe. */
function glyphSVG(p, level, label = 'Brimline') {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="18" height="18" fill="currentColor" role="img" aria-label="${label}">
  <!-- Glyphe gabarit de la barre des menus, piste ${p.titre}, niveau ${Math.round(level * 100)} %. Noir et transparence. -->
  ${p.glyph(level, `${p.id}-g`)}
</svg>
`;
}

function glyphVarSVG(p) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="18" height="18" fill="currentColor" role="img" aria-label="Brimline">
  <!-- Glyphe paramétrable, piste ${p.titre} : à insérer en ligne, niveau par la variable CSS --level (0 à 1).
       En <img>, la variable ne passe pas : le niveau par défaut (0,6) s'affiche. -->
  ${p.glyphVar}
</svg>
`;
}

const SYMBOL_STYLE = `.s{fill:${C.textLight}}.l{fill:${C.okLight}}.so{fill:none;stroke:${C.textLight};stroke-width:1}@media (prefers-color-scheme: dark){.s{fill:${C.textDark}}.l{fill:${C.okDark}}.so{stroke:${C.textDark}}}`;

function symbolSVG(p) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="180" height="180" role="img" aria-label="Brimline">
  <!-- Symbole, piste ${p.titre} : structure en couleur du texte, liquide en sarcelle ; suit le thème clair ou sombre. -->
  <style>${SYMBOL_STYLE}</style>
  ${p.symbol()}
</svg>
`;
}

/** Logo horizontal : symbole et logotype. Le logotype est du texte en police système (voir README). */
function logoSVG(p) {
  const word = p.id === 'b' ? 'brimline' : 'Brimline';
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 132 24" width="528" height="96" role="img" aria-label="Brimline">
  <!-- Logo horizontal, piste ${p.titre}. Logotype en police système, semi-gras : à figer en tracés avec la police retenue au lot d'intégration. -->
  <style>${SYMBOL_STYLE}text{font:600 19px -apple-system,BlinkMacSystemFont,"SF Pro Display","Segoe UI",Roboto,"Helvetica Neue",Arial,sans-serif;letter-spacing:-0.2px}</style>
  <g transform="translate(0 2) scale(1.1111)">${p.symbol(`${p.id}-ls`)}</g>
  <text class="s" x="27" y="18.5">${word}</text>
</svg>
`;
}

/** Favicon : le glyphe en couleur sur une tuile graphite, lisible en 16 px. */
function faviconSVG(p) {
  return `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 18 18" width="32" height="32">
  <!-- Favicon, piste ${p.titre}. -->
  <rect width="18" height="18" rx="4" fill="#1B1E21"/>
  <g transform="translate(9 9) scale(0.84) translate(-9 -9)"><style>.s{fill:${C.textDark}}.l{fill:${C.okDark}}.so{fill:none;stroke:${C.textDark};stroke-width:1}</style>${p.symbol(`${p.id}-fs`)}</g>
</svg>
`;
}

module.exports = { PISTES, glyphSVG, glyphVarSVG, symbolSVG, logoSVG, faviconSVG, SYMBOL_STYLE, C };
