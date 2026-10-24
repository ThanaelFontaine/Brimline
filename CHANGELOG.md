# Changelog

All notable changes to Sightglass are documented here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses [Semantic Versioning](https://semver.org/).

The version lives in the `VERSION` file. `0.0.0` is the development version: nothing is released. Every other version gets its tag and its GitHub release from the CI, with the notes of its section below.

## [Unreleased]

### Added

- Repository set up: license (PolyForm Shield 1.0.0), contributing guide, security policy, text checks and the release workflow.
- **Menu bar app** (macOS 14 or later): a level glyph that follows the account closest to a limit, with an optional percentage next to it. Its window shows one card per Claude account, named by its email address (or a label you choose), with the five hour session, the week across all models and the week per model, each with its percentage in text and its reset time ("resets in 2 h 10 (14:30)"). Plans without a weekly limit across all models say so in a sentence.
- **Every state in words**: data getting old ("Data from ... ago"), session expired (last known values greyed, nothing renewed), sign-in refused, provider unavailable (reason and time of the next try), not signed in, limit reached.
- **Account discovery**: `~/.claude` and every `~/.claude-*` folder with a `.claude.json`, plus folders added by hand. Each sign-in is read from the macOS Keychain with `/usr/bin/security`, by its exact service name (the hash of the folder's path, as Claude Code names it); nothing is enumerated, renewed or written.
- **Refresh** every 2, 5, 10 or 15 minutes (5 by default) and on demand, with a growing wait after a failure (2, 4, 8, 16, 32 then 60 minutes) and the provider's `Retry-After` honored.
- **Settings window** with four tabs: Accounts (show or hide, label, add or remove a folder, search again, a link to the guide), General (refresh interval, percentage in the menu bar, open at login through a LaunchAgent), Agents (ready to copy command, MCP snippets and cache path), About. It opens in front, from the window or by opening the app again.
- **English and French**, following the language of the Mac (`SIGHTGLASS_LANG` overrides it).
- **`sightglass` command**: `status [--json] [--live]`, `accounts [--json]`, `mcp`, `--version`. The JSON says the age of every number and writes every key, `null` when unknown.
- **Local MCP server** (`sightglass mcp`, stdio, protocol 2025-06-18, also 2025-03-26 and 2024-11-05): tools `list_accounts`, `get_usage` and `best_account` (the account with the most room left, for a window and optionally a model), with text and `structuredContent` answers. The command and the server read the app's cache only and never see a token.
- **Cache and settings** in `~/Library/Application Support/Sightglass/`, readable by your user only; the cache type has no field for a token, and a test checks the written file.
- **Design**: colors, glyph and app icon (`design/`), light and dark mode, never color alone.
- **Scripts**: `scripts/build_app.sh` builds and signs `build/Sightglass.app` ad hoc with the Command Line Tools alone (the command ships inside, in `Contents/Helpers`); `scripts/install.sh` copies it to `~/Applications`, links `~/.local/bin/sightglass` and opens it.
- **Screenshots** rendered from fictitious data (`swift run sightglass-snapshots`) in `docs/images/`.
- **Documentation**: linking accounts (English and French), installing, agents (command, JSON format, MCP), FAQ; README updated.
- **Tests**: Swift Testing suites for discovery, Keychain service names, credential and usage parsing (anonymized real answers), service states and backoff, cache, ranking, time formatting and the MCP server. The CI now also runs `swift build`, `swift test` and `scripts/build_app.sh`.

### Fixed

- The text check test now runs with a temporary `HOME` while keeping the rest of the environment, so it passes on any Mac.
