# Brimline

*Anciennement Sightglass. Renommé le 26 octobre 2026, avant la première publication, parce que le nom Sightglass est déjà porté par des logiciels proches (la raison est dans le [CHANGELOG](CHANGELOG.md)).*

[![Licence : PolyForm Shield 1.0.0](https://img.shields.io/badge/licence-PolyForm%20Shield%201.0.0-blue.svg)](LICENSE)
[![État : en développement](https://img.shields.io/badge/%C3%A9tat-en%20d%C3%A9veloppement-orange.svg)](CHANGELOG.md)

*[English version](README.md)*

**Brimline montre, dans la barre des menus du Mac, où en est chaque limite de tes abonnements IA : compte par compte, chacun nommé par son adresse.**

Avec plusieurs comptes Claude (ou Claude et ChatGPT, Gemini, Grok), les indicateurs intégrés montrent un compte à la fois, sans dire lequel. Brimline les met côte à côte : limite de session de 5 heures, limite de la semaine, limite de la semaine par modèle, et l'heure où chacune repart.

<p align="center">
  <img src="docs/images/panel-fr-light.png" width="364" alt="La fenêtre de Brimline : trois comptes avec leurs limites de session, de semaine et par modèle">
  <img src="docs/images/panel-fr-dark.png" width="364" alt="La même fenêtre en mode sombre">
</p>

Les mêmes chiffres sont lisibles par tes agents (une commande à sortie JSON et un serveur MCP local) : un agent peut choisir le compte qui a encore de la marge.

> **État :** en développement, pas encore publié. La version 0.1 fonctionne avec Claude (par Claude Code) ; le [CHANGELOG](CHANGELOG.md) dit ce qui existe.

Le *brim* est le bord jusqu'où monte une cuve, et la *line* la limite tracée au-dessus : Brimline montre d'un coup d'œil à quelle distance du bord tu en es.

## Principes

- **Lecture seule.** Brimline lit les jetons de connexion que tes outils IA rangent déjà sur le Mac (pour Claude Code, le Trousseau de macOS). Il ne les renouvelle, ne les réécrit et ne les déplace jamais : il ne peut donc jamais te déconnecter d'un outil. Un jeton expiré s'affiche « Session expirée », il ne se répare pas en douce.
- **Rien ne sort du Mac**, hormis les requêtes d'usage vers chaque fournisseur. Aucun serveur, aucune télémétrie, aucun jeton dans un journal.
- **Un compte, une ligne, une adresse.** Plusieurs comptes par fournisseur, c'est le cas normal.
- **Ouvert à tout fournisseur.** Chaque fournisseur sera un petit greffon : Claude d'abord, puis ChatGPT, Gemini et Grok.
- **Honnête sur la fragilité.** À notre connaissance (octobre 2026), aucun fournisseur ne documente de point d'accès pour les limites d'un abonnement. Brimline passe par les mêmes points d'accès internes que les outils officiels, qui peuvent changer sans préavis. Quand l'un casse, Brimline le dit au lieu d'afficher un faux chiffre.

Pourquoi un outil de plus, quand de bons existent (CodexBar, ClaudeBar, Claude Usage Tracker) ? Voir [docs/why.md](docs/why.md) (en anglais).

## Installer

Il n'y a pas encore d'app notariée à télécharger : tu construis Brimline sur ton Mac, avec les Command Line Tools d'Apple (ni Xcode, ni compte Apple).

```bash
git clone https://github.com/ThanaelFontaine/Brimline.git
cd Brimline
scripts/build_app.sh     # construit build/Brimline.app
scripts/install.sh       # la copie dans ~/Applications, relie la commande, ouvre l'app
```

Ajoute `--login` à `install.sh` pour ouvrir aussi Brimline à la connexion (ou active-le plus tard dans **Réglages, Général**).

Prérequis, ce que montre macOS, mise à jour et désinstallation : [docs/install.md](docs/install.md) (en anglais).

## Utiliser

1. **Associe tes comptes.** Chaque compte Claude est un dossier de configuration de Claude Code (`~/.claude`, `~/.claude-work`, ...), choisi avec `CLAUDE_CONFIG_DIR` et connecté une fois avec `/login`. Brimline les trouve seul. Pas à pas : [docs/accounts.fr.md](docs/accounts.fr.md).
2. **Clique sur le glyphe dans la barre des menus.** Son niveau suit le compte le plus proche d'une limite. Chaque carte montre l'adresse, puis une jauge par limite avec son pourcentage et son heure de remise à zéro (« repart dans 2 h 10 (14:30) »).
3. **Réglages** (depuis la fenêtre, ou en rouvrant l'app) : masquer un compte, lui donner un libellé, ajouter un dossier, changer l'intervalle d'actualisation (2 à 15 minutes), afficher le pourcentage à côté du glyphe, ouvrir à la connexion. Il y a aussi un interrupteur par fournisseur et une case « Ne pas lire » par compte : Claude est allumé ; tout autre fournisseur est **coupé tant que tu ne l'allumes pas** (Gemini n'affiche aujourd'hui qu'une phrase, voir [providers](docs/providers.md)), et un fournisseur coupé n'est pas touché du tout (`brimline providers` fait la même chose depuis le terminal).

L'app suit la langue du Mac (anglais ou français). Chaque état est dit en mots, jamais par la seule couleur :

<p align="center">
  <img src="docs/images/panel-states-fr-light.png" width="364" alt="États : données d'il y a 25 minutes, session expirée avec les dernières valeurs connues, fournisseur indisponible, pas de limite hebdomadaire globale">
  <img src="docs/images/settings-accounts-fr-light.png" width="520" alt="Réglages, onglet Comptes">
</p>

## Pour les agents

```bash
brimline status --json                                              # chaque compte, chaque limite, avec l'âge des données
claude mcp add --scope user brimline -- ~/.local/bin/brimline mcp   # outils MCP : list_accounts, get_usage, best_account
```

Les deux lisent le cache écrit par l'app et ne voient jamais de jeton (seule `brimline status --live` lit le Trousseau, comme l'app). Détails et format JSON : [docs/agents.md](docs/agents.md) (en anglais).

## Les conditions d'Anthropic

Brimline est un projet indépendant : ni fait, ni approuvé, ni soutenu par Anthropic. La documentation d'Anthropic ([Legal and compliance, Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance), en anglais) dit que les connexions OAuth sont prévues pour Claude Code et les applications d'Anthropic, et que les développeurs tiers ne peuvent pas proposer la connexion Claude.ai dans leurs applications, faire passer des requêtes par les identifiants d'un abonnement Free, Pro ou Max pour le compte de leurs utilisateurs, ni collecter, stocker ou relayer des identifiants ou jetons de session Claude.ai.

Ce que fait Brimline, pour que tu juges toi-même : il tourne sur ton propre Mac et lit la connexion que Claude Code y a déjà rangée, en lecture seule. Il ne te connecte jamais, n'écrit, ne renouvelle ni ne copie le jeton, et ne l'envoie qu'à Anthropic, pour demander tes propres chiffres d'usage, sous son propre nom (`User-Agent: Brimline/<version>`). Il n'envoie aucune requête à un modèle. Nous ne prétendons pas qu'Anthropic autorise cet usage : lis les conditions de ton abonnement et décide. La même page dit qu'Anthropic peut faire respecter ces restrictions sans préavis : le risque éventuel porte sur le compte que Brimline lit.

## Documentation

- [Associer vos comptes](docs/accounts.fr.md) ([in English](docs/accounts.md))
- [Installer](docs/install.md) (en anglais)
- [Agents : commande et serveur MCP](docs/agents.md) (en anglais)
- [FAQ](docs/faq.md) (en anglais)
- [Pourquoi Brimline](docs/why.md) (en anglais)
- [Modèle de sécurité](SECURITY.md) (en anglais)
- [Direction artistique : couleurs, glyphe, icône](design/DA.md)

## Licence

Code source public sous licence [PolyForm Shield 1.0.0](LICENSE), © 2026 Thanaël Fontaine : ce n'est pas de l'open source au sens de l'OSI. Chacun peut l'utiliser, le modifier et le partager, y compris au travail ou pour vendre ses propres produits et services ; personne ne peut en faire un produit concurrent, même gratuit (le revendre, le proposer en service hébergé). L'auteur garde tous ses droits, dont celui de vendre sa propre version hébergée.

Les contributions sont les bienvenues : voir [CONTRIBUTING.md](CONTRIBUTING.md). Signaler une faille : voir [SECURITY.md](SECURITY.md).
