# FAQ

## Which providers does Brimline support?

Claude, through Claude Code sign-ins; ChatGPT, through the Codex sign-in (the 5 hour session and the week that Codex shows with `/status`); Grok, through the sign-in of the Grok CLI (the credits of the current period); and Gemini through Google's Antigravity CLI (Brimline launches its official command `agy --print /usage`, and says where the limits are when Antigravity is not installed; it is not launched until it has been tried on a real account, see [providers](providers.md)); and Cursor, through the sign-in its app keeps (the cycle of your plan, when Cursor stores that sign-in in plain text; when it protects it, Brimline says where to see the usage). ChatGPT, Gemini, Grok and Cursor are off until you turn them on. Each provider is a small plugin; the ones that read limits use the sign-in their official tool already keeps.

## Where do the numbers come from?

From the endpoint Claude Code itself uses to show your limits: `https://api.anthropic.com/api/oauth/usage`, asked with each account's own sign-in. As far as we know (October 2026), Anthropic does not document it. It can change without notice. When its answer stops making sense, Brimline shows the account as **Unavailable** ("answer not understood") instead of a wrong number.

## Are the percentages what is used, or what is left?

What is used, as Anthropic reports it, so you can compare with what Claude shows. The gauge fills up toward the limit; the empty part is what you have left. Each gauge also writes its percentage in text: color is never the only signal.

## Why does an account say "Session expired"?

Claude Code's access tokens last a limited time and Claude Code renews them when you use it. Brimline never renews a token (renewing can rotate the sign-in and log the official tool out), so an account you have not used for a while shows "Session expired" with its last numbers in grey. Open Claude Code with that account and it is back at the next refresh.

## Does Brimline slow down or rate limit my accounts?

It asks once per account every 5 minutes by default (2, 5, 10 or 15 in the settings), plus when you click Refresh. After a failure it waits longer each time (2, 4, 8, 16, 32 then 60 minutes), and it follows Anthropic's `Retry-After` when there is one.

## Does anything leave my Mac?

Only the usage requests, sent to Anthropic with each account's own token and the header `User-Agent: Brimline/<version>`. There is no Brimline server, no telemetry, no analytics. The cache, the settings and the command's output stay on your Mac and never contain a token.

## What exactly is stored on disk?

In `~/Library/Application Support/Brimline/`:

- `usage.json`: the last numbers of each account (percentages, reset times, status, the account's address and folder). No token, ever: the type that is written has no field for one, and a test checks the file.
- `settings.json`: your preferences (refresh interval, hidden accounts, labels, folders added by hand, the providers that are on, the accounts marked "Don't read this account").

Both are readable by your user only.

## My account is not listed

Brimline finds `~/.claude` and every `~/.claude-*` folder that contains a `.claude.json`. If your folder has another name, add it in **Settings, Accounts, Add a Claude Code folder…**. If it is listed as **Not signed in**, run Claude Code with that folder and sign in. See [accounts.md](accounts.md).

## I signed in over SSH and Brimline says "Not signed in"

When the Keychain is locked (for example in an SSH session), Claude Code keeps the sign-in in a `.credentials.json` file inside the folder instead ([Claude Code documentation](https://code.claude.com/docs/en/authentication#credential-management)). Brimline v0.1 reads the Keychain only. Claude Code's documentation explains how to move the sign-in back to the Keychain ([recovery steps](https://code.claude.com/docs/en/troubleshoot-install#not-logged-in-or-token-expired)).

## Can my agents use it?

Yes: a command with JSON output and a local MCP server, both reading the app's cache. See [agents.md](agents.md).

## Why is there no Dock icon?

Brimline is a menu bar app. To open the settings, use **Settings…** in its window, or open the app again from Finder or Spotlight.

## Why isn't there a downloadable app?

Distributing a Mac app outside the App Store without warnings needs an Apple Developer ID and notarization. Brimline is built on your Mac instead, in a few minutes: see [install.md](install.md).

## Is Brimline's code public?

Its source code is public, under the [PolyForm Shield 1.0.0](../LICENSE) license: you can use it, modify it and share it, at work too; you cannot offer a product that competes with it. It is not open source in the OSI sense.

## Is this allowed by Anthropic?

We do not know, and we do not claim it is. Anthropic's documentation ([Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance)) says OAuth sign-ins are meant for Claude Code and Anthropic's own apps, and that third-party developers may not collect, store or intermediate Claude.ai credentials or session tokens. Brimline reads your own token on your own Mac, read only, never writes, renews or copies it, sends it only to Anthropic to ask for your own usage, and announces itself as Brimline. It is not an official or endorsed product. Read the terms of your plan and judge for yourself. The same page says Anthropic may enforce these restrictions without prior notice: the risk, if any, is on the account Brimline reads.

## How do I report a bug or a security problem?

A bug: open an issue (never paste a token or private data). A security problem: see [SECURITY.md](../SECURITY.md), privately.
