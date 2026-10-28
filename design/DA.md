# Brimline : direction artistique

Version 1, 25/10/2026, amendée le 27/10/2026 (lot 0.3.0 : jauge par compte dans la barre des menus, couleurs des comptes). Vue d'ensemble : `apercu.png`.

## Intention

Le *brim* est le bord jusqu'où monte une cuve ; la *line* est la limite tracée au-dessus. Brimline doit se lire comme un niveau qu'on regarde monter vers ce bord : d'un regard, sans interprétation, sans mentir. C'est un instrument de précision calme, pas un tableau de bord. Peu de couleur, beaucoup de gris honnêtes, un seul liquide (un bleu sarcelle) qui ne vire à l'ambre puis au rouge que quand il le faut.

Trois règles fondent tout le reste :

1. **Le chiffre d'abord.** Chaque jauge a son pourcentage écrit en texte. La couleur confirme, elle ne porte jamais seule l'information.
2. **Le liquide, c'est ce qui est consommé.** La jauge et le glyphe montent vers la limite (le bord de la cuve et le trait au-dessus, le bout de la piste). Le vide au-dessus, c'est ce qui reste. Le pourcentage affiché est celui de l'API (part utilisée), pour qu'on puisse le comparer aux chiffres de Claude.
3. **Natif avant tout.** L'app emprunte tout au système (SF Pro, matériaux, couleurs `.primary` et `.secondary`, boutons sans cadre). Brimline n'ajoute que l'accent, les couleurs de jauge et les couleurs des comptes.

## Couleurs

Valeurs sRGB. Contrastes WCAG 2.2 calculés (formule de luminance relative), AA exigé : 4,5:1 pour le texte, 3:1 pour les éléments graphiques. Toutes les couleurs ci-dessous passent aussi 4,5:1 sur le fond et la surface, donc elles restent utilisables en texte.

### Clair

| Jeton | Valeur | Rôle | Contraste fond / surface |
|---|---|---|---|
| `bg` | `#F5F6F7` | fond de page | |
| `surface` | `#FFFFFF` | cartes, panneaux | |
| `text` | `#15191D` | texte principal | 16,3 / 17,7 |
| `text2` | `#56606A` | texte secondaire | 5,9 / 6,4 |
| `border` | `#D3D8DD` | filets, bord de piste, repères | décoratif |
| `track` | `#E7EAED` | piste vide de la jauge | décoratif |
| `accent` | `#0B6E7A` | liens, action principale | 5,5 / 6,0 |
| `gaugeOk` | `#127A82` | marge, moins de 70 % | 4,7 / 5,1 (piste 4,2) |
| `gaugeWarn` | `#9A5800` | attention, de 70 à moins de 90 % | 5,2 / 5,6 (piste 4,6) |
| `gaugeCrit` | `#C0302B` | critique, 90 % et plus | 5,3 / 5,7 (piste 4,7) |
| `gaugeMuted` | `#56606A` à 55 % | expiré | |

### Sombre

| Jeton | Valeur | Rôle | Contraste fond / surface |
|---|---|---|---|
| `bg` | `#111315` | fond de page | |
| `surface` | `#1B1E21` | cartes, panneaux | |
| `text` | `#ECEFF2` | texte principal | 16,1 / 14,5 |
| `text2` | `#9BA5AF` | texte secondaire | 7,4 / 6,7 |
| `border` | `#30353A` | filets, bord de piste, repères | décoratif |
| `track` | `#2B3035` | piste vide de la jauge | décoratif |
| `accent` | `#5CC8D0` | liens, action principale | 9,4 / 8,5 |
| `gaugeOk` | `#3BBDC2` | marge | 8,2 / 7,4 (piste 5,9) |
| `gaugeWarn` | `#EFA63A` | attention | 9,0 / 8,1 (piste 6,5) |
| `gaugeCrit` | `#FF6F64` | critique | 6,8 / 6,2 (piste 4,9) |
| `gaugeMuted` | `#9BA5AF` à 55 % | expiré | |

Dans l'app, `BrimlineTheme.swift` fournit ces couleurs en `Color` dynamiques (clair et sombre suivent l'apparence du Mac). Le texte et les fonds y restent ceux du système. Sur le site, `tokens.css` les expose en variables `--sg-*`, le sombre par `prefers-color-scheme`.

## Typographie

**App** : uniquement la police système (SF Pro), tailles de macOS.

| Usage | Style |
|---|---|
| En-tête « Brimline » | 13 pt, semi-gras |
| Adresse du compte | 13 pt, semi-gras, coupure au milieu (`.truncationMode(.middle)`) si trop longue, adresse complète en infobulle |
| Organisation, offre | 11 pt, secondaire |
| Libellé de limite (« Session 5 h », « Semaine · Fable ») | 12 pt |
| Pourcentage | 12 pt, semi-gras, chiffres à chasse fixe (`.monospacedDigit()`), aligné à droite |
| « repart dans 2 h 10 (14:30) », âge, messages d'état | 11 pt, secondaire |
| Pied (« Actualisé à 12:20 ») | 11 pt, secondaire ; boutons 12 pt sans cadre, « Actualiser » en accent |

**Site** : la pile système, sans police web : même voix que l'app, et aucune requête vers un tiers (cohérent avec « rien ne sort du Mac »).

- Texte : `-apple-system, BlinkMacSystemFont, "SF Pro Text", "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif`
- Code et commandes : `ui-monospace, "SF Mono", SFMono-Regular, Menlo, Consolas, monospace`
- Échelle : 13, 15, 17 (corps), 22, 32 px, titre d'accueil `clamp(40px, 6vw, 64px)` semi-gras, interlignage 1,55 (1,15 pour les titres), mesure de 680 px au plus.
- Chiffres des jauges en `font-variant-numeric: tabular-nums` (classe `.sg-num`).
- Typographie française : espace avant « % » et « : » en français (« 72 % »), pas en anglais (« 72% »).

## La jauge

**Forme.** Un tube horizontal : capsule (rayon égal à la moitié de la hauteur). Hauteur 6 pt dans l'app, 8 px sur le site, 10 px dans les visuels d'accueil. Pleine largeur de la carte.

**Composition**, de bas en haut :

1. piste `track`, capsule ;
2. deux repères de seuil de 1 pt de large, toute la hauteur, couleur `border`, à 70 % et 90 % de la largeur (ils annoncent où la couleur va changer) ;
3. le liquide, capsule partant de la gauche, couleur selon le seuil ;
4. un filet de 0,5 pt en `border` autour de la piste.

**Seuils** (sur la part consommée) : moins de 70 % : `gaugeOk` ; de 70 à moins de 90 % : `gaugeWarn` ; 90 % et plus : `gaugeCrit`.

**Valeurs limites.**

- **0 %** : piste vide, aucun liquide (pas de point factice) ; texte « 0 % ».
- **De 0 à 1 %** : le liquide fait au moins la hauteur de la jauge (un point rond), pour qu'un usage réel ne soit jamais invisible.
- **100 %** : piste pleine en `gaugeCrit` ; texte « 100 % » et, en dessous, « Limite atteinte · repart dans … ».
- Au-delà de 100 % (si l'API le renvoie) : jauge pleine, texte avec la vraie valeur.
- Arrondi du texte à l'entier le plus proche. La jauge suit la valeur exacte.

**États.**

| État | Jauge | Texte |
|---|---|---|
| À jour | normale | « 34 % », « repart dans 2 h 10 (14:30) » |
| Ancien (données de plus de 2 intervalles) | normale | pourcentage, plus « il y a 25 min » en secondaire |
| Expiré | liquide en `gaugeMuted` (gris à 55 %) à la dernière valeur connue | pourcentage, « valeur d'il y a 3 h », heure de remise à zéro si encore future, puis le message « Session expirée : ouvrez Claude Code avec ce compte pour la reconnecter. » |
| Indisponible (429, 5xx, réseau) | piste sans remplissage, contour en pointillés 2/2 | « Indisponible » à la place du pourcentage, raison courte en secondaire, « nouvel essai à 12:35 » |
| À reconnecter (401) | comme expiré | « À reconnecter » et le même message |
| Pas de limite hebdomadaire globale | pas de jauge | la phrase en secondaire, à la place de la ligne « Semaine » |

**Accessibilité.** Chaque jauge est un seul élément VoiceOver : libellé = nom de la limite, valeur = « 72 % » (plus « expiré » ou « indisponible »). Composant prêt à l'emploi : `SGGauge` dans `BrimlineTheme.swift` (chaînes à passer par les ressources localisées de l'app). Sur le site : `role="meter"` avec `aria-valuenow`, classe `.sg-gauge` de `tokens.css`.

## Plusieurs fournisseurs

Planche : `planche-fournisseurs.html` (QUOTA-35, lot D), captures dans `captures-fournisseurs/`. Variante A (regroupé par fournisseur) retenue le 27/10/2026 (THA-1313, tranchée par la session maître), construite au lot P1b (THA-1432).

- **Le fournisseur s'écrit** : son nom en texte, toujours. Aucun logo de tiers.
- **Pastilles** : depuis le lot 0.3.0, la pastille ronde de 8 pt est celle du **compte**, avant le titre de sa carte, à la couleur du compte (section « Couleurs des comptes »). L'en-tête de groupe du fournisseur garde son nom écrit, sans pastille, pour qu'une couleur ne veuille dire qu'une chose. Une carte à phrase seule (Gemini) prend le nom du fournisseur pour titre. Couleurs propres à l'app, pas celles des marques ; aucune ne reprend l'accent ou une couleur de jauge.
- **Couleur d'un fournisseur** : celle de son premier compte par défaut.

| Jeton | Clair | Sombre |
|---|---|---|
| `providerClaude` (violet) | `#7445D6` | `#B48CFF` |
| `providerChatgpt` (bleu) | `#1C68C9` | `#62AEF5` |
| `providerGemini` (magenta) | `#B03A86` | `#F08BCB` |
| `providerGrok` (olive) | `#5E7A12` | `#B3CC5C` |
| `providerCursor` (encre) | `#15191D` | `#ECEFF2` |

Toutes passent 4,5:1 sur le fond et la surface.

- **Sous-limite** (un modèle, un pool Auto ou API) : ligne compacte, texte de 11 pt, jauge de 4 pt, remise à zéro écrite seulement si elle diffère de la ligne au-dessus.
- **Remise à zéro au-delà de 6 jours** : avec la date (« repart dans 12 j (dim. 8 nov.) »).
- **Sans limite lisible** (`not_readable`) : jamais de jauge. La première phrase tient en deux lignes, la suite se déplie par « En savoir plus ».
- **Format changé** (`format_changed`) : derniers chiffres en gris avec leur âge, et la phrase.
- **Ne pas lire** : derniers chiffres en gris, « Lecture coupée dans les Réglages ».

## Couleurs des comptes

Planche : `planche-comptes.html` (lot D de QUOTA-70, 71 et 72), captures dans `captures-comptes/`. Jetons : `tokens.json` (`accountPalette`) et `tokens.css` (`--sg-account-*`).

Chaque compte a une couleur, choisie dans Réglages, Comptes, et gardée dans `settings.json` sous la clé du compte (`Account.id`). Elle sert à sa part dans la jauge de la barre des menus et à sa pastille dans le panneau. Les jauges des limites du panneau gardent leurs couleurs de seuil : là, la couleur confirme un niveau, pas un compte.

**La palette** : dix couleurs, dans l'ordre des emplacements 0 à 9.

| # | Nom (FR, EN) | Jeton | Clair | Sombre |
|---|---|---|---|---|
| 0 | Violet, Violet | `providerClaude` | `#7445D6` | `#B48CFF` |
| 1 | Bleu, Blue | `providerChatgpt` | `#1C68C9` | `#62AEF5` |
| 2 | Magenta, Magenta | `providerGemini` | `#B03A86` | `#F08BCB` |
| 3 | Olive, Olive | `providerGrok` | `#5E7A12` | `#B3CC5C` |
| 4 | Encre, Ink | `providerCursor` | `#15191D` | `#ECEFF2` |
| 5 | Sapin, Pine | `accountPine` | `#1B6B4C` | `#5CCB98` |
| 6 | Or, Gold | `accountGold` | `#8C7400` | `#F4D63A` |
| 7 | Marine, Navy | `accountNavy` | `#1D3270` | `#B9CAFE` |
| 8 | Cacao, Cocoa | `accountCocoa` | `#703821` | `#CA9678` |
| 9 | Lilas, Lilac | `accountLilac` | `#7A6A96` | `#E9C6F6` |

Règles, vérifiées par `tests/test_design_tokens.py` : au moins 3:1 sur la piste, le fond, la surface et la barre des menus (gris simulés de la planche), en clair et en sombre (le plus faible : or clair, 3,34:1 sur la barre) ; écart CIEDE2000 d'au moins 15 entre deux couleurs de la palette, dans chaque apparence (le plus petit : 15,2, bleu et marine en sombre) ; au moins 10 avec l'accent, les couleurs de seuil et le gris expiré.

**Couleur par défaut.** Le premier compte d'un fournisseur prend la couleur de son fournisseur ; les suivants, la première couleur libre dans l'ordre sapin, or, marine, cacao, lilas, puis parmi les couleurs des fournisseurs qui n'ont aucun compte. Une fois donnée, elle est gardée : elle ne change plus quand un autre compte apparaît. « Revenir au défaut » redonne la couleur que cette règle donnerait à cet instant.

**Couleur libre.** Le sélecteur de couleur du système, sans opacité, gardé en hex sRGB ; une seule valeur, servie en clair et en sombre. Avertissement (jamais un refus) sous 3:1 sur la piste dans l'une des deux apparences, avec le ratio écrit.

**Couleurs trop proches.** Avertissement sur les deux comptes quand deux comptes visibles ont un écart CIEDE2000 sous 10 dans l'une des deux apparences.

**Réglages.** Sous chaque compte, une ligne « Couleur » : les dix pastilles de 18 pt (6 pt d'écart, la choisie entourée d'un anneau de 1,5 pt à la couleur du texte), « Autre couleur… » (pastille en pointillés marquée « + », remplie de la couleur libre quand elle est choisie), puis « Revenir au défaut » (grisé, avec « Couleur par défaut », quand rien n'a changé). Avertissements sous la ligne : triangle en `gaugeWarn`, texte secondaire de 11 pt. VoiceOver : un groupe à choix unique « Couleur de <compte> », chaque option son nom.

## Espacements et mesures

Grille de 4 : 2, 4, 8, 12, 16, 24, 32, 48, 64.

**App (fenêtre de la barre des menus) :**

- largeur 340 pt ;
- marges intérieures 16 pt ;
- cartes de compte à 8 pt du bord, 8 pt entre elles, rayon 10, padding 12 ;
- 18 pt entre adresse et organisation ;
- une ligne de limite fait 48 pt : libellé et pourcentage, 8 pt, jauge, 4 pt, ligne de remise à zéro ;
- pied séparé par un filet, boutons espacés de 14 pt.

**Rayons :**

- contrôles : 6 ;
- cartes : 10 ;
- fenêtres : 12 ;
- blocs de page : 16 ;
- jauge : capsule.

**Site :** largeur utile 1080 px, texte 680 px, gouttière 16 px sur téléphone, sections espacées de 64 px.

## La barre des menus

Planche : `planche-comptes.html`, sections 1 à 4. Fichiers : `BrimlineGlyph.swift` et `MenuBarGaugeImage.swift` (app), `icons/menubar-template.svg` et `.pdf`, `glyph-level.svg` (site).

**Amendement du 27/10/2026 (QUOTA-70).** La barre des menus montre désormais une image **en couleurs** dès qu'un compte a un chiffre : la règle « jamais de couleur dans la barre des menus » est levée pour les parts des comptes et le repère d'alerte. C'est un écart assumé au conseil d'Apple (image modèle en noir et transparence) : Brimline fait elle-même ce que le système faisait (couleurs selon l'apparence réelle de la barre, contour à la couleur du texte de la barre). Le glyphe modèle reste quand aucun compte n'a de chiffre.

### L'élément : « Ras couché »

Le glyphe se couche et sa cuve devient la jauge : une cuve ouverte, fermée à gauche, dont le liquide est fait des parts des comptes, et à droite, sans la toucher, le trait de la limite. La marque reste la même (une cuve ouverte, un trait libre qui ne la touche jamais), lue à l'horizontale.

- **Image** de 18 pt de haut, largeur = course + 10 pt (50 à 74 pt), centrée dans la barre de 24 pt. Non modèle (`isTemplate = false`).
- **Cuve** : 12 pt de haut (y 3 à 15), rayon extérieur 2,5 à gauche, trait de 1,5 pt en 2x et 1 pt en 1x, en `NSColor.labelColor` résolu pour l'apparence du bouton.
- **Liquide** : 6 pt de haut (y 6 à 12), à 1,5 pt (2x) ou 2 pt (1x) des parois ; la cuve dépasse la course du même écart à droite.
- **Course** : 40 pt jusqu'à 4 comptes, 4 pt de plus par compte au-delà, 64 pt à 10 comptes et plus.
- **Trait de la limite** : 16 pt de haut (y 1 à 17), 1,5 pt (2x) ou 1 pt (1x) de large, à 2 pt du bout de la cuve.
- **Parts** : chaque compte compté a une part de p / N de la course (p : sa limite la plus serrée maintenant ; N : les comptes comptés), tassées à gauche dans l'ordre du panneau, jamais triées par taille. Le total est la moyenne, jamais plus de 100 %. Arrondi en pixels à la plus grande part de reste ; une part non nulle fait au moins 1 pixel, pris sur le vide. Part d'une dernière valeur connue (expiré, indisponible, à reconnecter) : couleur du compte à l'opacité 0,45.
- **Alerte** : dès qu'un compte compté atteint 90 %, le trait devient un « ! » en `gaugeCrit` (barre de 2,5 x 10,5 pt et point de 2,5 pt en 2x ; 2 x 10 et 2 x 2 en 1x). Forme et couleur : jamais la couleur seule. La place du « ! » est toujours réservée, la largeur ne bouge pas. De 70 à 90 %, rien dans la barre.
- **Pourcentage à côté** (réglage) : texte système de la barre, chiffres à chasse fixe, 4 pt après l'image ; c'est celui du compte le plus chargé, jamais la moyenne.
- **Comptes sans chiffre** (phrase seule, jamais lu, illimité) : hors de N et hors de la jauge ; VoiceOver et le panneau les citent.
- **Aucun compte compté** : le glyphe vertical ci-dessous, image modèle, cuve vide.
- **Infobulle** : « Moyenne 45 % sur 5 comptes · Agence à 94 % ».
- **VoiceOver** : un seul élément, l'alerte d'abord : « Alerte : Agence à 94 %. Brimline, utilisé 45 % en moyenne sur 5 comptes : Principal 58 %, …, Secours 9 %, valeur ancienne, ChatGPT Plus 41 %. Gemini : pas de chiffre. »

Variantes montrées et écartées (planche, section 4) : « une case par compte » (le total ne se lit plus, 5 pt par case à dix comptes), « glyphe à côté » (deux objets, près de 80 pt), verticale (8 pt de course).

### Le glyphe vertical (aucun compte compté, en-tête du panneau, site)

- Image **gabarit** 18 x 18 pt, noir et transparence, `isTemplate = true` : macOS la teinte (clair, sombre, barre teintée, survol).
- Dessin (piste A · Ras, choisie le 27/10/2026) : une cuve ouverte en U (10 pt de large, bord à 5 pt du haut, coins arrondis) et, au-dessus de son bord, un trait libre de 14 pt : la limite. Le liquide (4 pt de large) monte du fond de la cuve vers son bord (8 pt de course). Le trait ne touche jamais la cuve : c'est lui qui fait la marque, à protéger.
- Netteté : géométrie au pixel près en 1x (traits de 1 pt) et en 2x (traits de 1,5 pt, la géométrie de `icons/menubar-template.svg`). Les tests de rendu (`BrimlineGlyphTests`) lisent les pixels : le trait, les parois et le fond sont pleins à tous les niveaux, rien entre le trait et le bord.
- Niveau (en-tête du panneau, site) : celui de la limite **la plus proche de son plafond**. Au moins 1 pt de liquide dès que le niveau dépasse 0. La course pleine est réservée à 100 %.
- Données expirées ou indisponibles : glyphe atténué (opacité 0,45, `dimmed: true`).

Usage :

```swift
statusLabel = Image(nsImage: BrimlineGlyph.image(level: nil))   // aucun compte compté
BrimlineGlyph.image(level: last, dimmed: true)                  // en-tête, expiré ou indisponible
```

## L'icône de l'app

`icons/app-icon.svg` (source vectorielle), `AppIcon.iconset/` (10 PNG aux noms d'`iconutil`), `icons/AppIcon.icns`.

- Grille macOS : carré arrondi de 824 px dans 1024, à 100 px du bord, rayon 185,4, ombre portée douce.
- Fond graphite (dégradé `#2C333A` vers `#111417`), halo sarcelle très discret.
- Au centre, la cuve :
  - une cuve de verre ouverte, aux parois translucides, avec un reflet ;
  - le liquide sarcelle à 62 %, avec son ménisque ;
  - au-dessus du bord, le trait : la limite, en ivoire, avec une lueur sarcelle discrète. Il ne touche jamais la cuve.
- En 16 et 32 px (`icons/app-icon-small.svg`), le dessin se simplifie : pas de halo, de reflet, de ménisque ni de lueur ; parois et trait plus épais, liquide d'un aplat.

## Site

- `favicon.svg` : icône simplifiée, lisible en 16 px.
- `favicon.ico` : 16 et 32 px.
- `favicon-32.png`, `favicon-16.png`.
- `apple-touch-icon.png` : 180 px, plein cadre et opaque, iOS arrondit lui-même.
- `og.png` : 1200 x 630, fond sombre. Il porte l'icône, le nom et la promesse « See how much of every AI subscription you have left. », avec trois jauges d'exemple.
- Le site reprend la jauge (`.sg-gauge`) comme motif principal : une fausse fenêtre de barre des menus en tête de page vaut mieux qu'une illustration.

## Fichiers

| Fichier | Contenu |
|---|---|
| `tokens.json`, `tokens.css` | jetons (couleurs avec contrastes, rayons, espacements, polices) |
| `BrimlineGlyph.swift` | glyphe gabarit, `NSImage` pour un niveau donné |
| `MenuBarGaugeImage.swift` | élément « Ras couché » de la barre des menus, à partir du modèle de la jauge (lot L4) |
| `planche-comptes.html`, `captures-comptes/`, `src/render-comptes.cjs` | planche de la jauge par compte, du panneau multi-comptes et des couleurs, ses captures et leur générateur |
| `BrimlineTheme.swift` | couleurs dynamiques, seuils, mesures, vue `SGGauge` (vérifiés par `swiftc -typecheck`, macOS 14, Swift 6) |
| `src/render-icons.swift` | générateur des PNG : à compiler comme `main.swift` avec `BrimlineGlyph.swift` et les sources de `BrimlineCore` dans un seul module (sans la ligne `import BrimlineCore`), puis `render <dossier da>` (binaire à ne pas versionner) |
