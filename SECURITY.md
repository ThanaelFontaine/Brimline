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
- **Only the providers' own hosts** are contacted, over HTTPS, and only with the account's own token. Each reader has a closed list of URLs, compared whole (host, path and query); anything else is refused before the request leaves, redirections are refused, and no cookie is sent or kept.
- **A provider is read only if you turned it on.** Claude is on, as it always was; every other provider starts off (see below).
- **The local MCP server and command expose usage numbers only**, never a token or a cookie.

### Providers are off until you turn them on

- Claude is on by default, as before. Every other provider is **off** until you turn it on in Settings, Accounts, or with `brimline providers enable <name>`. A provider that is off is not touched at all: Brimline does not look for its folder, opens none of its files, calls no `security`, makes no request. This is checked before any reader runs, and a test with fake readers counts the calls (zero).
- **"Do not read"** on an account (Settings, Accounts) means the same for one account's sign-in and numbers: its sign-in is never read (no Keychain item, no sign-in file, no request), whatever the provider, and it keeps its last numbers with their age. Brimline still lists the account's folder and reads its address and organization from `.claude.json` when it looks for accounts. Turn the box off to read it again.
- Both choices live in `settings.json` (`enabledProviders`, `unreadAccounts`). A settings file from before the providers has neither key and keeps Claude on and the rest off. `brimline providers` writes the same file; the app takes the change at its next refresh, so a provider turned off stops being read at the next attempt.
- The rules every reader follows, for the providers that come after Claude:
  - A sign-in file is opened without following a link (`O_NOFOLLOW`) and checked on the open file: a regular file, owned by you, 1 MiB at most. A file cut short (the provider's tool is rewriting it) is a passing failure to try again, never "signed out".
  - Only the few fields a reader needs are decoded; a refresh token is never decoded.
  - A token goes in a header only if it is printable text with no space or line break, and only to the reader's listed URL.
  - What a provider sends is data, never an instruction: names are kept only if they are 64 characters at most among letters, digits, `.`, `_`, `-` and the space; percentages are held between 0 and 100 (a value that is not a number is dropped); reset times must be between one day ago and 400 days ahead.
  - An answer that is not the expected one (other JSON, a page) is shown as "The provider changed its answer" and never as a number. The cache keeps a fingerprint of the keys of the last answer (SHA-256), with no value in it. `brimline status --live --shape` prints the keys and the types of an answer, never a value.
  - Nothing is ever written, renewed or moved at a provider.

### What it looks at for ChatGPT (Codex)

- When ChatGPT is on, Brimline looks for the folder `~/.codex` (and the Codex folders you added by hand in `settings.json`, `extraCodexFolders`; the `CODEX_HOME` variable is never read) and opens one file in it: `auth.json`, without following a link, checked on the open file. It reads no other file of Codex (no `config.toml`), no Keychain item (Codex keeps its Keychain item for its own program only), launches no program (not `codex`, not `codex app-server`, which would renew and rewrite Codex's sign-in) and writes nothing. A test checks that the home folder is byte for byte the same after a reading.
- Of `auth.json`, three fields are decoded: `auth_mode`, `tokens.access_token` and `tokens.account_id`. The refresh token, the id token and an API key in the file are never decoded (a test gives them values no decoder could read). The `exp` of the access token is read, without checking the signature, only so that an expired token is never sent (with a 60 second margin); it is never renewed.
- The token and the account id go only to `https://chatgpt.com/backend-api/wham/usage`, over HTTPS, and only if they are printable text with no space or line break (the account id: letters, digits and `-`, 64 characters at most). The request is a read of the usage that consumes no quota. Brimline says who it is (`User-Agent: Brimline/<version>`), never Codex.
- The address and the plan in Codex's files and in the answer are not kept. Tests plant fake tokens, a fake account id and a fake answer secret, and look for them in the cache, the settings, the JSON of the command and the MCP answers (none).

### What it looks at for Gemini

- Gemini is a sentence only: when Gemini is on, Brimline checks that `~/.gemini` exists and is a folder (one `stat`, following no file inside it). It opens and lists nothing in that folder (no `oauth_creds.json`, no settings), reads no Keychain item, makes no request and launches no program. A test with a bait token in the folder, made unreadable, checks that nothing is opened. When Gemini is off, the folder is not even checked.

### What it looks at for Grok (the Grok CLI)

- When Grok is on, Brimline looks for the folder `~/.grok` (the `GROK_HOME` and `GROK_AUTH_PATH` variables are never read) and opens one file in it: `auth.json`, without following a link, checked on the open file. It reads no other file of the CLI (no `config.toml`, no `mcp_credentials.json`), no Keychain item, launches no program (not `grok`) and writes nothing. A test checks that the home folder is byte for byte the same after a reading.
- `auth.json` maps a scope to a sign-in. Brimline looks at the names of the scopes and decodes only the entries of an xAI account (`https://auth.x.ai`, then `::` and the client id), and of them four fields: `key`, `user_id`, `expires_at` and `create_time`. The refresh token, the address, the team, the API key (`xai::api_key`) and the sign-in of any other issuer are never decoded, nor sent (a test gives them values no decoder could read). The expiry is only used so that an expired token is never sent (with a 60 second margin); it is never renewed.
- The session token and the user id go only to `https://cli-chat-proxy.grok.com/v1/billing?format=credits`, over HTTPS, and only if they are printable text with no space or line break (the user id: letters, digits and `-`, 64 characters at most). The request is a read of the billing that consumes no credit. It carries the header `X-XAI-Token-Auth: xai-grok-cli` that the Grok CLI sends so that the proxy treats the token as a user token; Brimline says who it is (`User-Agent: Brimline/<version>`), never the Grok CLI.
- The address, the team and the plan in the CLI's files and in the answer are not kept. Tests plant fake tokens, a fake user id, a fake address and a fake answer secret, and look for them in the cache, the settings, the JSON of the command and the MCP answers (none).

### What it looks at for Cursor

- When Cursor is on, Brimline checks (one `lstat`, following no link) that `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb` is a regular file of yours. It looks at no other file of Cursor (no `storage.json`, no extension data, not the CLI's folder), reads no Keychain item (never "Cursor Safe Storage", the key that opens everything Cursor encrypts) and launches no program. No request is made in this version.
- It first reads the 20 first bytes of that file (the SQLite header, through a descriptor opened read-only that follows no link) to learn the journal mode, and creates nothing in Cursor's folder in either mode. In the classic journal mode (the one VS Code uses, and so, most likely, Cursor), a read-only opening creates no file, so the database is read whether Cursor runs or not, unless a `-journal` file is next to it (a write in progress): then nothing is opened and the answer is "busy". In WAL mode, the database is opened only while Cursor is running: both `state.vscdb-wal` and `state.vscdb-shm` must already exist, as regular files of yours, otherwise nothing is opened (SQLite could create them, which would be a write in Cursor's folder). The opening is `SQLITE_OPEN_READONLY` on a `mode=ro` URI, refuses a link as the file, and is never `immutable=1` (it would ignore a token still in the log or in a journal) nor a copy on disk. SQLite touches the shared-memory index `-shm` as any WAL reader does; tests check, in both modes, that the database and its log do not change by a byte or a date, and that no file appears.
- One prepared query: `SELECT value FROM ItemTable WHERE key = ?` with the key `cursorAuth/accessToken`. The value is only classified (an encrypted value, a plain token shaped like a JWT, nothing, or something else) and dropped: it is not kept, not sent, not written in the cache, the settings, the answers to agents or the logs, and nothing in it is decoded in this version. A value that Cursor encrypted is never decrypted. Tests plant a fake token, a fake refresh token and a fake address in the database and look for them in every output (none).

### How it reads Claude Code sign-ins

- Claude Code keeps each sign-in in the macOS Keychain, one generic password per configuration folder. Brimline computes the item's exact service name from the folder (`Claude Code-credentials`, or `Claude Code-credentials-` followed by the first 8 hex digits of the SHA-256 of the folder's absolute path) and asks for that one item. It never lists or searches the Keychain.
- The read goes through Apple's `/usr/bin/security find-generic-password -s <service> -w`, whose output is piped straight into the app's decoder: it is never printed, logged or stored. Only `accessToken` and `expiresAt` are decoded; the refresh token is never decoded, stored or used.
- If `security` does not answer within 60 seconds, it is stopped and the account is shown as unavailable.
- Why the `security` tool rather than the Keychain framework: in our tests, reading Claude Code's items with that tool showed no prompt, which suggests it is already allowed to read them (to be confirmed on other setups). An app reading them directly is not on their access list, so macOS would ask for each item, and ask again after each rebuild of an app signed ad hoc, which would train people to click "Always Allow" without reading.
- The token is sent only to `https://api.anthropic.com` (the usage endpoint Claude Code uses), over HTTPS, with an ephemeral session that keeps no cookie and no cache. Requests time out after 15 seconds. Each request carries the token (`Authorization: Bearer`), the header `anthropic-beta: oauth-2025-04-20`, and `User-Agent: Brimline/<version> (+https://github.com/ThanaelFontaine/Brimline)`: Brimline says who it is and never presents itself as Claude Code.
- An expired token is reported as "Session expired": Brimline does not ask for usage with it and does not renew it.

### What it writes

- `~/Library/Application Support/Brimline/usage.json` (the last numbers, statuses, addresses and folders of the accounts, and a fingerprint of the keys of each answer) and `settings.json` (preferences, the providers that are on, the accounts marked "Do not read"), in a folder readable by your user only (`0700`, files `0600`). The cache type has no field for a token, and a test writes a cache from fake tokens and checks none of them is in the file.
- `~/Library/LaunchAgents/eu.thanaelfontaine.brimline.plist`, only when you turn on "Open at login"; it opens the app and nothing else.
- Nothing in the Keychain, nothing in the Claude Code folders.
- Once, at its first launch, it reads `settings.json` and `usage.json` from the old folder in `~/Library/Application Support` (the one named after the old app) and copies them to the Brimline folder: a real folder owned by you, files opened without following a link, regular, owned by you, 1 MiB at most, decoded into the same types as above and written again (so no token can come over), never over an existing file. The old folder is not changed.

### Anthropic's terms

Anthropic's documentation restricts the use of Claude.ai OAuth tokens by third-party applications ([Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance)). Brimline reads the user's own token on the user's own Mac, read only, never writes or renews it, sends it only to Anthropic and announces itself under its own name. It is not an official or endorsed Anthropic product, and we make no claim that this use is permitted: each user judges for their plan. The same page says Anthropic may enforce these restrictions without prior notice, which is a risk for the account that is read. See the README.

### Out of scope

Malware already running under your user account can read the same Keychain items and files as Brimline (macOS may ask your permission the first time an app reads a Keychain item it was not allowed to read). Brimline does not try to defend against it.
