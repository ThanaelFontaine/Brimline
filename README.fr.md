# Sightglass

[![Licence : PolyForm Shield 1.0.0](https://img.shields.io/badge/licence-PolyForm%20Shield%201.0.0-blue.svg)](LICENSE)
[![État : en développement](https://img.shields.io/badge/%C3%A9tat-en%20d%C3%A9veloppement-orange.svg)](CHANGELOG.md)

*[English version](README.md)*

**Sightglass montre, dans la barre des menus du Mac, où en est chaque limite de tes abonnements IA : compte par compte, chacun nommé par son adresse.**

Avec plusieurs comptes Claude (ou Claude et ChatGPT, Gemini, Grok), les indicateurs intégrés montrent un compte à la fois, sans dire lequel. Sightglass les met côte à côte : limite de session de 5 heures, limite de la semaine, limite de la semaine par modèle, et l'heure où chacune repart.

```
you@example.com    5 h             ███░░░░░░░   34 %   repart à 02:59
                   Fable, semaine  ░░░░░░░░░░    0 %   repart lun. 02:00
team@example.org   5 h             ██████████  100 %   repart à 00:19
                   semaine         █████░░░░░   49 %   repart lun. 11:59
```

Les mêmes chiffres sont lisibles par tes agents (une commande à sortie JSON et un serveur MCP local) : un agent peut choisir le compte qui a encore de la marge.

> **État :** en développement, pas encore publié. Ce README décrit le but ; le [CHANGELOG](CHANGELOG.md) dit ce qui existe.

## Principes

- **Lecture seule.** Sightglass lit les jetons de connexion que tes outils IA rangent déjà sur le Mac (pour Claude Code, le Trousseau de macOS). Il ne les renouvelle, ne les réécrit et ne les déplace jamais : il ne peut donc jamais te déconnecter d'un outil. Un jeton expiré s'affiche « reconnecte ce compte », il ne se répare pas en douce.
- **Rien ne sort du Mac**, hormis les requêtes d'usage vers chaque fournisseur. Aucun serveur, aucune télémétrie, aucun jeton dans un journal.
- **Un compte, une ligne, une adresse.** Plusieurs comptes par fournisseur, c'est le cas normal.
- **Ouvert à tout fournisseur.** Chaque fournisseur est un petit greffon : Claude d'abord, puis ChatGPT, Gemini et Grok.
- **Honnête sur la fragilité.** À notre connaissance (octobre 2026), aucun fournisseur ne documente de point d'accès pour les limites d'un abonnement. Sightglass passe par les mêmes points d'accès internes que les outils officiels, qui peuvent changer sans préavis. Quand l'un casse, Sightglass le dit au lieu d'afficher un faux chiffre.

Pourquoi un outil de plus, quand de bons existent (CodexBar, ClaudeBar, Claude Usage Tracker) ? Voir [docs/why.md](docs/why.md) (en anglais).

## Installer

Pas encore disponible.

## Licence

Code source public sous licence [PolyForm Shield 1.0.0](LICENSE), © 2026 Thanaël Fontaine : ce n'est pas de l'open source au sens de l'OSI. Chacun peut l'utiliser, le modifier et le partager, y compris au travail ou pour vendre ses propres produits et services ; personne ne peut en faire un produit concurrent, même gratuit (le revendre, le proposer en service hébergé). L'auteur garde tous ses droits, dont celui de vendre sa propre version hébergée.

Les contributions sont les bienvenues : voir [CONTRIBUTING.md](CONTRIBUTING.md). Signaler une faille : voir [SECURITY.md](SECURITY.md).
