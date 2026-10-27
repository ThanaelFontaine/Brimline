# Brimline

*Formerly Sightglass. Renamed on 26 October 2026, before the first public release, because the name Sightglass is already carried by close software (the reason is in the [changelog](CHANGELOG.md)).*

[![License: PolyForm Shield 1.0.0](https://img.shields.io/badge/license-PolyForm%20Shield%201.0.0-blue.svg)](LICENSE)
[![Status: in development](https://img.shields.io/badge/status-in%20development-orange.svg)](CHANGELOG.md)

*[Version française](README.fr.md)*

**Brimline shows, in your Mac's menu bar, how much of each AI subscription limit you have left: account by account, each one named by its email address.**

If you use several Claude accounts (or Claude and ChatGPT, Gemini, Grok), the built-in indicators show one account at a time, without telling you which one. Brimline puts them side by side: the five hour session, the week, the week per model, and when each one resets.

<p align="center">
  <img src="docs/images/panel-light.png" width="364" alt="The Brimline window: three accounts with their session, weekly and per model limits">
  <img src="docs/images/panel-dark.png" width="364" alt="The same window in dark mode">
</p>

The same numbers are readable by your agents (a command with JSON output and a local MCP server), so an agent can pick the account that still has room.

> **Status:** in development, not released yet. Version 0.1 works with Claude (through Claude Code); [CHANGELOG.md](CHANGELOG.md) says what exists.

The *brim* is the edge a tank fills up to, and the *line* is the limit drawn above it: Brimline shows how close you are to the edge, at a glance.

## Principles

- **Read only.** Brimline reads the sign-in tokens your AI tools already store on your Mac (for Claude Code, the macOS Keychain). It never refreshes, rewrites or moves them, so it can never sign you out of a tool. An expired token is shown as "Session expired", not repaired behind your back.
- **Nothing leaves your Mac**, except the usage requests to each provider. No server, no telemetry, no token ever written to a log.
- **One account, one line, one address.** Several accounts per provider are a first-class case, not an afterthought.
- **Open to any provider.** Each provider will be a small plugin: Claude first, then ChatGPT, Gemini and Grok.
- **Honest about fragility.** As far as we know (October 2026), no provider documents an endpoint for subscription limits. Brimline uses the same internal endpoints as the official tools, which can change without notice. When one breaks, Brimline says so instead of showing a wrong number.

Why another tool, when good ones exist (CodexBar, ClaudeBar, Claude Usage Tracker)? See [docs/why.md](docs/why.md).

## Install

There is no notarized download yet: you build Brimline on your Mac, with Apple's Command Line Tools (no Xcode, no Apple account).

```bash
git clone https://github.com/ThanaelFontaine/Brimline.git
cd Brimline
scripts/build_app.sh     # builds build/Brimline.app
scripts/install.sh       # copies it to ~/Applications, links the command, opens the app
```

Add `--login` to `install.sh` to also open Brimline at login (or turn it on later in **Settings, General**).

Requirements, what macOS shows, updating and uninstalling: [docs/install.md](docs/install.md).

## Use

1. **Link your accounts.** Each Claude account is a Claude Code configuration folder (`~/.claude`, `~/.claude-work`, ...), chosen with `CLAUDE_CONFIG_DIR` and signed in once with `/login`. Brimline finds them by itself. Step by step: [docs/accounts.md](docs/accounts.md).
2. **Click the glyph in the menu bar.** Its level follows the account closest to a limit, whatever the provider. The cards are grouped by provider (a dot and its name, "ChatGPT via Codex"); each card shows its name, then one gauge per limit with its percentage and its reset time ("resets in 2 h 10 (14:30)"), a limit of one model on a compact line under it. A provider that gives no limit Brimline can read (Gemini without Antigravity) shows one sentence and no gauge; "Learn more" opens the rest of it.
3. **Settings** (from the window, or by opening the app again): hide an account, give it a label, add a Claude Code or Codex folder, change the refresh interval (2 to 15 minutes), show the percentage next to the glyph, open at login. Each provider has its own block with a switch, one line that says what Brimline reads and where it asks ("What is read" opens [providers](docs/providers.md)), and a "Don't read this account" box per account: Claude is on; every other provider is **off until you turn it on** (Gemini is read by launching Google's Antigravity command `agy --print /usage`, the one third-party program Brimline launches, and only its build verified on 27/10/2026 (Antigravity CLI 1.4.8) is launched: see [providers](docs/providers.md); Cursor is read through the sign-in its app keeps, with one request to cursor.com: see [providers](docs/providers.md)), and a provider that is off is not touched at all (`brimline providers` does the same from the terminal).

Every state is said in words, never by color alone:

<p align="center">
  <img src="docs/images/panel-states-light.png" width="364" alt="States: data from 25 minutes ago, session expired with the last known values, provider unavailable, no weekly limit across all models">
  <img src="docs/images/settings-accounts-light.png" width="520" alt="Settings, Accounts tab">
</p>

## For agents

```bash
brimline status --json                                              # every account, every limit, with the age of the data
claude mcp add --scope user brimline -- ~/.local/bin/brimline mcp   # MCP tools: list_accounts, get_usage, best_account
```

Both read the cache written by the app and never see a token (only `brimline status --live` reads the Keychain, like the app). Details and JSON format: [docs/agents.md](docs/agents.md).

## Anthropic's terms

Brimline is an independent project: it is not made, endorsed or supported by Anthropic. Anthropic's documentation ([Legal and compliance, Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance)) says that OAuth sign-ins are meant for Claude Code and Anthropic's own apps, and that third-party developers may not offer Claude.ai login in their apps, route requests through Free, Pro or Max plan credentials on behalf of their users, or collect, store or intermediate Claude.ai credentials or session tokens.

What Brimline does, so you can judge for yourself: it runs on your own Mac and reads the sign-in Claude Code already stored there, read only. It never signs you in, never writes, renews or copies the token, and sends it only to Anthropic, to ask for your own usage numbers, under its own name (`User-Agent: Brimline/<version>`). It sends no prompts and uses no model. We do not claim Anthropic allows this use: read the terms that apply to your plan and decide. The same page says Anthropic may enforce these restrictions without prior notice: the risk, if any, is on the account Brimline reads.

## Documentation

- [Linking your accounts](docs/accounts.md) ([en français](docs/accounts.fr.md))
- [Installing](docs/install.md)
- [Agents: command and MCP server](docs/agents.md)
- [FAQ](docs/faq.md)
- [Why Brimline](docs/why.md)
- [Security model](SECURITY.md)
- [Design: colors, glyph, icon](design/DA.md) (in French)

## License

Brimline's source code is public, but it is not open source in the OSI sense: [PolyForm Shield 1.0.0](LICENSE), © 2026 Thanaël Fontaine. Anyone may use, modify and share it, at work too, or to sell their own products and services; nobody may provide a product that competes with Brimline, even for free (reselling it, offering it as a hosted service). The author keeps every right, including selling his own hosted version.

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: see [SECURITY.md](SECURITY.md).
