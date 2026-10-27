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

In **Settings, Accounts** you can hide an account from the menu bar window, give it a custom label, or remove a folder you added by hand.

![Accounts settings](images/settings-accounts-light.png)

## What Brimline reads, and what it never does

For each folder, Brimline reads:

- **the account's identity** in `.claude.json`: `oauthAccount.emailAddress`, and `organizationName` and `seatTier` as a secondary label. Nothing else from that file;
- **the sign-in** in the Keychain item Claude Code made for that folder. The item's name is `Claude Code-credentials` for `~/.claude`, and `Claude Code-credentials-` followed by 8 hexadecimal characters for any other folder (the start of the SHA-256 of the folder's path; observed behavior of Claude Code, not documented, so it may change). Brimline reads it with the system's `/usr/bin/security` tool, by its exact name, without ever listing the Keychain. [SECURITY.md](../SECURITY.md) explains why.

From the sign-in, only the access token is used, in memory, for one request to `https://api.anthropic.com/api/oauth/usage`. Brimline never uses the refresh token, never renews a sign-in, never writes to the Keychain, and never writes a token to a file, a log or its answers to agents.

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
