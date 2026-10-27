# Brimline : direction artistique

Version 1, 25/10/2026. Vue d'ensemble : `apercu.png`.

## Intention

Le *brim* est le bord jusqu'où monte une cuve ; la *line* est la limite tracée au-dessus. Brimline doit se lire comme un niveau qu'on regarde monter vers ce bord : d'un regard, sans interprétation, sans mentir. C'est un instrument de précision calme, pas un tableau de bord. Peu de couleur, beaucoup de gris honnêtes, un seul liquide (un bleu sarcelle) qui ne vire à l'ambre puis au rouge que quand il le faut.

Trois règles fondent tout le reste :

1. **Le chiffre d'abord.** Chaque jauge a son pourcentage écrit en texte. La couleur confirme, elle ne porte jamais seule l'information.
2. **Le liquide, c'est ce qui est consommé.** La jauge et le glyphe montent vers la limite (la bride du haut, le bout de la piste). Le vide au-dessus, c'est ce qui reste. Le pourcentage affiché est celui de l'API (part utilisée), pour qu'on puisse le comparer aux chiffres de Claude.
3. **Natif avant tout.** L'app emprunte tout au système (SF Pro, matériaux, couleurs `.primary` et `.secondary`, boutons sans cadre). Brimline n'ajoute que l'accent et les couleurs de jauge.

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

## Le glyphe de la barre des menus

Fichiers : `BrimlineGlyph.swift` (app), `icons/menubar-template.svg` et `glyph-level.svg` (site).

- Image **gabarit** 18 x 18 pt, noir et transparence, `isTemplate = true` : macOS la teinte (clair, sombre, barre teintée, survol). Jamais de couleur dans la barre des menus.
- Dessin : deux brides horizontales (12 pt de large) et deux parois verticales autour d'une cavité de 6 pt. Le liquide (4 pt de large) monte de la bride du bas vers celle du haut, qui figure la limite.
- Netteté : géométrie au pixel près en 1x (traits de 1 pt) et en 2x (traits de 1,5 pt). Contrôlé par rendu : aucune demi-teinte en 1x, seulement les coins arrondis des brides en 2x.
- Niveau : celui de la limite **la plus proche de son plafond** parmi les comptes affichés. Au moins 1 pt de liquide dès que le niveau dépasse 0. La course pleine est réservée à 100 %, pour que 99 % ne se confonde pas avec la limite.
- Pourcentage à côté (réglage) : texte système de la barre des menus, chiffres à chasse fixe, même valeur que le glyphe. Le glyphe n'a pas de couleur : à 90 % et plus, seuls le niveau et le chiffre parlent, c'est voulu.
- Données expirées ou indisponibles : glyphe atténué (opacité 0,45, `dimmed: true`), avec la dernière valeur connue ou tube vide si aucune.
- Aucun compte : tube vide, opacité pleine.
- Libellé VoiceOver : « Brimline, 72 % ».

Usage :

```swift
statusLabel = Image(nsImage: BrimlineGlyph.image(level: 0.72))
BrimlineGlyph.image(level: last, dimmed: true)   // expiré ou indisponible
```

## L'icône de l'app

`icons/app-icon.svg` (source vectorielle), `AppIcon.iconset/` (10 PNG aux noms d'`iconutil`), `icons/AppIcon.icns`.

- Grille macOS : carré arrondi de 824 px dans 1024, à 100 px du bord, rayon 185,4, ombre portée douce.
- Fond graphite (dégradé `#2C333A` vers `#111417`), halo sarcelle très discret.
- Au centre, le voyant :
  - deux brides métalliques à boulons ;
  - un tube de verre avec reflet ;
  - des graduations à 25, 50 et 75 % ;
  - le liquide sarcelle à 62 % avec son ménisque.
- En 16 et 32 px, le dessin se simplifie : pas de boulons, de reflet ni de graduations ; parois plus épaisses.

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
| `BrimlineTheme.swift` | couleurs dynamiques, seuils, mesures, vue `SGGauge` (vérifiés par `swiftc -typecheck`, macOS 14, Swift 6) |
| `src/main.swift` | générateur des PNG : `swiftc -O -o src/render BrimlineGlyph.swift src/main.swift && src/render .` (binaire à ne pas versionner) |
