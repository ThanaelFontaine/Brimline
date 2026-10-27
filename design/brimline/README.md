# design/brimline/ : icône et logo de Brimline, trois pistes

Planche du renommage de Sightglass en Brimline (QUOTA-34, 27/10/2026). Rien ici n'est encore utilisé par l'app ni par le site : la piste retenue par Thanaël sera intégrée dans un lot à part, qui remplacera `design/icons/` et le glyphe.

Planche : `planche.html` (autonome, sans réseau, suit le thème du système). Captures : `captures/` (`pistes-*` pour la vue d'ensemble, `planche-*` pour la page entière, en clair et en sombre).

## Les pistes

| Piste | Idée | Dossier |
|---|---|---|
| A · Ras (recommandée) | Une cuve ouverte et, au-dessus de son bord, un trait libre : la limite. Le liquide monte vers le trait. | `piste-a-ras/` |
| B · Le b | Un « b » minuscule : la hampe est la règle de niveau, la panse est la cuve qui se remplit. | `piste-b-monogramme/` |
| C · Cadran | Un demi-cercle qui se remplit de gauche à droite jusqu'à une butée, le trait au bout de la course. | `piste-c-cadran/` |

Recommandation : A. Elle dit le nom à la lettre (un bord, un trait) et garde le niveau vertical déjà appris dans la barre des menus, sans confusion avec la batterie de macOS ; c'est la plus nette à 16 px.

## Fichiers de chaque piste

| Fichier | Rôle |
|---|---|
| `app-icon.svg` | Icône d'app, grille macOS 1024 (carré arrondi de 824 à 100 du bord, rayon 185,4, ombre), pour 64 px et plus. |
| `app-icon-small.svg` | Version simplifiée pour 16 et 32 px : pas de reflet, de ménisque ni de graduations, traits plus épais. |
| `menubar-template.svg` | Glyphe gabarit de la barre des menus, 18 pt, noir et transparence, niveau 60 %. |
| `glyph-level.svg` | Le même glyphe, niveau par la variable CSS `--level` (0 à 1), pour le site. |
| `symbole.svg` | Symbole en couleur : structure en couleur du texte, liquide en sarcelle (`gaugeOk`), clair ou sombre selon le thème. |
| `logo.svg` | Logo horizontal : symbole et logotype. |
| `favicon.svg` | Le symbole sur une tuile graphite, lisible en 16 px. |
| `png/` | Rendus : icône 1024, 512, 64 (dessin complet), 32 et 16 (dessin simplifié), favicon 32 et 16. |

Couleurs : uniquement les jetons de `../tokens.json`, inchangés. Le glyphe suit les règles de `../DA.md` : niveau de la limite la plus proche de son plafond, au moins un trait de liquide dès que le niveau dépasse 0, course pleine réservée à 100 %, opacité 0,45 quand les données sont expirées.

Logotype : texte en police système, semi-gras, comme l'en-tête actuel du site. Il n'est pas vectorisé, car la licence de SF Pro réserve la police aux interfaces des plateformes Apple ; si un logotype figé est voulu (image de partage, page GitHub), le lot d'intégration choisit une police sous licence libre et vectorise le mot.

## Régénérer

```sh
node design/brimline/src/build.cjs
NODE_PATH=<dossier node_modules qui contient playwright> node design/brimline/src/render.cjs
```

`src/pistes.cjs` est la source unique de la géométrie ; `build.cjs` écrit les SVG et la planche, `render.cjs` les PNG et les captures (Chromium sans tête). Ne pas retoucher les SVG ni la planche à la main.
