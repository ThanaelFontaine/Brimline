# Security policy

Brimline reads the sign-in tokens of your AI tools (for Claude Code, from the macOS Keychain). Security reports are taken seriously and handled privately.

## Reporting a vulnerability

**Please do not open a public issue for a security problem.**

Use GitHub's private vulnerability reporting: on the repository page, **Security** tab, **Report a vulnerability**. If the button is not there, contact the maintainer privately through the contact details on their GitHub profile.

Please include what an attacker can do and under which conditions, steps to reproduce, and the affected version and macOS version. Never send real tokens or account data in a report: use fictitious data.

What to expect: an acknowledgement within 7 days, an assessment and a plan, then a fix released as a new version with a changelog entry. Brimline is maintained on a volunteer basis, so timelines are best effort.

## Supported versions

Only the latest released version receives security fixes.

## Threat model

### What Brimline is

A macOS app that runs under your user account. It reads the tokens your AI tools already store, asks each provider for the usage of each account, and shows the result in the menu bar, in a command with JSON output and in a local MCP server. There is no Brimline server and no telemetry.

### What it promises

- **Read only.** Tokens are read, never refreshed, rewritten, moved or copied to another store. Refreshing a token can rotate it, which may sign the official tool out: Brimline never does it.
- **Tokens stay in memory**, only for the request that needs them. They are never written to a log, a cache file, the JSON output or the MCP answers.
- **Only the providers' own hosts** are contacted, over HTTPS, and only with the account's own token.
- **The local MCP server and command expose usage numbers only**, never a token or a cookie.

### How it reads Claude Code sign-ins

- Claude Code keeps each sign-in in the macOS Keychain, one generic password per configuration folder. Brimline computes the item's exact service name from the folder (`Claude Code-credentials`, or `Claude Code-credentials-` followed by the first 8 hex digits of the SHA-256 of the folder's absolute path) and asks for that one item. It never lists or searches the Keychain.
- The read goes through Apple's `/usr/bin/security find-generic-password -s <service> -w`, whose output is piped straight into the app's decoder: it is never printed, logged or stored. Only `accessToken` and `expiresAt` are decoded; the refresh token is never decoded, stored or used.
- If `security` does not answer within 60 seconds, it is stopped and the account is shown as unavailable.
- Why the `security` tool rather than the Keychain framework: in our tests, reading Claude Code's items with that tool showed no prompt, which suggests it is already allowed to read them (to be confirmed on other setups). An app reading them directly is not on their access list, so macOS would ask for each item, and ask again after each rebuild of an app signed ad hoc, which would train people to click "Always Allow" without reading.
- The token is sent only to `https://api.anthropic.com` (the usage endpoint Claude Code uses), over HTTPS, with an ephemeral session that keeps no cookie and no cache. Requests time out after 15 seconds. Each request carries the token (`Authorization: Bearer`), the header `anthropic-beta: oauth-2025-04-20`, and `User-Agent: Brimline/<version> (+https://github.com/ThanaelFontaine/Brimline)`: Brimline says who it is and never presents itself as Claude Code.
- An expired token is reported as "Session expired": Brimline does not ask for usage with it and does not renew it.

### What it writes

- `~/Library/Application Support/Brimline/usage.json` (the last numbers, statuses, addresses and folders of the accounts) and `settings.json` (preferences), in a folder readable by your user only (`0700`, files `0600`). The cache type has no field for a token, and a test writes a cache from fake tokens and checks none of them is in the file.
- `~/Library/LaunchAgents/eu.thanaelfontaine.brimline.plist`, only when you turn on "Open at login"; it opens the app and nothing else.
- Nothing in the Keychain, nothing in the Claude Code folders.
- Once, at its first launch, it reads `settings.json` and `usage.json` from the old folder in `~/Library/Application Support` (the one named after the old app) and copies them to the Brimline folder: a real folder owned by you, files opened without following a link, regular, owned by you, 1 MiB at most, decoded into the same types as above and written again (so no token can come over), never over an existing file. The old folder is not changed.

### Anthropic's terms

Anthropic's documentation restricts the use of Claude.ai OAuth tokens by third-party applications ([Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance)). Brimline reads the user's own token on the user's own Mac, read only, never writes or renews it, sends it only to Anthropic and announces itself under its own name. It is not an official or endorsed Anthropic product, and we make no claim that this use is permitted: each user judges for their plan. The same page says Anthropic may enforce these restrictions without prior notice, which is a risk for the account that is read. See the README.

### Out of scope

Malware already running under your user account can read the same Keychain items and files as Brimline (macOS may ask your permission the first time an app reads a Keychain item it was not allowed to read). Brimline does not try to defend against it.
