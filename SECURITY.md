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

### How it reads Claude Code sign-ins

- Claude Code keeps each sign-in in the macOS Keychain, one generic password per configuration folder. Sightglass computes the item's exact service name from the folder (`Claude Code-credentials`, or `Claude Code-credentials-` followed by the first 8 hex digits of the SHA-256 of the folder's absolute path) and asks for that one item. It never lists or searches the Keychain.
- The read goes through Apple's `/usr/bin/security find-generic-password -s <service> -w`, whose output is piped straight into the app's decoder: it is never printed, logged or stored. Only `accessToken` and `expiresAt` are decoded; the refresh token is never read into a variable and never used.
- Why the `security` tool rather than the Keychain framework: in our tests, reading Claude Code's items with that tool showed no prompt, which suggests it is already allowed to read them (to be confirmed on other setups). An app reading them directly is not on their access list, so macOS would ask for each item, and ask again after each rebuild of an app signed ad hoc, which would train people to click "Always Allow" without reading.
- The token is sent only to `https://api.anthropic.com` (the usage endpoint Claude Code uses), over HTTPS, with an ephemeral session that keeps no cookie and no cache. Requests time out after 15 seconds.
- An expired token is reported as "Session expired": Sightglass does not ask for usage with it and does not renew it.

### What it writes

- `~/Library/Application Support/Sightglass/usage.json` (the last numbers, statuses, addresses and folders of the accounts) and `settings.json` (preferences), in a folder readable by your user only (`0700`, files `0600`). The cache type has no field for a token, and a test writes a cache from fake tokens and checks none of them is in the file.
- `~/Library/LaunchAgents/eu.thanaelfontaine.sightglass.plist`, only when you turn on "Open at login"; it opens the app and nothing else.
- Nothing in the Keychain, nothing in the Claude Code folders.

### Out of scope

Malware already running under your user account can read the same Keychain items and files as Sightglass (macOS may ask your permission the first time an app reads a Keychain item it was not allowed to read). Sightglass does not try to defend against it.
