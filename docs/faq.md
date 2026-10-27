# FAQ

## Which providers does Brimline support?

Five (Claude since v0.1.0, the four others each tried on a real account on 27 October 2026), **on the plan named in the [table of the README](../README.md#providers) and nowhere else**:

- **Claude**, through the Claude Code sign-ins (the Keychain).
- **ChatGPT**, through Codex: the sign-in Codex keeps in `~/.codex/auth.json` (the 5 hour session and the week that Codex shows with `/status`). Tried on ChatGPT Free.
- **Gemini**, through Google's Antigravity CLI: Brimline launches its official command `agy --print /usage` and shows each group of models over 5 hours and over the week (it says where the limits are when Antigravity is not installed). Only the build verified on 27/10/2026, Antigravity CLI 1.4.8, is launched. Tried on a Google account (`agy` does not say the plan).
- **Grok**, through the sign-in of the Grok CLI. Tried on a free account, for which xAI returns **no credit limit**: Brimline says so and shows no percentage. What a paid account gives was not tried.
- **Cursor**, through the sign-in its app keeps (the cycle of your plan, when Cursor stores that sign-in in plain text; when it protects it, Brimline says where to see the usage). Tried on Cursor Free.

ChatGPT, Gemini, Grok and Cursor are off until you turn them on. What is read for each, and what each try showed: [providers](providers.md).

## Why does Grok show no percentage?

Because xAI sent none. On the free account Brimline was tried with, the answer of the Grok CLI's own billing request has a weekly period and zero amounts, but no credit limit and no percentage: Brimline shows "xAI returns no credit limit for this account." rather than a 0 % that would be invented. There is no xAI page or command to compare with (`grok usage` only gives the tokens of one session). What a paid account (SuperGrok, X Premium Plus) answers was not tried, so nothing is claimed for it.

## What does "read and checked" mean, and who checked?

That the real answer of a real account was read on 27 October 2026, that its shape matches the test data, that ten reads in a row agreed, that nothing was written or renewed at the provider and that turning the provider off stopped every read. It is said per provider and per plan, never for a plan that was not tried. Two comparisons with the provider's own usage page are still pending (ChatGPT through Codex, and Cursor), and Gemini's percentage was seen at 100 % remaining only: [providers](providers.md) says so in each section.

## Where do the numbers come from?

From the same place the official tool gets them. For Claude, the endpoint Claude Code itself uses to show your limits, `https://api.anthropic.com/api/oauth/usage`, asked with each account's own sign-in. For ChatGPT, Grok and Cursor, one request to the address their own tool or dashboard uses; for Gemini, the text of Google's command `agy --print /usage`. As far as we know (October 2026), none of these requests is documented by its provider (Google documents the `/usage` command, not the format of its text), so they can change without notice. When an answer stops making sense, Brimline shows the account as **Unavailable** ("answer not understood") or as a provider that "changed its answer", instead of a wrong number. The exact addresses are in [providers](providers.md) and [SECURITY.md](../SECURITY.md).

## Are the percentages what is used, or what is left?

What is used, as the provider reports it, so you can compare with what its own tool shows. (Antigravity prints what *remains*, "Remaining 82 %"; Brimline shows what is used, 18 %, so that every gauge fills the same way.) The gauge fills up toward the limit; the empty part is what you have left. Each gauge also writes its percentage in text: color is never the only signal.

## Why does an account say "Session expired"?

Claude Code's access tokens last a limited time and Claude Code renews them when you use it. Brimline never renews a token (renewing can rotate the sign-in and log the official tool out), so an account you have not used for a while shows "Session expired" with its last numbers in grey. Open Claude Code with that account and it is back at the next refresh. The same goes for the others: "Open Codex to refresh the sign-in.", "Open the Grok CLI to refresh the sign-in.", "Open Cursor to refresh the sign-in.", "Open Antigravity to refresh the sign-in.".

## Does Brimline slow down or rate limit my accounts?

It asks once per account every 5 minutes by default (2, 5, 10 or 15 in the settings), plus when you click Refresh. Gemini is slower on purpose: launching Antigravity's command at most once every 15 minutes, whatever the interval. After a failure it waits longer each time (2, 4, 8, 16, 32 then 60 minutes), and it follows Anthropic's `Retry-After` when there is one.

## Does anything leave my Mac?

Only the usage requests, sent to each provider you turned on with that account's own token and the header `User-Agent: Brimline/<version>`. For Cursor the request carries the session cookie of cursor.com, which is worth a full web session: it goes to that one address and nowhere else (see [SECURITY.md](../SECURITY.md)). For Gemini, Brimline sends nothing itself: it launches Google's program, which does what it does with Google. There is no Brimline server, no telemetry, no analytics. The cache, the settings and the command's output stay on your Mac and never contain a token.

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

## Can Brimline hide the icons of Claude, ChatGPT and Cursor from the menu bar?

No, and it says so rather than pretend. macOS has no public way for an app to hide another app's menu bar icon (an app can only manage its own). The tools that do it (Bartender, Ice) use non-public methods that need Accessibility, and sometimes Screen Recording, and they are broken or unstable on macOS 27. A usage tracker should not ask for those permissions, so Brimline asks for none. **Settings, Menu Bar** gives you the way out instead: for each of the three apps installed on your Mac, the name of its own switch ("Turn off “Menu bar”" in Claude, "Show in menu bar" in ChatGPT, "Menu Bar Icon" in Cursor), where it is, and a button that opens the app; a button that opens System Settings on Menu Bar (macOS has its own "Allow in the Menu Bar" switch for each app); and the Command-drag gesture, which works for the apps that allow it. The names of the switches are the ones read in the apps on 27 October 2026 and can change with their versions.

## Why is there no Dock icon?

Brimline is a menu bar app. To open the settings, use **Settings…** in its window, or open the app again from Finder or Spotlight.

## Why isn't there a downloadable app?

Distributing a Mac app outside the App Store without warnings needs an Apple Developer ID and notarization. Brimline is built on your Mac instead, in a few minutes: see [install.md](install.md).

## Is Brimline's code public?

Its source code is public, under the [PolyForm Shield 1.0.0](../LICENSE) license: you can use it, modify it and share it, at work too; you cannot offer a product that competes with it. It is not open source in the OSI sense.

## Is this allowed by OpenAI, Google, xAI and Cursor?

We have not established it, and we do not claim it. Each provider has its own terms, and OpenAI's page on Codex, for one, does not allow the use of `codex app-server` for a commercial service (which is why Brimline does not use it). Brimline reads your own sign-in on your own Mac, read only, and says who it is, but read the terms of your plan and judge for yourself. The risk, if any, is on the account Brimline reads.

## Is this allowed by Anthropic?

We do not know, and we do not claim it is. Anthropic's documentation ([Authentication and credential use](https://code.claude.com/docs/en/legal-and-compliance)) says OAuth sign-ins are meant for Claude Code and Anthropic's own apps, and that third-party developers may not collect, store or intermediate Claude.ai credentials or session tokens. Brimline reads your own token on your own Mac, read only, never writes, renews or copies it, sends it only to Anthropic to ask for your own usage, and announces itself as Brimline. It is not an official or endorsed product. Read the terms of your plan and judge for yourself. The same page says Anthropic may enforce these restrictions without prior notice: the risk, if any, is on the account Brimline reads.

## How do I report a bug or a security problem?

A bug: open an issue (never paste a token or private data). A security problem: see [SECURITY.md](../SECURITY.md), privately.
