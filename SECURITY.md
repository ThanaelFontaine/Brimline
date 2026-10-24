# Security policy

Sightglass reads the sign-in tokens of your AI tools (for Claude Code, from the macOS Keychain). Security reports are taken seriously and handled privately.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting: on the repository page, **Security** tab, **Report a vulnerability**. If the button is not there, contact the maintainer privately through the contact details on their GitHub profile.

Please include what an attacker can do and under which conditions, steps to reproduce, and the affected version and macOS version. Never send real tokens or account data in a report: use fictitious data.

What to expect: an acknowledgement within 7 days, an assessment and a plan, then a fix released as a new version with a changelog entry. Sightglass is maintained on a volunteer basis, so timelines are best effort.

## Supported versions

Only the latest released version receives security fixes.

## Threat model

### What Sightglass is

A macOS app that runs under your user account. It reads the tokens your AI tools already store, asks each provider for the usage of each account, and shows the result in the menu bar, in a command with JSON output and in a local MCP server. There is no Sightglass server and no telemetry.

### What it promises

- **Read only.** Tokens are read, never refreshed, rewritten, moved or copied to another store. Refreshing a token can rotate it, which may sign the official tool out: Sightglass never does it.
- **Tokens stay in memory**, only for the request that needs them. They are never written to a log, a cache file, the JSON output or the MCP answers.
- **Only the providers' own hosts** are contacted, over HTTPS, and only with the account's own token.
- **The local MCP server and command expose usage numbers only**, never a token or a cookie.

### Out of scope

Malware already running under your user account can read the same Keychain items and files as Sightglass (macOS may ask your permission the first time an app reads a Keychain item it was not allowed to read). Sightglass does not try to defend against it.
