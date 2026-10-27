# Linking your accounts

*[Version française](accounts.fr.md)*

Brimline shows one line per account. For Claude, an account is a **Claude Code configuration folder**: Brimline finds the folders, reads which address each one is signed in with, and asks Anthropic for that account's limits. You never type a password or a token into Brimline.

## The short version

1. Give each Claude account its own Claude Code configuration folder, chosen with the `CLAUDE_CONFIG_DIR` variable.
2. Sign in once in each folder with Claude Code (`/login`).
3. Open Brimline: every folder named `~/.claude` or `~/.claude-something` shows up by itself. Any other folder can be added in **Settings, Accounts, Add a Claude Code folder…**.

## 1. One folder per account

Claude Code keeps its settings, history and sign-in in a configuration folder. By default it is `~/.claude`. The `CLAUDE_CONFIG_DIR` variable picks another one, and each folder has its own claude.ai sign-in. This is how Claude Code's documentation suggests staying signed in to several accounts ([Log in with multiple accounts](https://code.claude.com/docs/en/authentication#log-in-with-multiple-accounts)).

Your first account usually lives in `~/.claude` already. For a second one, add an alias to `~/.zshrc` (or `~/.bashrc`):

```bash
alias claude-work='CLAUDE_CONFIG_DIR=~/.claude-work claude'
```

Open a new terminal, then run `claude-work`. Use as many folders as you have accounts: `~/.claude-team`, `~/.claude-client`, and so on.

**Name them `~/.claude-something`** so Brimline finds them by itself. A folder elsewhere works too: add it by hand (step 3).

## 2. Sign in in each folder

Start Claude Code with the folder's alias (`claude-work`) and sign in when it asks, or type `/login`. Claude Code then:

- writes the account's address in `.claude.json`, inside the folder (for `~/.claude`, the file is `~/.claude.json` in your home folder);
- stores the sign-in in the macOS Keychain, in an item tied to that folder.

Check with `/status` in Claude Code that the right address is signed in.

## 3. Brimline

Brimline looks for accounts when it starts, and again when you click **Search again** in the settings:

- `~/.claude` (address read from `~/.claude.json`);
- every `~/.claude-*` folder that contains a `.claude.json`;
- the folders you added with **Add a Claude Code folder…** (the file picker shows hidden folders).

In **Settings, Accounts** each provider has its own block: a switch, one line that says what Brimline reads and where it asks, and its accounts. For an account you can hide it from the menu bar window, give it a custom label, tick **Don't read this account** (Brimline keeps its last numbers, in grey with their age, and no longer opens its sign-in), or remove a folder you added by hand.

![Accounts settings](images/settings-accounts-light.png)

## The color of an account

Every account has a color: its dot in the menu bar window, and its part of the gauge in the menu bar. Brimline gives one the first time it sees an account and keeps it, so it does not change when another account appears: the first account of a provider has that provider's color (Claude's is violet), the next ones the first free color of the palette (pine, gold, navy, cocoa, lilac). The limit gauges of the window keep their own colors (teal, amber, red): there, the color says how full a limit is, not whose it is.

In **Settings, Accounts**, the **Color** line under each account lets you change it:

- **the ten colors of the palette**: violet, blue, magenta, olive, ink, pine, gold, navy, cocoa and lilac. Each one has a value for the light and one for the dark appearance, so it stays readable on both;
- **Other color…** opens the system color picker (without opacity). The color you pick is kept as six digits (`RRGGBB`, sRGB) and is the same in light and in dark;
- **Reset to default** gives back the color Brimline would give this account now. It is greyed, with "Default color" beside it, when the account already has it.

Brimline warns, and never refuses:

- **close to another account's color**: the two accounts are shown, and their parts are hard to tell apart in the gauge (a CIEDE2000 distance under 10, in light or in dark). Hidden accounts and accounts of a provider that is off are not compared;
- **hard to see**: a free color too pale or too dark for the empty track of a gauge (under 3:1 contrast, the WCAG 2.2 limit for graphics), in light or in dark mode, with its ratio written. The ten colors of the palette all reach 3:1.

The color is never the only signal: every account is named beside its dot. With the keyboard, each color is a button reached with Tab (with Full Keyboard Access on in System Settings) and chosen with Space. VoiceOver reads one group per account ("Color of Asso") with one named choice per color.

![Colors in the settings](images/settings-colors-light.png)

The choice is saved in `settings.json` (`accountColors`, by account), and read again at each launch. A value that is not a palette slot or six hexadecimal digits is ignored, and the account gets its default color.

## What Brimline reads, and what it never does

For each folder, Brimline reads:

- **the account's identity** in `.claude.json`: `oauthAccount.emailAddress`, and `organizationName` and `seatTier` as a secondary label. Nothing else from that file;
- **the sign-in** in the Keychain item Claude Code made for that folder. The item's name is `Claude Code-credentials` for `~/.claude`, and `Claude Code-credentials-` followed by 8 hexadecimal characters for any other folder (the start of the SHA-256 of the folder's path; observed behavior of Claude Code, not documented, so it may change). Brimline reads it with the system's `/usr/bin/security` tool, by its exact name, without ever listing the Keychain. [SECURITY.md](../SECURITY.md) explains why.

From the sign-in, only the access token is used, in memory, for one request to `https://api.anthropic.com/api/oauth/usage`. Brimline never uses the refresh token, never renews a sign-in, never writes to the Keychain, and never writes a token to a file, a log or its answers to agents.

## Connecting another provider

ChatGPT, Gemini, Grok and Cursor have no account to type into Brimline. Each one is read through **its own official tool**, which you install and sign in to yourself, with the command of its own documentation. Brimline then reads what that tool already keeps (or, for Gemini, launches Google's command). The same four steps apply to each:

1. Install the official tool and sign in to it (below, one line per provider).
2. Turn the provider **on** in **Settings, Accounts** (or `brimline providers enable <name>`): every provider but Claude starts off, and a provider that is off is not touched at all, not even to look for its folder.
3. Brimline shows one card for it. If the sign-in is one it does not read, the card says so in a sentence and shows no gauge: it never asks you to move a sign-in somewhere else. A sign-in kept in the Keychain, or protected by its app, is shown as protected and not read.
4. To leave one account alone, tick **Don't read this account** (Settings, Accounts). Brimline then keeps its last numbers, in grey with their age, and **no longer opens its sign-in**: no file, no Keychain item, no request. Turn the box off to read it again.

What was tried on each provider, and on which plan, is in the [table of the README](../README.md#providers) and in [providers](providers.md). In short, each was tried on 27 October 2026 on one plan only (ChatGPT Free, Cursor Free, a free Grok account, a Google account for Gemini), and nothing is claimed for a plan that was not tried.

### ChatGPT, through Codex

Official tool: Codex, signed in with your ChatGPT account (`codex login`, or the sign-in screen of Codex). Codex keeps its sign-in in `~/.codex/auth.json` by default. If you changed Codex's setting to keep it in the Keychain, Brimline cannot read it and says so ("Codex keeps its sign-in in the Keychain or is signed out"): it never reads a Keychain item of Codex.

Then turn ChatGPT on. Brimline shows one card for `~/.codex`. A Codex folder elsewhere (`CODEX_HOME`) is added with **Add a Codex folder…** in **Settings, Accounts**, under ChatGPT (the file picker shows hidden folders).

Brimline reads only `auth.json` in that folder, and of it the sign-in mode, the access token and the account id. It never renews the sign-in: if Codex has been closed for a long time the card says "Open Codex to refresh the sign-in." An account signed in with an API key has no subscription limit to show. Tried on ChatGPT Free; comparison with OpenAI's usage page pending. Details in [providers](providers.md).

### Gemini, through Antigravity

Official tool: Google's Antigravity CLI (`agy`), which you install and sign in to yourself, as [Google's documentation](https://antigravity.google/docs/cli/headless/) describes: Brimline never signs you in. `agy` lives at `~/.local/bin/agy`. Then turn Gemini on.

Brimline launches `agy --print /usage` (Google's official command for your limits; **Google's program may renew its own sign-in, and Brimline neither reads nor writes it**) and shows, per group of models, the 5 hour window and the week, and the limit of a model of its own when there is one. Only the build verified on 27/10/2026 (Antigravity CLI 1.4.8) is launched; any other build is not, and the card says "Antigravity was updated: update Brimline." Without `agy`, one card tells you where your limits are (the Gemini app, Settings, Usage limits). Read and checked on a Google account (`agy` does not say the plan); the percentage was seen at 100 % remaining only, and the reference is `agy`'s own text. Details in [providers](providers.md) and [SECURITY.md](../SECURITY.md).

### Grok, through the Grok CLI

Official tool: the Grok CLI, signed in with your xAI account (`grok login`, which opens your browser). The CLI keeps its sign-in in `~/.grok/auth.json`. Then turn Grok on. Brimline shows one card when the folder `~/.grok` exists. Without the Grok CLI there is no card: xAI publishes the limits of Grok for the CLI only, and the others are in your Grok account settings.

Brimline reads only `auth.json` in that folder, and of it the sign-in with an xAI account: the session token and the user id, in memory, for one request to `https://cli-chat-proxy.grok.com`. It never renews the sign-in: if the Grok CLI has been closed for a long time the card says "Open the Grok CLI to refresh the sign-in." A CLI signed in with an API key has no subscription limit to show.

**A free Grok account gets no limit from xAI**: its card says "xAI returns no credit limit for this account." and shows no gauge and no percentage (tried on 27/10/2026; there is no xAI page to compare with, and a paid account was not tried). An allowance with no use yet says "No number yet for this period." Details in [providers](providers.md).

### Cursor, through its app

Official tool: the Cursor app, signed in as usual. Cursor has no account to link: Brimline uses the sign-in the app already keeps. Turn Cursor on. Brimline looks at the one file where Cursor keeps its state and, when the sign-in is stored there as a plain token, asks cursor.com for the usage of your plan: the cycle, with its percentage and its reset time (and the Auto and API pools when Cursor gives them). If Cursor protects its sign-in (or keeps it in WAL mode and is closed), the card says "Cursor protects its sign-in on this Mac: Brimline does not read it." and points to cursor.com, Dashboard, Usage. If the sign-in has expired, the card says "Open Cursor to refresh the sign-in." Brimline never renews it, never reads Cursor's Keychain item and opens that file read-only, creating nothing in Cursor's folder (if Cursor keeps that file in WAL mode, only while Cursor is running). Tried on Cursor Free; comparison with the cursor.com usage page pending. Details in [providers](providers.md).

## Common situations

| What you see | What it means | What to do |
|---|---|---|
| **Session expired** | The account's access token has expired. Claude Code renews it the next time you use it; Brimline never does. Its last numbers stay, in grey, with their age. | Open Claude Code with this account (any command will do). |
| **Sign in again** | Anthropic refused the token (HTTP 401). | Run `/login` in Claude Code with this folder. |
| **Not signed in** | No Keychain item for this folder. | Run Claude Code with this folder and sign in. |
| **Unavailable** | Anthropic did not answer usefully (rate limit, server error, network, or an answer Brimline does not understand). Brimline tries again later, waiting longer each time. | Nothing, usually. If it lasts, the endpoint may have changed: see the [FAQ](faq.md). |
| **No weekly limit across all models** | The account (often a team seat) has no weekly limit across all models; only the session and per model limits apply. | Nothing. |
| An account is missing | Its folder is not named `~/.claude-*`, or has no `.claude.json` yet. | Sign in once in that folder, or add it by hand. |

The first time Brimline reads an item, macOS may show a Keychain prompt if the item does not already allow the `security` tool. In our tests with the Claude Code items, no prompt appeared; if one does, read what it asks before allowing.
