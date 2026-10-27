# Brimline for agents

Brimline gives your agents the same numbers as the menu bar. It holds no AI and is not a prompt: it is a command and a local MCP server that answer with numbers when an agent asks. It never switches accounts.

Your agents can pick an account that still has room instead of failing in the middle of a task. Two ways: a command with JSON output, and a local MCP server.

Both read the **cache written by the Brimline app** (`~/Library/Application Support/Brimline/usage.json`), refreshed every 5 minutes by default. They never read the Keychain and never see a token, except `brimline status --live` (below), which reads like the app. Every answer with numbers says how old they are. Nothing here writes to your Claude Code folders or to the Keychain, and nothing starts or stops an agent.

**Cache version 2.** With the providers, the cache changed shape (limits of more kinds, a `source` for each account). A cache written by an earlier version is not read: the app writes a new one at its first refresh, and a `brimline mcp` that was already running answers "No usage data yet" until it is restarted (restart your agent's MCP server, or the agent).

## Is it a prompt?

No. Brimline holds no AI model. When your agent starts, its client (Claude Code, Codex) reads a short notice from the server: the names and descriptions of its three tools, and one sentence of guidance. That text helps the model know when to call a tool; the answers themselves are plain numbers in JSON.

## Where the command is

The command is inside the app: `Brimline.app/Contents/Helpers/brimline`. `scripts/install.sh` links it to `~/.local/bin/brimline`. **Settings, Agents** shows its exact path, with ready to copy snippets.

![Agents settings](images/settings-agents-light.png)

## The command

```text
brimline status [--json] [--live] [--provider <name>]   Usage of each account
brimline status --live --shape [--provider <name>]      Shape of the provider's answer (keys and types)
brimline accounts [--json] [--provider <name>]          Accounts found on this Mac (no Keychain read)
brimline providers [--json]                             The providers and whether each is on
brimline providers enable|disable <name>                Turn a provider on or off
brimline mcp                                            Local MCP server over stdio
brimline --version
```

- `status` reads the cache, even when the app is not running (check `age_seconds`). Only when there is no cache at all does it say so and exit with code 2.
- `status --live` reads every account of the providers that are on, now, with the same code as the app: it reads the Keychain through `/usr/bin/security` and asks Anthropic. It does not write the cache (the app stays the only writer).
- `--provider <name>` (`claude`, `chatgpt`, `gemini`, `grok` or `cursor`) limits `status` and `accounts` to one provider. If that provider is off, the answer is empty and a line on the standard error says how to turn it on.
- `status --live --shape` prints, for each provider asked, the **shape** of its last answer: every key and the type of its value (`"string"`, `"number"`, `"bool"`, `"null"`), never a value. It is for checking a format when a provider changes it; it replaces `--json` and needs `--live`.
- `providers` lists the providers (on, off, or "not available yet" when this version has no reader for it); `providers enable <name>` and `providers disable <name>` change the setting file, and the app takes it at its next refresh. Claude is on by default, every other provider is **off until it is turned on**: a provider that is off is not touched at all.
- There is no `brimline best` command: agents choose an account with the MCP tool `best_account` and its `provider` argument.
- Exit codes: 0 on success, 2 when there is no cache yet (or no answer to show with `--shape`), 64 for a wrong command or option.

### `brimline status --json`

```json
{
  "accounts" : [
    {
      "age_seconds" : 74,
      "email" : "your@claude.ai",
      "fetched_at" : "2026-10-26T11:18:46Z",
      "folder" : "<home>/.claude-work",
      "hidden" : false,
      "id" : "claude:<home>/.claude-work",
      "label" : null,
      "limits" : [
        {
          "current_percent" : 34,
          "kind" : "session",
          "label" : null,
          "model" : null,
          "percent" : 34,
          "resets_at" : "2026-10-26T13:30:00Z",
          "resets_in_seconds" : 7800,
          "window_seconds" : null
        },
        {
          "current_percent" : 0,
          "kind" : "model",
          "label" : null,
          "model" : "Fable",
          "percent" : 0,
          "resets_at" : "2026-10-27T12:00:00Z",
          "resets_in_seconds" : 88800,
          "window_seconds" : null
        }
      ],
      "message" : null,
      "no_global_weekly_limit" : true,
      "organization" : "Example Team",
      "provider" : "claude",
      "reason" : null,
      "source" : "~/.claude-work",
      "stale" : false,
      "status" : "ok"
    }
  ],
  "age_seconds" : 74,
  "generated_at" : "2026-10-26T11:18:46Z",
  "schema_version" : 2,
  "source" : "cache"
}
```

Fields:

| Field | Meaning |
|---|---|
| `provider` | `claude`, `chatgpt`, `gemini`, `grok` or `cursor` |
| `source` | Where the official tool keeps the account's connection, written from your home folder (`~/.claude-work`). The same field for every provider |
| `folder` | The Claude Code configuration folder, absolute. Claude accounts only (`null` for the others); `source` says the same thing |
| `kind` | `session` (five hour window), `weekly` (all models), `model` (one model or pool, named in `model`; for Claude, that model's week), `daily`, `monthly`, `period` (another window length, see `window_seconds`) |
| `window_seconds` | Length of the window in seconds when the provider says it, else `null` |
| `label` | A name for the limit when its `kind` does not say enough, else `null` (letters, digits, `.`, `_`, `-` and spaces, 64 characters at most) |
| `percent` | Share used, 0 to 100, as the provider last reported it |
| `current_percent` | The share that applies now: 0 once `resets_at` has passed |
| `status` | `ok`, `expired` (token expired, numbers are the last known ones), `reconnect` (sign-in refused), `unavailable`, `signed_out`, `pending`, `not_readable` (the provider gives no limit Brimline can read for this account), `format_changed` (the provider's answer is not one Brimline recognizes: the numbers are the last known ones) |
| `reason` | Why the account is `not_readable`: `api_key`, `keychain_or_signed_out`, `consumer_plan`, `protected_sign_in` or `no_cli`; `null` otherwise |
| `stale` | `true` when the numbers are older than two refresh intervals, or the last read failed |
| `no_global_weekly_limit` | `true` for plans without a weekly limit across all models (often team seats) |
| `age_seconds` | Age of the numbers (per account) or of the cache (top level) |

Every key is always present; a missing value is `null`. `<home>` stands for your home folder.

## The MCP server

`brimline mcp` speaks the [Model Context Protocol](https://modelcontextprotocol.io/specification/2025-06-18) over stdio (JSON-RPC 2.0, one message per line). It answers `initialize`, `ping`, `tools/list` and `tools/call`.

### Add it to Claude Code

```bash
claude mcp add --scope user brimline -- ~/.local/bin/brimline mcp
```

`--scope user` makes it available in all your projects; without it, Claude Code adds it to the current project only.

### Add it to Codex (OpenAI)

Codex declares an MCP server in one line, or in `~/.codex/config.toml`, with an absolute path. Through Brimline, Codex reads your Claude accounts: Brimline reads Claude accounts only today (the other providers come later and are off until you turn them on).

```bash
codex mcp add brimline -- ~/.local/bin/brimline mcp
```

```toml
[mcp_servers.brimline]
command = "<home>/.local/bin/brimline"
args = ["mcp"]
```

Source: [Codex documentation, MCP](https://developers.openai.com/codex/mcp) (checked on 27 October 2026).

### Or to any MCP client

```json
{
  "mcpServers": {
    "brimline": {
      "command": "<home>/.local/bin/brimline",
      "args": ["mcp"]
    }
  }
}
```

Replace `<home>` with your home folder (absolute path: configuration files do not expand `~`). **Settings, Agents** gives both snippets with your path filled in.

### Tools

All three are read only.

| Tool | Arguments | Returns |
|---|---|---|
| `list_accounts` | none | Each account: id, provider, email, organization, label, source, folder (Claude only), hidden, status, reason |
| `get_usage` | `provider` (optional: `claude`, `chatgpt`, `gemini`, `grok` or `cursor`; all providers when omitted), `account` (optional: an address or an account id), `include_hidden` (optional, default false) | The same JSON as `brimline status --json` |
| `best_account` | `provider` (default `claude`), `window` (`any`, `session`, `week`, `day`, `month` or `period`; default `any`), `model` (optional, for example `Fable`) | `provider`, `best` (the account with the most room left), `ranking` (all, best first), each with `headroom_percent` and the `binding_limit` that sets it |

`best_account` ranks the accounts of **one** provider: `claude` when you give none, so a call written before the providers answers as it did. The windows that exist depend on the provider, and asking for another one is an error, not an empty answer (for example `The window session does not exist for grok: use any or period.`):

| Provider | Windows |
|---|---|
| `claude` | `any`, `session`, `week` |
| `chatgpt` | `any`, `session`, `week`, `period` |
| `gemini` | `any`, `day` |
| `grok` | `any`, `period` |
| `cursor` | `any`, `month` |

A provider that is off in Brimline has no account in the answers: `get_usage` and `best_account` then carry a `note` that says so (the user turns it on in the settings or with `brimline providers enable <name>`; an agent does not do it for them). A provider that is on but gives no readable limit (`not_readable`) is listed by `list_accounts` and never ranked.

How `best_account` ranks: for each account with numbers, it takes the limits that apply (`any`: every limit, and the limit of the model given in `model`; `session`, `week`, `day`, `month`, `period`: the limits of that window only, plus the limit of the model given in `model` unless the window is `session`), keeps the tightest one, and sorts by room left. Hidden accounts, accounts never read, accounts that are not readable, and accounts whose sign-in was refused or is missing are left out; an account whose token merely expired stays in, since the official tool renews it when used. Unavailable accounts, and accounts whose provider changed its format, come after all the others, since their numbers may be old. An account that has none of the limits asked for (a team seat without a weekly limit, asked for `week`) is judged on its tightest limit, so a full session never reads as 100% room (the limit that decides can then be the session). Ties go to the freshest numbers. A window whose reset time has passed counts as empty.

Results come both as text (JSON) and as `structuredContent`. When the app has not written the cache yet, tools answer with `isError: true` and a sentence saying to open the app.

### Try it yourself

Your agent does exactly this. Start the app, then paste this in a terminal: it asks the server for the account with the most room this week, and prints the answer.

```bash
printf '%s\n' \
  '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"try","version":"0"}}}' \
  '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"best_account","arguments":{"window":"week"}}}' \
  | brimline mcp | tail -n 1 | python3 -m json.tool
```

The answer, shortened (the full one also lists each limit of each account):

```json
{
  "result": {
    "isError": false,
    "structuredContent": {
      "provider": "claude",
      "window": "week",
      "model": null,
      "age_seconds": 42,
      "best": {
        "email": "your@claude.ai",
        "source": "~/.claude",
        "status": "ok",
        "stale": false,
        "headroom_percent": 58,
        "binding_limit": { "kind": "weekly", "percent": 42, "resets_in_seconds": 183600 }
      },
      "ranking": [
        { "email": "your@claude.ai", "headroom_percent": 58 },
        { "email": "team@claude.ai", "headroom_percent": 12 }
      ]
    }
  }
}
```

`best` is the first of `ranking`. `headroom_percent` is the room left on the limit that decides (`binding_limit`); `age_seconds` and `stale` say whether the numbers are fresh. Your numbers and addresses will differ.

In words: you ask, "Before this long task, which of my Claude accounts has the most room this week?" The agent calls `best_account` with `window: week`, gets your@claude.ai with 58% room left on the week, resetting in about two days, and answers: "Use your@claude.ai: `claude` in its usual folder." The session you are in stays on its account; you start the next one.

### Example

```text
→ {"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"best_account","arguments":{"model":"Fable"}}}
← {"jsonrpc":"2.0","id":1,"result":{"content":[{"type":"text","text":"{ ... }"}],"structuredContent":{"best":{"email":"your@claude.ai","headroom_percent":66, ...},"ranking":[...],"window":"any","model":"Fable","age_seconds":74},"isError":false}}
```

## Good habits for agents

- Check `age_seconds` and `stale` before trusting a number.
- Treat `unavailable` and `format_changed` as "unknown", not as "free".
- Name the `provider` you want in `best_account`: the default is Claude.
- The numbers come from an undocumented Anthropic endpoint (see the [FAQ](faq.md)): use them to choose, not as a guarantee.
