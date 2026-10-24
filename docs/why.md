# Why Sightglass

## The problem

People who work with AI tools all day often hold several subscriptions: a personal Claude account and a team seat, a second team for another company, ChatGPT for one thing, Gemini or Grok for another. Each subscription has its own limits: a five hour session window, a weekly window, sometimes a weekly window per model. Hitting one in the middle of a task stops the work.

The indicators built into the tools show one account at a time, without saying which one. Knowing where every account stands means opening each tool, or each settings page, one by one. And the agents that run on your behalf (Claude Code sessions, automations, coding agents) cannot see the limits at all: they find out when a request fails.

## What already exists (October 2026)

Good tools already read these limits, and Sightglass owes them a lot:

- **CodexBar** (MIT) is the most complete: a macOS menu bar app for dozens of providers, with a command that prints JSON, a guard mode for scripts and a local HTTP server.
- **ClaudeBar** (Apache 2.0) covers Claude, Gemini, Grok and Codex in the menu bar.
- **Claude Usage Tracker** (MIT) handles several Claude profiles, but switches the Claude Code credentials when you change profile.
- **Quotio** (MIT) manages several accounts per provider, as a proxy that routes your requests.
- **ccusage** (MIT) measures tokens and estimated cost from local logs: useful, but it does not know the real subscription limits.

## Why another one

Three needs are not met together by any of them:

1. **Several accounts of the same provider, side by side, each named by its email address**, taken from where the official tool already keeps them (for Claude Code, one configuration folder per account), without switching anything.
2. **Strictly read only.** Some tools refresh tokens or swap credentials. Refreshing a token rotates it and can sign the official tool out; swapping credentials can break a running session. Sightglass never writes a credential.
3. **Made for agents too.** Besides the menu bar, a local MCP server and a JSON command give agents the same numbers, so they can pick an account with room left instead of failing.

## What Sightglass is not

- Not a proxy: it never sees or routes your prompts.
- Not a cost tracker: it shows the limits of your subscriptions, not the price of API calls.
- Not a guarantee: the providers' usage endpoints are internal and undocumented. When one changes, Sightglass says the provider is unavailable rather than showing a wrong number.
