# design/ : jetons, icônes, planche

Vue d'ensemble de la direction artistique : `DA.md`. Planche à ouvrir dans un navigateur (autonome, sans réseau, clair et sombre) : `planche.html`.

## Source unique

| Fichier | Rôle |
|---|---|
| `tokens.json` | Source unique des valeurs : couleurs clair et sombre, seuils de jauge, typographie, rayons, espacements. |
| `tokens.css` | Les mêmes valeurs en variables `--sg-*`, pour le site. |
| `icons/app-icon.svg` | Icône de l'app (piste A · Ras), source vectorielle, pour 64 px et plus. |
| `icons/app-icon-small.svg` | Dessin simplifié pour 16 et 32 px (pas de halo, de reflet ni de lueur). |
| `icons/AppIcon.icns` | Icône de l'app pour macOS (`iconutil` depuis `AppIcon.iconset/`, pas de catalogue Xcode). |
| `icons/menubar-template.svg` et `.pdf` | Glyphe gabarit de la barre des menus : noir et transparence, aucune couleur, niveau 60 %. `glyph-level.svg` en est la version à niveau variable. |
| `planche.html` | Planche : icône d'app, glyphe à 0, 25, 72, 95 % et expiré, couleurs, typographie, jauges. |
| `planche-barre.html` | Planche de QUOTA-73, lot L6 : onglet de Réglages « Barre des menus » (« Ranger la barre des menus ») qui explique comment retirer les icônes de Claude, ChatGPT et Cursor, avec ses états (deux apps, aucune, erreurs d'ouverture), le geste ⌘ glisser et les textes EN et FR. Langue et thème : `#fr-light`, `#fr-dark`, `#en-light`, `#en-dark`. Captures dans `captures-barre/`, régénérées par `NODE_PATH=<node_modules avec playwright> node design/src/render-barre.cjs` ; contrôles dans `tests/test_design_barre.py`. |
| `planche-fournisseurs.html` | Planche de QUOTA-35 : plusieurs fournisseurs côte à côte (panneau en deux variantes, fenêtres, états, Réglages, pastilles, textes EN et FR). Langue et thème par l'adresse : `#fr-light`, `#fr-dark`, `#en-light`, `#en-dark`. Captures dans `captures-fournisseurs/`, régénérées par `NODE_PATH=<node_modules avec playwright> node design/src/render-fournisseurs.cjs`. |
| `planche-comptes.html` | Planche du lot 0.3.0 (QUOTA-70, 71, 72) : élément « Ras couché » de la barre des menus avec une part par compte (1, 3, 10 comptes, alerte, cas limites, 1x et 2x, barres claire, sombre, teintée, sélectionnée), variantes « une case par compte », « glyphe à côté » et verticale, panneau multi-comptes, réglage des couleurs, palette de dix. Langue et thème : `#fr-light`, `#fr-dark`, `#en-light`, `#en-dark`. Captures dans `captures-comptes/`, régénérées par `NODE_PATH=<node_modules avec playwright> node design/src/render-comptes.cjs`. |

## Consommer les jetons

- **App (lot 4b)** : `Sources/BrimlineUI/BrimlineTheme.swift` recopie les couleurs de `tokens.json` (`SGTheme.dynamic(clair, sombre)`). Le texte et les fonds restent ceux du système. Une valeur change : on la change d'abord dans `tokens.json`, puis dans `BrimlineTheme.swift`. L'icône est lue dans `icons/AppIcon.icns` par `scripts/build_app.sh`.
- **Site (lot 5)** : copier `tokens.css`, `icons/app-icon.svg` et le glyphe tels quels (même octets : la QA compare les fichiers). Ne jamais retoucher une valeur côté site.

## Contrôles

`python3 -m unittest discover -s tests` lance `tests/test_design_tokens.py` : contraste calculé depuis `tokens.json` (au moins 4,5:1 pour chaque texte, accent et couleur de jauge sur le fond et la surface, en clair et en sombre), palette des comptes (dix couleurs, au moins 3:1 sur la piste, le fond, la surface et la barre simulée, écart CIEDE2000 d'au moins 15 entre elles et de 10 avec l'accent et les seuils, CIEDE2000 vérifié sur les valeurs de référence de Sharma), mesures de l'élément de barre (80 pt au plus), deux thèmes complets, planche et CSS sans couleur hors jetons, glyphe gabarit sans couleur et de géométrie « Ras » (gabarit et `glyph-level.svg`), icône 16 et 32 px sans détail, planche sans réseau. `swift test` (`BrimlineGlyphTests`) lit les pixels du glyphe : trait, parois et fond à tous les niveaux, 1 % visible, 99 % sous le bord.

## Régénérer les images

`design/src/render-icons.swift` produit les PNG de l'icône (`AppIcon.iconset/`), le gabarit `menubar-template.pdf` et l'aperçu `apercu.png` ; `iconutil -c icns AppIcon.iconset -o icons/AppIcon.icns` assemble l'icône. Les captures du README (`docs/images/`) viennent de `swift run brimline-snapshots`.

Le glyphe SVG et le dessin de `BrimlineGlyph.swift` ont les mêmes coordonnées : une modification se fait dans les deux, puis les tests de ce dossier et `BrimlineGlyphTests` la vérifient.

`design/brimline/` (sur la branche du Designer, THA-1274) garde la planche des trois pistes du premier tour et son générateur ; seule la piste A est reprise ici.
