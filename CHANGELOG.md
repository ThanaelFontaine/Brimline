# Changelog

All notable changes to Brimline are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

The version lives in the `VERSION` file. `0.0.0` is the development version: nothing is released. Every other version gets its tag and its GitHub release from the CI, with the notes of its section below.

## [Unreleased]

### Changed

- **Sightglass is now Brimline.** The app, the `brimline` command and the MCP server (`brimline mcp`, server name `brimline`) carry the new name everywhere: the interface in English and French, the bundle (`Brimline.app`, `eu.thanaelfontaine.brimline`), the "Open at login" LaunchAgent (`eu.thanaelfontaine.brimline.plist`), the folder `~/Library/Application Support/Brimline/`, the `User-Agent` (`Brimline/<version>`), the `BRIMLINE_LANG` variable and the repository address. There is no `sightglass` alias: the app was never published and nothing known calls the old command.
- **Why.** The name Sightglass is already carried by close software: an AI company bought by Juniper Square in April 2026, two GitHub repositories on the same ground (a Claude Code limits tool and a macOS menu bar app) and a product studio, plus trademarks in the United States. A search for Brimline found no software, repository or trademark (TMview, USPTO, WIPO). The rename came before the first public release so that nobody has to follow it later.
- **Your data comes along.** At its first launch, Brimline copies `settings.json` and `usage.json` from `~/Library/Application Support/Sightglass/`: only those two files, never over a file Brimline already has, without following a link, and without changing the old folder. Nothing is deleted.
- **`scripts/install.sh` handles the old install.** It quits the old app (by its full path), removes the old `~/.local/bin/sightglass` link when it points into the old app, turns off the old LaunchAgent (`launchctl disable`, undone by `enable`, the file stays) and writes the Brimline one, then prints the commands that move the old files to the Trash, without running them.
- **Texts, docs and screenshots follow the name.** Both READMEs (with their "Formerly Sightglass" line and the reason), the docs, the design notes and the screenshots in `docs/images/` (rendered again with `swift run brimline-snapshots`) say Brimline. The new icon and logo come in a later change.
- **The text check keeps the old name out.** `scripts/check_text.py` now refuses the old name, in a text or in a file name, outside this changelog, the dated documents, the migration code and the installer, and the lines that say "Formerly" or "Anciennement".
- **For your agents:** register the server again under the new name, `claude mcp add brimline -- ~/.local/bin/brimline mcp` (see [docs/agents.md](docs/agents.md)).

## [0.1.0] - 2026-10-25

First version, private: the repository and the site are not public yet. The full notes are in [docs/releases/v0.1.0.md](https://github.com/ThanaelFontaine/Sightglass/blob/v0.1.0/docs/releases/v0.1.0.md).

### What does not work yet

- ChatGPT, Gemini and Grok are not supported: only Claude accounts are read.
- Only the Mac mini has been used: the MacBook Pro and macOS 14 (Sonoma) are not tried yet.
- The usage endpoint is not documented by Anthropic: it may change or stop answering without notice, and Sightglass says so in words when it does.

### Added

- Repository set up: license (PolyForm Shield 1.0.0), contributing guide, security policy, text checks and the release workflow.
- **Menu bar app** (macOS 14 or later): a level glyph that follows the account closest to a limit, with an optional percentage next to it. Its window shows one card per Claude account, named by its email address (or a label you choose), with the five hour session, the week across all models and the week per model, each with its percentage in text and its reset time ("resets in 2 h 10 (14:30)"). Plans without a weekly limit across all models say so in a sentence.
- **Every state in words**: data getting old ("Data from ... ago"), session expired (last known values greyed, nothing renewed), sign-in refused, provider unavailable (reason and time of the next try), not signed in, limit reached.
- **Account discovery**: `~/.claude` and every `~/.claude-*` folder with a `.claude.json`, plus folders added by hand. Each sign-in is read from the macOS Keychain with `/usr/bin/security`, by its exact service name (the hash of the folder's path, as Claude Code names it); nothing is enumerated, renewed or written.
- **Refresh** every 2, 5, 10 or 15 minutes (5 by default) and on demand, with a growing wait after a failure (2, 4, 8, 16, 32 then 60 minutes) and the provider's `Retry-After` honored.
- **Settings window** with four tabs: Accounts (show or hide, label, add or remove a folder, search again, a link to the guide), General (refresh interval, percentage in the menu bar, open at login through a LaunchAgent), Agents (ready to copy command, MCP snippets and cache path), About. It opens in front, from the window or by opening the app again.
- **English and French**, following the language of the Mac (`SIGHTGLASS_LANG` overrides it).
- **`sightglass` command**: `status [--json] [--live]`, `accounts [--json]`, `mcp`, `--version`. The JSON says the age of every number and writes every key, `null` when unknown.
- **Local MCP server** (`sightglass mcp`, stdio, protocol 2025-06-18, also 2025-03-26 and 2024-11-05): tools `list_accounts`, `get_usage` and `best_account` (the account with the most room left, for a window and optionally a model), with text and `structuredContent` answers. The command and the server read the app's cache and never see a token; only `sightglass status --live` reads the Keychain, like the app.
- **Cache and settings** in `~/Library/Application Support/Sightglass/`, readable by your user only; the cache type has no field for a token, and a test checks the written file.
- **Design**: colors, glyph and app icon (`design/`), light and dark mode, never color alone.
- **Scripts**: `scripts/build_app.sh` builds and signs `build/Sightglass.app` ad hoc with the Command Line Tools alone (the command ships inside, in `Contents/Helpers`); `scripts/install.sh` copies it to `~/Applications`, links `~/.local/bin/sightglass` and opens it; `--login` also turns on Open at login.
- **Screenshots** rendered from fictitious data (`swift run sightglass-snapshots`) in `docs/images/`.
- **Documentation**: linking accounts (English and French), installing, agents (command, JSON format, MCP), FAQ, and an honest section on Anthropic's terms for OAuth tokens; README updated.
- **Honest User-Agent**: requests to Anthropic announce `Sightglass/<version>`, never Claude Code.
- Percentages follow the language: "72%" in English, "72 %" in French. The guide link opens the French guide when the app is in French. `best_account` puts unavailable accounts last and never gives 100% room to an account that lacks the limit asked for.
- The Keychain read is stopped after 60 seconds if `security` never answers, so refreshing never stays stuck.
- **Tests**: Swift Testing suites for discovery, Keychain service names, credential and usage parsing (anonymized real answers), service states and backoff, cache, ranking, time formatting and the MCP server. The CI now also runs `swift build`, `swift test` and `scripts/build_app.sh`.

### Security

- Hardening of what Sightglass reads and writes: redirects from the usage request are refused, its body is limited to 256 KiB, an MCP message is limited to 1 MiB per line (longer ones are dropped and answered with an error), and the cache and settings are written through a temporary file created in 0600 inside a 0700 folder.

### Fixed

- The text check test now runs with a temporary `HOME` while keeping the rest of the environment, so it passes on any Mac.
