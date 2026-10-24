# Sightglass

[![License: PolyForm Shield 1.0.0](https://img.shields.io/badge/license-PolyForm%20Shield%201.0.0-blue.svg)](LICENSE)
[![Status: in development](https://img.shields.io/badge/status-in%20development-orange.svg)](CHANGELOG.md)

*[Version française](README.fr.md)*

**Sightglass shows, in your Mac's menu bar, how much of each AI subscription limit you have left: account by account, each one named by its email address.**

If you use several Claude accounts (or Claude and ChatGPT, Gemini, Grok), the built-in indicators show one account at a time, without telling you which one. Sightglass puts them side by side:

```
you@example.com         5 h  ███░░░░░░░  34 %   resets 02:59
                        Fable week  ░░░░░░░░░░   0 %   resets Mon 02:00
team@example.org        5 h  ██████████ 100 %   resets 00:19
                        week ████▉░░░░░  49 %   resets Mon 11:59
```

The same numbers are readable by your agents (a command with JSON output and a local MCP server), so an agent can pick the account that still has room.

> **Status:** in development, not released yet. This README describes the goal; [CHANGELOG.md](CHANGELOG.md) says what exists.

## Principles

- **Read only.** Sightglass reads the sign-in tokens your AI tools already store on your Mac (for Claude Code, the macOS Keychain). It never refreshes, rewrites or moves them, so it can never sign you out of a tool. An expired token is shown as "sign in again", not repaired behind your back.
- **Nothing leaves your Mac**, except the usage requests to each provider. No server, no telemetry, no token ever written to a log.
- **One account, one line, one address.** Several accounts per provider are a first-class case, not an afterthought.
- **Open to any provider.** Each provider is a small plugin: Claude first, then ChatGPT, Gemini and Grok.
- **Honest about fragility.** No provider documents an endpoint for subscription limits. Sightglass uses the same internal endpoints as the official tools, which can change without notice. When one breaks, Sightglass says so instead of showing a wrong number.

Why another tool, when good ones exist (CodexBar, ClaudeBar, Claude Usage Tracker)? See [docs/why.md](docs/why.md).

## Install

Not available yet.

## License

Sightglass's source code is public, but it is not open source in the OSI sense: [PolyForm Shield 1.0.0](LICENSE), © 2026 Thanaël Fontaine. Anyone may use, modify and share it, at work too, or to sell their own products and services; nobody may provide a product that competes with Sightglass, even for free (reselling it, offering it as a hosted service). The author keeps every right, including selling his own hosted version.

Contributions are welcome: see [CONTRIBUTING.md](CONTRIBUTING.md). Security reports: see [SECURITY.md](SECURITY.md).
