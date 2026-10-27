# Brimline for agents

Brimline gives your agents the same numbers as the menu bar. It holds no AI and is not a prompt: it is a command and a local MCP server that answer with numbers when an agent asks. It never switches accounts.

Your agents can pick an account that still has room instead of failing in the middle of a task. Two ways: a command with JSON output, and a local MCP server.

Both read the **cache written by the Brimline app** (`~/Library/Application Support/Brimline/usage.json`), refreshed every 5 minutes by default. They never read the Keychain and never see a token, except `brimline status --live` (below), which reads like the app. Every answer with numbers says how old they are. Nothing here writes to your Claude Code folders or to the Keychain, and nothing starts or stops an agent.

## Is it a prompt?

No. Brimline holds no AI model. When your agent starts, its client (Claude Code, Codex) reads a short notice from the server: the names and descriptions of its three tools, and one sentence of guidance. That text helps the model know when to call a tool; the answers themselves are plain numbers in JSON.

## Where the command is

The command is inside the app: `Brimline.app/Contents/Helpers/brimline`. `scripts/install.sh` links it to `~/.local/bin/brimline`. **Settings, Agents** shows its exact path, with ready to copy snippets.

![Agents settings](images/settings-agents-light.png)

## The command

```text
brimline status [--json] [--live]   Usage of each account
brimline accounts [--json]          Accounts found on this Mac (no Keychain read)
brimline mcp                        Local MCP server over stdio
brimline --version
```

- `status` reads the cache, even when the app is not running (check `age_seconds`). Only when there is no cache at all does it say so and exit with code 2.
- `status --live` reads every account now, with the same code as the app: it reads the Keychain through `/usr/bin/security` and asks Anthropic. It does not write the cache (the app stays the only writer).
- Exit codes: 0 on success, 2 when there is no cache yet, 64 for a wrong command or option.

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
          "model" : null,
          "percent" : 34,
          "resets_at" : "2026-10-26T13:30:00Z",
          "resets_in_seconds" : 7800
        },
        {
          "current_percent" : 0,
          "kind" : "weekly_model",
          "model" : "Fable",
          "percent" : 0,
          "resets_at" : "2026-10-27T12:00:00Z",
          "resets_in_seconds" : 88800
        }
      ],
      "message" : null,
      "no_global_weekly_limit" : true,
      "organization" : "Example Team",
      "provider" : "claude",
      "stale" : false,
      "status" : "ok"
    }
  ],
  "age_seconds" : 74,
  "generated_at" : "2026-10-26T11:18:46Z",
  "schema_version" : 1,
  "source" : "cache"
}
```

Fields:

| Field | Meaning |
|---|---|
| `kind` | `session` (five hour window), `weekly` (all models), `weekly_model` (one model, named in `model`) |
| `percent` | Share used, 0 to 100, as Anthropic last reported it |
| `current_percent` | The share that applies now: 0 once `resets_at` has passed |
| `status` | `ok`, `expired` (token expired, numbers are the last known ones), `reconnect` (sign-in refused), `unavailable`, `signed_out`, `pending` |
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

Codex declares an MCP server in one line, or in `~/.codex/config.toml`, with an absolute path. Through Brimline, Codex reads your Claude accounts: Brimline reads Claude accounts only today.

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
| `list_accounts` | none | Each account: id, provider, email, organization, label, folder, hidden, status |
| `get_usage` | `account` (optional: an address or an account id), `include_hidden` (optional, default false) | The same JSON as `brimline status --json` |
| `best_account` | `window` (`any`, `session` or `week`; default `any`), `model` (optional, for example `Fable`) | `best` (the account with the most room left), `ranking` (all, best first), each with `headroom_percent` and the `binding_limit` that sets it |

How `best_account` ranks: for each account with numbers, it takes the limits that apply (`any`: the session, the week across all models, and the model's week when `model` is given; `session`: the session only; `week`: the weekly limits only), keeps the tightest one, and sorts by room left. Hidden accounts, accounts never read, and accounts whose sign-in was refused or is missing are left out; an account whose token merely expired stays in, since Claude Code renews it when used. Unavailable accounts come after all the others, since their numbers may be old. An account that has none of the limits asked for (a team seat without a weekly limit, asked for `week`) is judged on its tightest limit, so a full session never reads as 100% room (the limit that decides can then be the session). Ties go to the freshest numbers. A window whose reset time has passed counts as empty.

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
      "window": "week",
      "model": null,
      "age_seconds": 42,
      "best": {
        "email": "your@claude.ai",
        "folder": "<home>/.claude",
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
- Treat `unavailable` as "unknown", not as "free".
- The numbers come from an undocumented Anthropic endpoint (see the [FAQ](faq.md)): use them to choose, not as a guarantee.
