# design/brimline/v2/ : icône et logo de Brimline, deuxième tour

Planche du deuxième tour (QUOTA-34, THA-1412, 27/10/2026). Le premier tour (`../`, pistes Ras, Le b, Cadran) est abandonné en entier. Rien ici n'est encore utilisé par l'app ni par le site : la piste retenue sera intégrée dans les lots L7a (app) et L7b (site).

Planche : `planche.html`, un seul fichier autonome (SVG en ligne, aucune ressource externe). Elle suit le thème du système ; boutons Système, Clair, Sombre et curseur du niveau du glyphe en haut de page. Captures : `captures/` (`pistes-*` pour la vue d'ensemble, `situation-<piste>-*` pour chaque piste en situation, en clair et en sombre ; les captures pleine page `planche-*` sont produites par le rendu mais pas versionnées).

## Les pistes

| Piste | Idée | Dossier |
|---|---|---|
| A · Flottaison (recommandée) | Une colonne haute traversée par sa ligne de charge, comme la marque de Plimsoll des navires. Le liquide monte vers la ligne. | `piste-a-flottaison/` |
| B · Seuil | Une colonne pleine, haute, sous le trait qu'elle ne doit pas toucher. L'écart est ce qui reste. | `piste-b-seuil/` |
| C · Le l | La colonne est le « l » du nom (Brim·l·ine) : une éprouvette haute dont le bord est la limite. | `piste-c-le-l/` |

Méthode reprise de Firméa (et de Vorssaint, son projet d'origine) : un seul aplat de couleur pour tout le symbole, une seule épaisseur de trait (4,5 sur 64), deux formes au plus, beaucoup d'air. Toutes les pistes ont une colonne au moins deux fois plus haute que large (« une barre plus haute »).

## Fichiers de chaque piste

| Fichier | Rôle |
|---|---|
| `app-icon.svg` | Icône d'app, grille macOS 1024 (tuile de 824 à 100 du bord, rayon 185,4, ombre), pour 64 px et plus. |
| `app-icon-small.svg` | Version 16 et 32 px : traits épaissis (7 sur 64), marque agrandie, sans ombre ni reflet. |
| `menubar-template.svg` | Glyphe gabarit de la barre des menus, 18 pt, noir et transparence, niveau 60 %. |
| `symbole.svg` | Symbole en accent (`accent` clair ou sombre selon le thème). |
| `logo-clair.svg`, `logo-sombre.svg` | Logo horizontal (logotype en police système, non vectorisé). |
| `favicon.svg` | La tuile et le symbole, traits épais pour 16 px. |
| `png/` | Rendus : icône 1024, 512, 64, 32, 16 ; favicon 32 et 16 ; glyphe 18 et 36. |

Couleurs : `accent` et `text` de `../../tokens.json`, inchangés. Nouvelles, réservées à l'icône et au favicon : l'encre pétrole de la tuile (`#0F2F3B` vers `#061319`) et l'aqua du symbole sur la tuile (`#7ADFE4`). Le lot d'intégration les ajoute aux jetons. Le glyphe garde les règles de `../../DA.md` (niveau de la limite la plus proche de son plafond, au moins 1 pt de liquide dès que le niveau dépasse 0, opacité 0,45 quand les données sont expirées) ; la piste B ajoute une piste vide à 25 % d'opacité derrière la colonne.

Logotype : police système semi-grasse, non vectorisé (licence de SF Pro) ; pour la piste C surtout, le lot d'intégration choisit une police sous licence libre et vectorise le mot.

## Régénérer

```sh
node design/brimline/v2/src/build.cjs
NODE_PATH=<dossier node_modules qui contient playwright> node design/brimline/v2/src/render.cjs
```

`src/pistes.cjs` est la source unique de la géométrie ; `build.cjs` écrit les SVG et la planche, `render.cjs` les PNG et les captures (Chromium sans tête). Ne pas retoucher les SVG ni la planche à la main.
