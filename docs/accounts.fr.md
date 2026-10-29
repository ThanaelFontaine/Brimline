# Associer vos comptes

*[English version](accounts.md)*

Brimline montre une ligne par compte. Pour Claude, un compte est un **dossier de configuration de Claude Code** : Brimline trouve les dossiers, lit l'adresse avec laquelle chacun est connecté, puis demande à Anthropic où en sont les limites de ce compte. Vous ne tapez jamais de mot de passe ni de jeton dans Brimline.

## En bref

1. Donnez à chaque compte Claude son propre dossier de configuration de Claude Code, choisi avec la variable `CLAUDE_CONFIG_DIR`.
2. Connectez-vous une fois dans chaque dossier avec Claude Code (`/login`).
3. Ouvrez Brimline : chaque dossier nommé `~/.claude` ou `~/.claude-quelquechose` apparaît tout seul. Tout autre dossier s'ajoute dans **Réglages, Comptes, Ajouter un dossier Claude Code…**.

## 1. Un dossier par compte

Claude Code range ses réglages, son historique et sa connexion dans un dossier de configuration. Par défaut, c'est `~/.claude`. La variable `CLAUDE_CONFIG_DIR` en désigne un autre, et chaque dossier a sa propre connexion claude.ai. C'est la façon que propose la documentation de Claude Code pour rester connecté à plusieurs comptes ([Log in with multiple accounts](https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts), en anglais).

Votre premier compte vit en général déjà dans `~/.claude`. Pour un deuxième, ajoutez un alias à `~/.zshrc` (ou `~/.bashrc`) :

```bash
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'
```

Ouvrez un nouveau terminal, puis lancez `claude-work`. Prenez autant de dossiers que de comptes : `~/.claude-equipe`, `~/.claude-client`, etc.

**Nommez-les `~/.claude-quelquechose`** pour que Brimline les trouve seul. Un dossier ailleurs fonctionne aussi : ajoutez-le à la main (étape 3).

## 2. Se connecter dans chaque dossier

Lancez Claude Code avec l'alias du dossier (`claude-work`) et connectez-vous quand il le demande, ou tapez `/login`. Claude Code :

- écrit l'adresse du compte dans `.claude.json`, dans le dossier (pour `~/.claude`, c'est le fichier `~/.claude.json` de votre dossier personnel) ;
- range la connexion dans le Trousseau de macOS, dans un élément propre à ce dossier.

Vérifiez avec `/status` dans Claude Code que la bonne adresse est connectée.

## 3. Brimline

Brimline cherche les comptes à son lancement, et de nouveau quand vous cliquez sur **Rechercher à nouveau** dans les réglages :

- `~/.claude` (adresse lue dans `~/.claude.json`) ;
- chaque dossier `~/.claude-*` qui contient un `.claude.json` ;
- les dossiers ajoutés avec **Ajouter un dossier Claude Code…** (le sélecteur montre les dossiers cachés).

Dans **Réglages, Comptes**, chaque fournisseur a son bloc : un interrupteur, une ligne qui dit ce que Brimline lit et où il le demande, et ses comptes. Pour un compte, vous pouvez le masquer dans la fenêtre de la barre des menus, lui donner un libellé, cocher **Ne pas lire ce compte** (Brimline garde ses derniers chiffres, en gris avec leur âge, et n'ouvre plus sa connexion), ou retirer un dossier ajouté à la main.

![Réglages des comptes](images/settings-accounts-fr-light.png)

## La couleur d'un compte

Chaque compte a une couleur : sa pastille dans la fenêtre de la barre des menus, et sa part de la jauge dans la barre des menus. Brimline en donne une la première fois qu'il voit un compte et la garde, si bien qu'elle ne change pas quand un autre compte apparaît : le premier compte d'un fournisseur prend la couleur de ce fournisseur (celle de Claude est le violet), les suivants la première couleur libre de la palette (sapin, or, marine, cacao, lilas). Les jauges de limites de la fenêtre gardent leurs couleurs (sarcelle, ambre, rouge) : là, la couleur dit à quel point une limite est pleine, pas à qui elle est.

Dans **Réglages, Comptes**, la ligne **Couleur** sous chaque compte permet de la changer :

- **les dix couleurs de la palette** : violet, bleu, magenta, olive, encre, sapin, or, marine, cacao et lilas. Chacune a une valeur pour l'apparence claire et une pour la sombre, de sorte qu'elle reste lisible sur les deux ;
- **Autre couleur…** ouvre le panneau Couleurs du système (sans opacité). La couleur choisie est gardée en six chiffres (`RRGGBB`, sRVB) et reste la même en clair et en sombre ;
- **Revenir au défaut** redonne la couleur que Brimline donnerait à ce compte maintenant. Le bouton est grisé, avec « Couleur par défaut » à côté, quand le compte l'a déjà.

Brimline prévient, et ne refuse jamais :

- **proche de la couleur d'un autre compte** : les deux comptes sont désignés, et leurs parts se distinguent mal dans la jauge (une distance CIEDE2000 sous 10, en clair ou en sombre). Les comptes masqués et ceux d'un fournisseur coupé ne sont pas comparés ;
- **peu visible** : une couleur libre trop pâle ou trop sombre pour la piste vide d'une jauge (contraste sous 3:1, la limite WCAG 2.2 pour les éléments graphiques), en mode clair ou sombre, avec son rapport écrit. Les dix couleurs de la palette atteignent toutes 3:1.

La couleur n'est jamais le seul signal : chaque compte est nommé à côté de sa pastille. Au clavier, chaque couleur est un bouton atteint avec Tab (avec l'accès complet au clavier activé dans Réglages Système) et choisi avec la barre d'espace. VoiceOver lit un groupe par compte (« Couleur de Client ») avec un choix nommé par couleur.

![Les couleurs dans les réglages](images/settings-colors-fr-light.png)

Le choix est enregistré dans `settings.json` (`accountColors`, par compte) et relu à chaque lancement. Une valeur qui n'est ni un emplacement de la palette ni six chiffres hexadécimaux est ignorée, et le compte reçoit sa couleur par défaut.

## Plusieurs comptes

Chaque fournisseur distingue ses comptes à sa façon, et Brimline montre une ligne par compte trouvé :

| Fournisseur | Un compte, c'est | Pour en ajouter un |
|---|---|---|
| Claude | un dossier de Claude Code (`~/.claude`, `~/.claude-*`, ou un dossier ajouté), ou une adresse qui a un relevé de Claude Code | lui donner son propre dossier et s'y connecter (étapes 1 à 3 ci-dessus), ou laisser Claude Code relever ses limites (plus bas) |
| ChatGPT | un dossier de Codex (`~/.codex`, ou un dossier `CODEX_HOME` ajouté) | **Ajouter un dossier Codex…**, sous ChatGPT dans **Réglages, Comptes** |
| Grok | la connexion du Grok CLI dans `~/.grok` : un seul compte | rien : Brimline ne lit que `~/.grok` (un dossier `GROK_HOME` n'est pas lu) |
| Cursor | la connexion de l'app Cursor : un seul compte | rien : Brimline lit la seule connexion de l'app |
| Gemini | la connexion d'Antigravity : un seul compte | rien : Brimline lit la seule connexion d'Antigravity |

Avec quatre comptes Claude, faites quatre dossiers (par exemple `~/.claude-premier`, `~/.claude-deuxieme`, `~/.claude-troisieme`, et `~/.claude` pour le quatrième), connectez-vous une fois dans chacun, et Brimline liste les quatre. Donnez à chacun un libellé court dans **Réglages, Comptes** si son adresse est longue.

**Une connexion faite avec `claude setup-token` n'est pas lue.** Cette commande fabrique un jeton de longue durée pour des scripts. Le 27 octobre 2026, nous avons essayé trois jetons de ce genre sur l'adresse que Brimline interroge pour les limites (une requête chacun, et une seconde une heure plus tard pour les deux qui ont reçu HTTP 429 ; rien d'autre lu ni gardé) : aucun n'a renvoyé de limites (une réponse était un refus, HTTP 403, et deux étaient « trop de requêtes », HTTP 429, les deux fois). Brimline ne lit donc que des dossiers, et n'affirme rien sur ces jetons. Si vous n'avez qu'un tel jeton, connectez-vous plutôt avec `/login` dans un dossier à part.

**Un dossier que vous n'utilisez plus reste « Session expirée ».** Brimline ne renouvelle jamais une connexion : seul Claude Code le fait, quand vous utilisez ce compte. Ses derniers chiffres restent, en gris, avec leur âge.

## Relevés de Claude Code : un compte que Brimline ne lit pas directement

Claude Code connaît déjà les limites de son compte à chaque réponse, et les donne à deux endroits : à votre commande de **ligne d'état** (le champ `rate_limits`, décrit dans la [documentation de Claude Code](https://code.claude.com/docs/en/statusline)), et dans `claude -p --output-format stream-json`, sous la forme d'une ligne `rate_limit_event` (son type, `SDKRateLimitInfo`, est publié avec l'Agent SDK, mais sans `unifiedWindows`, le champ qui porte les deux fenêtres que lit Brimline : voir plus bas). La commande `brimline report claude` lit l'une ou l'autre sur son entrée standard et n'en garde **que les chiffres** : la part utilisée et l'heure de remise à zéro de la session de 5 h et de la semaine. Brimline montre alors ce compte, même sans dossier sur ce Mac (un compte utilisé ailleurs, par un script, ou dont Brimline voit la session expirée), avec l'âge de ses chiffres.

Aucun jeton n'est lu, aucune requête n'est envoyée, aucun quota n'est consommé : les chiffres sont ceux que Claude Code avait déjà.

### Par la ligne d'état

Ajoutez la commande à la ligne d'état de chaque dossier de Claude Code, avec l'adresse du compte de ce dossier. **Réglages, Comptes, Relevés Claude Code** donne la commande prête à copier pour chaque compte Claude que Brimline connaît, son adresse remplie. La ligne d'état se règle dans le `settings.json` du dossier (`~/.claude/settings.json`, ou `~/.claude-travail/settings.json` pour un dossier choisi avec `CLAUDE_CONFIG_DIR`) :

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.local/bin/brimline report claude --account someone@example.com --statusline"
  }
}
```

Avec `--statusline`, la commande affiche une ligne courte (`5 h 23 % · Semaine 41 %`, dans la langue du Mac) quand l'entrée reçue a des limites, et rien sinon (avant la première réponse d'une session, par exemple). Elle ne fait jamais échouer la ligne d'état et n'écrit jamais sur la sortie d'erreur ; sans chiffre à donner, elle n'affiche rien, et la ligne d'état est alors vide si la commande y est seule (Claude Code n'affiche rien pour une commande qui n'affiche rien). Elle n'écrit que si Claude Code a donné une limite.

**Le raccourci `--account auto`** prend l'adresse dans le `.claude.json` du dossier pour lequel la commande tourne : le `CLAUDE_CONFIG_DIR` que voit la commande, ou `~/.claude`. Sa limite : la documentation de Claude Code ne dit pas que la commande de la ligne d'état voit le `CLAUDE_CONFIG_DIR` de la session. Avec `--statusline`, `auto` compare donc le `transcript_path` de la session à ce dossier (Claude Code range l'historique d'un dossier sous `<dossier>/projects/`, [variables d'environnement](https://code.claude.com/docs/en/env-vars)) : si la transcription est dans un autre dossier, ou si l'entrée ne donne pas de `transcript_path` absolu, rien n'est écrit et rien n'est affiché. Avec `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, Claude Code retire `CLAUDE_CONFIG_DIR` des programmes qu'il lance (sa documentation cite les commandes Bash, les hooks et les serveurs MCP stdio ; elle ne dit pas si la ligne d'état en fait partie) : `auto` lirait alors `~/.claude`, et cette vérification l'empêche d'enregistrer les chiffres d'un autre compte. L'adresse écrite en clair, comme ci-dessus, est le moyen sûr.

**Vous avez déjà une ligne d'état.** Gardez-la, et donnez-lui la même entrée. Dans un script à vous (par exemple `~/.claude/statusline.sh`, nommé dans `statusLine.command`) :

```bash
#!/bin/bash
input=$(cat)
printf '%s' "$input" | ~/.local/bin/brimline report claude --account someone@example.com --statusline >/dev/null
# puis votre ligne d'état, comme avant, à partir de "$input"
printf '%s' "$input" | ~/.claude/ma-ligne-detat.sh
```

Retirez `>/dev/null` pour afficher aussi la ligne de Brimline. La documentation de Claude Code dit que `rate_limits` est présent pour les abonnés Claude.ai Pro et Max, après la première réponse d'une session, et que chaque fenêtre peut manquer. Pour une autre offre (un siège Team ou Enterprise), Claude Code peut n'en donner aucune : passez alors par stream-json, ci-dessous.

### Par `claude -p`

Un script qui lance `claude -p --output-format stream-json --verbose` peut envoyer sa sortie à la commande (elle lit chaque ligne et ne garde que les `rate_limit_event`). Donnez-lui la sortie en direct, comme ci-dessous, pas un ancien journal : c'est la dernière entrée reçue qui compte.

```bash
claude -p "..." --output-format stream-json --verbose | tee run.ndjson | ~/.local/bin/brimline report claude --account someone@example.com
```

Donnez l'adresse ici : dans `CLAUDE_CONFIG_DIR=~/.claude-travail claude -p ... | brimline report claude --account auto`, la variable ne vaut que pour `claude`, jamais pour `brimline`, et `auto` prendrait l'adresse de `~/.claude`. La commande lit toujours son entrée jusqu'au bout, même après une option fausse, pour que `claude -p` ne trouve jamais son tube fermé ; une ligne de plus de 64 Kio est jetée sans être gardée.

Codes de sortie : `0` relevé écrit, `3` aucune limite dans l'entrée (rien d'écrit), `4` l'événement de Claude Code a une forme que Brimline ne connaît pas (noté « format modifié »), `1` le relevé n'a pas pu être écrit, `64` une option fausse. `--dir <dossier>` écrit ailleurs (pour les essais : l'app ne lit que son propre dossier) ; le dossier doit être à vous et ouvert à vous seul (`0700`), ou absent (il est alors créé en `0700`) : un dossier ouvert à d'autres, comme votre dossier personnel, est refusé et laissé tel quel.

Le pourcentage d'un `rate_limit_event` est dans `rate_limit_info.unifiedWindows`, un champ absent du type publié de l'événement (vu sur les versions de Claude Code d'octobre 2026). S'il disparaît, Brimline dit « format modifié » et ne montre aucun chiffre nouveau, jamais une supposition.

### Ce que Brimline fait d'un relevé

- Un relevé par adresse, dans `~/Library/Application Support/Brimline/claude-reports/<adresse>.json` (dossier `0700`, fichier `0600`, écrit de façon atomique). Il contient un numéro de version (`schema_version`), l'adresse, d'où viennent les chiffres (`statusline` ou `stream-json`), quand, un état (`ok`, ou `format_changed` quand la dernière entrée avait un événement que Brimline n'a pas su lire), et les deux fenêtres, chacune avec sa part utilisée, son heure de remise à zéro et l'heure où elle a été vue. Rien d'autre de la sortie de Claude Code ne peut y entrer ([SECURITY.md](../SECURITY.md)).
- Fenêtre par fenêtre, chaque fenêtre gardée est remplacée par celle de la dernière entrée reçue : une semaine absente d'une entrée reste telle que vue la dernière fois. Une remise à zéro passée vaut 0 %. Une semaine jamais vue s'affiche **« Semaine : pas encore vue dans les relevés de Claude Code »**, jamais « pas de limite hebdomadaire » (un siège d'équipe peut ne jamais en avoir).
- Un relevé dont l'adresse est celle d'un dossier y est rattaché : ce compte **garde sa lecture directe**, et son relevé ne sert que si la session a expiré ou si l'élément du Trousseau manque, et seulement s'il est plus récent que les derniers chiffres lus. Une adresse sans dossier devient un compte à part, lu par son relevé seulement.
- La carte dit toujours l'âge des chiffres (« Relevé de Claude Code, il y a 3 min »). Un compte peu utilisé montre des chiffres anciens, avec leur âge.
- **« Ne pas lire ce compte »** vaut aussi pour les relevés, par adresse : le relevé de l'adresse de ce compte n'est pas ouvert, même si le `.claude.json` du dossier perd l'adresse un moment. La commande continue d'écrire le relevé : retirez-la de la ligne d'état (ou du script) pour l'arrêter.
- Pour les agents, un compte connu par son seul relevé a `"source": "report"` et `"folder": null`, et chaque compte lu par un relevé a `observed_at`, l'heure où Claude Code a vu ses chiffres ([agents](agents.md)).

## Ce que Brimline lit, et ce qu'il ne fait jamais

Pour chaque dossier, Brimline lit :

- **l'identité du compte** dans `.claude.json` : `oauthAccount.emailAddress`, puis `organizationName` et `seatTier` comme étiquette secondaire. Rien d'autre de ce fichier ;
- **la connexion** dans l'élément du Trousseau que Claude Code a créé pour ce dossier. Il s'appelle `Claude Code-credentials` pour `~/.claude`, et `Claude Code-credentials-` suivi de 8 caractères hexadécimaux pour tout autre dossier (le début du SHA-256 du chemin du dossier ; comportement observé de Claude Code, non documenté, donc susceptible de changer). Brimline le lit avec l'outil du système `/usr/bin/security`, par son nom exact, sans jamais parcourir le Trousseau. [SECURITY.md](../SECURITY.md) explique pourquoi (en anglais).

De la connexion, seul le jeton d'accès sert, en mémoire, le temps d'une requête vers `https://api.anthropic.com/api/oauth/usage`. Brimline n'utilise jamais le jeton de renouvellement, ne renouvelle jamais une connexion, n'écrit jamais dans le Trousseau et n'écrit jamais un jeton dans un fichier, un journal ou ses réponses aux agents.

## Connecter un autre fournisseur

ChatGPT, Gemini, Grok et Cursor n'ont pas de compte à saisir dans Brimline. Chacun se lit par **son propre outil officiel**, que vous installez et dans lequel vous vous connectez vous-même, avec la commande de sa propre documentation. Brimline lit ensuite ce que cet outil garde déjà (ou, pour Gemini, lance la commande de Google). Les mêmes quatre étapes valent pour chacun :

1. Installez l'outil officiel et connectez-vous (plus bas, une ligne par fournisseur).
2. Allumez le fournisseur dans **Réglages, Comptes** (ou `brimline providers enable <nom>`) : tout fournisseur sauf Claude démarre coupé, et un fournisseur coupé n'est pas touché du tout, pas même pour chercher son dossier.
3. Brimline montre une carte. Si la connexion est de celles qu'il ne lit pas, la carte le dit en une phrase et ne montre aucune jauge : il ne vous demande jamais de déplacer une connexion ailleurs. Une connexion rangée dans le Trousseau, ou protégée par son app, est indiquée comme protégée et non lue.
4. Pour laisser un compte tranquille, cochez **Ne pas lire ce compte** (Réglages, Comptes). Brimline garde alors ses derniers chiffres, en gris avec leur âge, et **n'ouvre plus sa connexion** : ni fichier, ni élément du Trousseau, ni requête. Décochez la case pour le lire de nouveau.

Ce qui a été essayé sur chaque fournisseur, et sur quel forfait, est dans le [tableau du README](../README.fr.md#fournisseurs) et dans [providers](providers.md) (en anglais). En bref, chacun a été essayé le 27 octobre 2026 sur un seul forfait (ChatGPT gratuit, Cursor Free, un compte Grok gratuit, un compte Google pour Gemini), et rien n'est affirmé pour un forfait qui n'a pas été essayé.

### ChatGPT, par Codex

Outil officiel : Codex, connecté à votre compte ChatGPT (`codex login`, ou l'écran de connexion de Codex). Par défaut, Codex range sa connexion dans `~/.codex/auth.json`. Si vous avez réglé Codex pour la ranger dans le Trousseau, Brimline ne peut pas la lire et le dit (« Codex range sa connexion dans le Trousseau ou n'est pas connecté ») : il ne lit jamais un élément du Trousseau de Codex.

Allumez ensuite ChatGPT. Brimline montre une carte pour `~/.codex`. Un dossier Codex ailleurs (`CODEX_HOME`) s'ajoute avec **Ajouter un dossier Codex…** dans **Réglages, Comptes**, sous ChatGPT (le sélecteur montre les dossiers cachés).

Brimline ne lit que `auth.json` dans ce dossier, et de lui seulement le mode de connexion, le jeton d'accès et l'identifiant du compte. Il ne renouvelle jamais la connexion : si Codex est resté fermé longtemps, la carte dit « Ouvrez Codex pour rafraîchir la connexion. » Un compte connecté par une clé d'API n'a pas de limite d'abonnement à montrer. Essayé sur ChatGPT gratuit ; comparaison avec la page d'usage d'OpenAI en attente. Détails dans [providers](providers.md) (en anglais).

### Gemini, par Antigravity

Outil officiel : l'Antigravity CLI de Google (`agy`), que vous installez et dans lequel vous vous connectez vous-même, comme le décrit [la documentation de Google](https://antigravity.google/docs/cli/headless/) (en anglais) : Brimline ne vous connecte jamais. `agy` se trouve dans `~/.local/bin/agy`. Allumez ensuite Gemini.

Brimline lance `agy --print /usage` (la commande officielle de Google pour vos limites ; **le programme de Google peut renouveler lui-même sa connexion, et Brimline ne la lit ni ne l'écrit**) et montre, par groupe de modèles, la fenêtre de 5 heures et la semaine, et la limite propre à un modèle quand il y en a une. Seules les builds vérifiées (Antigravity CLI 1.4.8, 1.4.9 et 1.4.10, les 27, 28 et 29/10/2026) sont lancées ; toute autre ne l'est pas, et la carte dit « Antigravity a été mis à jour : mettez Brimline à jour. » Sans `agy`, une carte vous dit où sont vos limites (l'app Gemini, Réglages, Limites d'utilisation). Lu et vérifié sur un compte Google (`agy` ne dit pas le forfait) ; le pourcentage n'a été vu qu'à 100 % restant, et la référence est le texte d'`agy` lui-même. Détails dans [providers](providers.md) (en anglais) et [SECURITY.md](../SECURITY.md) (en anglais).

### Grok, par le CLI Grok

Outil officiel : le CLI Grok, connecté à votre compte xAI (`grok login`, qui ouvre votre navigateur). Le CLI range sa connexion dans `~/.grok/auth.json`. Allumez ensuite Grok. Brimline montre une carte quand le dossier `~/.grok` existe. Sans le CLI Grok, pas de carte : xAI ne publie les limites de Grok que pour le CLI, et les autres sont dans les réglages de votre compte Grok.

Brimline ne lit que `auth.json` dans ce dossier, et de lui seulement la connexion d'un compte xAI : le jeton de session et l'identifiant, en mémoire, le temps d'une requête vers `https://cli-chat-proxy.grok.com`. Il ne renouvelle jamais la connexion : si le CLI Grok est resté fermé longtemps, la carte dit « Ouvrez le CLI Grok pour rafraîchir la connexion. » Un CLI connecté par une clé d'API n'a pas de limite d'abonnement à montrer.

**Un compte Grok gratuit ne reçoit aucune limite de xAI** : sa carte dit « xAI ne renvoie aucune limite de crédits pour ce compte. » et ne montre ni jauge ni pourcentage (essayé le 27/10/2026 ; xAI n'a aucune page de comparaison, et un compte payant n'a pas été essayé). Un plafond sans usage encore dit « Pas encore de chiffre pour cette période. » Détails dans [providers](providers.md) (en anglais).

### Cursor, par son app

Outil officiel : l'app Cursor, connectée comme d'habitude. Cursor n'a pas de compte à relier : Brimline utilise la connexion que l'app garde déjà. Allumez Cursor. Brimline regarde le seul fichier où Cursor range son état et, quand la connexion y est écrite en clair, demande à cursor.com l'usage de votre forfait : le cycle, avec son pourcentage et sa remise à zéro (et les pools Auto et API quand Cursor les donne). Si Cursor protège sa connexion (ou la garde en mode WAL et est fermé), la carte dit « Cursor protège sa connexion sur ce Mac : Brimline ne la lit pas. » et renvoie à cursor.com, Dashboard, Usage. Si la connexion a expiré, la carte dit « Ouvrez Cursor pour rafraîchir la connexion. » Brimline ne la renouvelle jamais, ne lit jamais l'élément du Trousseau de Cursor et ouvre ce fichier en lecture seule, sans rien créer dans le dossier de Cursor (si Cursor garde ce fichier en mode WAL, seulement pendant que Cursor tourne). Essayé sur Cursor Free ; comparaison avec la page d'usage de cursor.com en attente. Détails dans [providers](providers.md) (en anglais).

## Situations courantes

| Ce que vous voyez | Ce que ça veut dire | Que faire |
|---|---|---|
| **Session expirée** | Le jeton d'accès du compte a expiré. Claude Code le renouvelle à sa prochaine utilisation ; Brimline jamais. Ses derniers chiffres restent, en gris, avec leur âge. | Ouvrez Claude Code avec ce compte (n'importe quelle commande suffit). |
| **À reconnecter** | Anthropic a refusé le jeton (HTTP 401). | Lancez `/login` dans Claude Code avec ce dossier. |
| **Pas connecté** | Aucun élément du Trousseau pour ce dossier. | Lancez Claude Code avec ce dossier et connectez-vous. |
| **Indisponible** | Anthropic n'a pas répondu utilement (trop de requêtes, erreur du serveur, réseau, ou réponse que Brimline ne comprend pas). Brimline réessaie plus tard, en attendant un peu plus à chaque fois. | En général, rien. Si ça dure, le point d'accès a peut-être changé : voir la [FAQ](faq.md) (en anglais). |
| **Semaine : pas encore vue dans les relevés de Claude Code** | Les chiffres viennent d'un relevé de Claude Code qui n'a jamais eu la semaine (un siège d'équipe peut ne jamais en avoir). Elle est inconnue, pas absente. | Rien. |
| **Pas de limite hebdomadaire globale** | Le compte (souvent un siège d'équipe) n'a pas de limite hebdomadaire tous modèles ; seules la session et les limites par modèle s'appliquent. | Rien. |
| Un compte manque | Son dossier ne s'appelle pas `~/.claude-*`, ou n'a pas encore de `.claude.json`. | Connectez-vous une fois dans ce dossier, ou ajoutez-le à la main. |

À la première lecture d'un élément, macOS peut afficher une demande du Trousseau si l'élément n'autorise pas déjà l'outil `security`. Dans nos essais avec les éléments de Claude Code, aucune demande n'est apparue ; si l'une apparaît, lisez ce qu'elle demande avant d'autoriser.
