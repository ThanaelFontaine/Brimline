# Sightglass

[![License: PolyForm Shield 1.0.0](https://img.shields.io/badge/license-PolyForm%20Shield%201.0.0-blue.svg)](LICENSE)
[![Status: in development](https://img.shields.io/badge/status-in%20development-orange.svg)](CHANGELOG.md)

*[Version française](README.fr.md)*

**Sightglass shows, in your Mac's menu bar, how much of each AI subscription limit you have left: account by account, each one named by its email address.**

If you use several Claude accounts (or Claude and ChatGPT, Gemini, Grok), the built-in indicators show one account at a time, without telling you which one. Sightglass puts them side by side: the five hour session, the week, the week per model, and when each one resets.

<p align="center">
  <img src="docs/images/panel-light.png" width="364" alt="The Sightglass window: three accounts with their session, weekly and per model limits">
  <img src="docs/images/panel-dark.png" width="364" alt="The same window in dark mode">
</p>

The same numbers are readable by your agents (a command with JSON output and a local MCP server), so an agent can pick the account that still has room.

> **Status:** in development, not released yet. Version 0.1 works with Claude (through Claude Code); [CHANGELOG.md](CHANGELOG.md) says what exists.

A *sight glass* is the glass tube on the side of a tank that shows its level at a glance: what is left, without opening anything.

## Principles

- **Read only.** Sightglass reads the sign-in tokens your AI tools already store on your Mac (for Claude Code, the macOS Keychain). It never refreshes, rewrites or moves them, so it can never sign you out of a tool. An expired token is shown as "sign in again", not repaired behind your back.
- **Nothing leaves your Mac**, except the usage requests to each provider. No server, no telemetry, no token ever written to a log.
- **One account, one line, one address.** Several accounts per provider are a first-class case, not an afterthought.
- **Open to any provider.** Each provider is a small plugin: Claude first, then ChatGPT, Gemini and Grok.
- **Honest about fragility.** As far as we know (October 2026), no provider documents an endpoint for subscription limits. Sightglass uses the same internal endpoints as the official tools, which can change without notice. When one breaks, Sightglass says so instead of showing a wrong number.

Why another tool, when good ones exist (CodexBar, ClaudeBar, Claude Usage Tracker)? See [docs/why.md](docs/why.md).

## Install

There is no notarized download yet: you build Sightglass on your Mac, with Apple's Command Line Tools (no Xcode, no Apple account).

```bash
git clone https://github.com/ThanaelFontaine/Sightglass.git
cd Sightglass
scripts/build_app.sh     # builds build/Sightglass.app
scripts/install.sh       # copies it to ~/Applications, links the command, opens the app
```

Requirements, what macOS shows, updating and uninstalling: [docs/install.md](docs/install.md).

## Use

1. **Link your accounts.** Each Claude account is a Claude Code configuration folder (`~/.claude`, `~/.claude-work`, ...), chosen with `CLAUDE_CONFIG_DIR` and signed in once with `/login`. Sightglass finds them by itself. Step by step: [docs/accounts.md](docs/accounts.md).
2. **Click the glyph in the menu bar.** Its level follows the account closest to a limit. Each card shows the address, then one gauge per limit with its percentage and its reset time ("resets in 2 h 10 (14:30)").
3. **Settings** (from the window, or by opening the app again): hide an account, give it a label, add a folder, change the refresh interval (2 to 15 minutes), show the percentage next to the glyph, open at login.

Every state is said in words, never by color alone:

<p align="center">
  <img src="docs/images/panel-states-light.png" width="364" alt="States: data from 25 minutes ago, session expired with the last known values, provider unavailable, no weekly limit across all models">
  <img src="docs/images/settings-accounts-light.png" width="520" alt="Settings, Accounts tab">
</p>

## For agents

```bash
sightglass status --json                               # every account, every limit, with the age of the data
claude mcp add sightglass -- ~/.local/bin/sightglass mcp   # MCP tools: list_accounts, get_usage, best_account
```

Both read the cache written by the app and never see a token. Details and JSON format: [docs/agents.md](docs/agents.md).

## Documentation

- [Linking your accounts](docs/accounts.md) ([en français](docs/accounts.fr.md))
- [Installing](docs/install.md)
- [Agents: command and MCP server](docs/agents.md)
- [FAQ](docs/faq.md)
- [Why Sightglass](docs/why.md)
- [Security model](SECURITY.md)
- [Design: colors, glyph, icon](design/DA.md) (in French)

## License

Sightglass's source code is public, but it is not open source in the OSI sense: [PolyForm Shield 1.0.0](LICENSE), © 2026 Thanaël Fontaine. Anyone may use, modify and share it, at work too, or to sell their own products and services; nobody may provide a product that competes with Sightglass, even for free (reselling it, offering it as a hosted service). The author keeps every right, including selling his own hosted version.

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: see [SECURITY.md](SECURITY.md).
