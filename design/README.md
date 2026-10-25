# design/ : jetons, icônes, planche

Vue d'ensemble de la direction artistique : `DA.md`. Planche à ouvrir dans un navigateur (autonome, sans réseau, clair et sombre) : `planche.html`.

## Source unique

| Fichier | Rôle |
|---|---|
| `tokens.json` | Source unique des valeurs : couleurs clair et sombre, seuils de jauge, typographie, rayons, espacements. |
| `tokens.css` | Les mêmes valeurs en variables `--sg-*`, pour le site. |
| `icons/app-icon.svg` | Icône de l'app, source vectorielle. |
| `icons/AppIcon.icns` | Icône de l'app pour macOS (`iconutil` depuis `AppIcon.iconset/`, pas de catalogue Xcode). |
| `icons/menubar-template.svg` et `.pdf` | Glyphe gabarit de la barre des menus : noir et transparence, aucune couleur, niveau 60 %. `glyph-level.svg` en est la version à niveau variable. |
| `planche.html` | Planche : icône d'app, glyphe à 0, 50, 80 et 100 %, couleurs, typographie, jauges. |

## Consommer les jetons

- **App (lot 4b)** : `Sources/SightglassUI/SightglassTheme.swift` recopie les couleurs de `tokens.json` (`SGTheme.dynamic(clair, sombre)`). Le texte et les fonds restent ceux du système. Une valeur change : on la change d'abord dans `tokens.json`, puis dans `SightglassTheme.swift`. L'icône est lue dans `icons/AppIcon.icns` par `scripts/build_app.sh`.
- **Site (lot 5)** : copier `tokens.css`, `icons/app-icon.svg` et le glyphe tels quels (même octets : la QA compare les fichiers). Ne jamais retoucher une valeur côté site.

## Contrôles

`python3 -m unittest discover -s tests` lance `tests/test_design_tokens.py` : contraste calculé depuis `tokens.json` (au moins 4,5:1 pour chaque texte, accent et couleur de jauge sur le fond et la surface, en clair et en sombre), deux thèmes complets, planche et CSS sans couleur hors jetons, glyphe gabarit sans couleur, planche sans réseau.

## Régénérer les images

`design/src/render-icons.swift` produit les PNG de l'icône (`AppIcon.iconset/`) et l'aperçu `apercu.png` ; `iconutil -c icns AppIcon.iconset -o icons/AppIcon.icns` assemble l'icône.
