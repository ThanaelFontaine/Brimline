# Brimline: critical journeys

The journeys to replay before each release to prove that Brimline (the macOS menu bar app, its `brimline` command and its MCP server) still builds, reads usage from every provider and shows it, without leaking a secret. Everything runs locally, on test doubles and invented data: never on real accounts, never in production.

- Verified on: 2026-10-28
- origin/main commit verified: `0eb12654d1fc81d178d4cc22cfadd383a6c6dcb4` (version 0.1.0)
- Environment: macOS 27.0.1 on Apple silicon, Swift with the Command Line Tools only (no Xcode).
- J1 to J5 are the steps of `.github/workflows/checks.yml`; their result of the day is the one of the full local run on origin/main of the same day (the CI run on that commit was green). J6 to J9 were run on this commit.

## Journeys

### J1: text rules

- Proves: no em or en dash, no personal data (home paths, personal addresses) and no old product name in tracked text files.
- How: `python3 scripts/check_text.py`
- Expected: exit code 0.
- Automated: CI (step "Text rules").
- Result on 2026-10-28: green.

### J2: tests of the repository scripts

- Proves: the text checker, the design tokens and the menu bar design contract (`tests/test_*.py`).
- How: `python3 -m unittest discover -s tests -v`
- Expected: all tests pass.
- Automated: CI (step "Script tests").
- Result on 2026-10-28: green.

### J3: the Swift package builds

- Proves: the five targets (core, CLI, UI, app, snapshots) compile under Swift 6 language mode.
- How: `swift build`
- Expected: "Build complete!".
- Automated: CI (step "Build").
- Result on 2026-10-28: green.

### J4: the whole Swift test suite

- Proves: the 516 tests (442 in `tests/BrimlineCoreTests`, 74 in `tests/BrimlineUITests`) (Swift Testing).
- How: `swift test`
- Expected: the two lines "Test run with 74 tests in 12 suites passed" and "Test run with 442 tests in 43 suites passed".
- Automated: CI (step "Swift tests").
- Result on 2026-10-28: RED once, then green. In the full local run (the CI run of the same commit was green), `launchedAsPlanned` (`tests/BrimlineCoreTests/Providers/AntigravityEndToEndTests.swift`) failed once on `#expect(text.contains("--print /usage --sandbox\n"))`; it passed on the two following full runs and six times under CPU load. This journey re-ran the suite that holds it (`swift test --filter AntigravityEndToEndTests`, 9 tests) five times in a row: five greens. Flaky, not reproduced; root cause not established. What the test does: it launches a stand-in `agy` script that appends its arguments and environment to a log file, then reads that log back; the failing assertion is the one that looks for the arguments of the second launch in that file. To investigate, run the suite in a loop under CPU load and keep the log content of the first failure.

### J5: the app bundle builds

- Proves: `Brimline.app` is assembled (release build of the app and of the command, Info.plist, icon, helper, ad hoc signature) without being installed anywhere.
- How: `scripts/build_app.sh`
- Expected: ends with "Built .../build/Brimline.app (version 0.1.0, ad hoc signature)", exit code 0; then `codesign --verify --deep --strict build/Brimline.app` passes.
- Automated: CI (step "App bundle").
- Result on 2026-10-28: green. Exit code 0, release build 24.7 s (warm cache), `codesign --verify --deep --strict` passes, `plutil` lint passes, version 0.1.0, `LSUIElement` true (no Dock icon), bundle identifier `eu.thanaelfontaine.brimline`, `Contents/MacOS/Brimline` is an arm64 Mach-O, `Contents/Helpers/brimline --version` prints `0.1.0`. The bundle stays in `build/` (ignored by git): not installed, not opened.

### J6: reading the usage of each provider, on test doubles

- Proves: for Claude, ChatGPT (Codex), Gemini (Antigravity), Grok and Cursor, the reader turns a sign-in file or a command output into limits (or into an honest "expired", "unavailable", "format changed", "no limit returned"), refuses unreadable or oversized files, and calls only its own closed list of URLs. Nothing here touches a real account: the sign-ins are fixtures, HTTP is a fake, and Gemini runs against a stand-in script.
- How: `swift test --filter "ChatGPTTests|CursorTests|CursorUsageTests|CursorHardeningTests|GrokTests|GeminiTests|AntigravityTests|AntigravityRunnerTests|AntigravityEndToEndTests|AntigravityControlCharacterTests|UsageTests|ReaderServiceTests|ClaudeReportTests|ClaudeReportCommandTests"`
- Expected: all pass.
- Automated: yes (part of J4).
- Result on 2026-10-28: green, 218 tests in 14 suites. Not covered: a read of a real provider (needs a real account and a real request, see J10).

### J7: menu bar element and panel

- Proves: the gauge in the menu bar (parts per account, average, alert "!", dimmed last value, upright glyph without data), its tooltip and accessibility text, the panel layout (grouping by provider, states in words), the settings models (colors and warnings, hiding icons).
- How: `swift test --filter BrimlineUITests`, then `swift test --filter "MenuBarGaugeTests|MenuBarAccessibilityTests|PanelLayoutTests|StatusTextTests|MenuBarHidingTests|MenuBarTidyTests|FormattingTests|RankingNoFigureTests|CacheAndRankingTests"`, then the demo renderer: `swift run brimline-snapshots <empty folder>` (it draws the views off screen, at invented data, with a fake menu bar environment, and writes 68 PNG files).
- Expected: tests pass; the renderer ends with exit code 0 and writes the same 68 files as `docs/images/`.
- Automated: tests yes (part of J4); the renderer is manual (it is not in CI and nothing compares its output).
- Result on 2026-10-28: green for the tests (74 and 78 tests). Renderer: exit code 0, 68 files written, 50 byte-identical to `docs/images/`; 18 differ (the long panel sheets (2), the full accounts settings sheets (2) and 14 settings tab images). Looked at: `qa-panel-many-light.png` differs only by the scroll bar, drawn in the committed image and absent in the new one (a system setting of the machine, not a change of the app). The settings images differ only in a 30 by 30 px square at the bottom right corner (largest channel difference 52); the content is unchanged. Treat a diff outside such a square as a real change. Not verified: the real app drawing itself in a real menu bar (see J10).

### J8: no secret in logs, cache, settings or answers

- Proves: seeded tokens are found nowhere in the cache, the settings, the JSON of the command and the MCP answers; the cached types have no field able to hold a token; a token printed by Claude Code never reaches a report; sign-in files are read safely; provider response shapes are keys, not data; a provider that is off is not touched.
- How: `swift test --filter "LeakTests|SecretFileTests|HardeningTests|ResponseShapeTests|ConsentTests|MCPServerTests|AgentsDocExampleTests|AgentProviderTests|RegistryTests|HTTPAllowListTests"`, and `grep -rnE "NSLog|os_log|Logger\(" Sources` (the code writes no system log).
- Expected: tests pass; the grep finds nothing.
- Automated: tests yes (part of J4); the grep is manual.
- Result on 2026-10-28: green (70 tests in 11 suites; grep empty). Not verified: the system log of a real session (see J10).

### J9: the `brimline` command and the MCP server

- Proves: `status`, `accounts`, `providers`, `report` and `mcp` (tools `list_accounts`, `get_usage`, `best_account`) answer in the documented format, and the examples of `docs/agents.md` hold.
- How: the suites `MCPServerTests`, `AgentsDocExampleTests`, `AgentProviderTests`, `ClaudeReportCommandTests` (J6 and J8 commands), plus `build/Brimline.app/Contents/Helpers/brimline --version` on the bundle of J5.
- Expected: tests pass; the version printed is the content of `VERSION`.
- Automated: tests yes; the `--version` check is manual.
- Result on 2026-10-28: green. Not verified: running the built command on data. The command takes the home folder from the system account, not from `$HOME`, so it cannot be pointed at an empty fake home: any run reads the real caches and sign-ins of the person who runs it. It is therefore not replayed here; the same code paths run in the suites above on temporary homes.

### J10: the real app, in a real session, on a real account

- Proves: the app starts, lives in the menu bar, reads a real account, refreshes, shows the panel and the settings, opens at login, and writes nothing in a system log.
- How: manual, on a Mac the maintainer chooses, after `scripts/install.sh`, with an account that can be shown.
- Expected: as described in the README ("Use").
- Automated: no.
- Result on 2026-10-28: not verifiable in this run. It needs the graphical session of the maintainer and real accounts, which a non-regression run must not use; the bundle was built (J5) and its views drawn on invented data (J7), nothing more. Reading real providers also stays manual (the 27 October 2026 trials listed in the README and in `docs/providers.md`).
- Result on 2026-10-28, later, with the maintainer's agreement, on the maintainer's Mac (macOS 27.0.1, a 1920 pt screen, real accounts), build of version 0.2.2 installed by `scripts/install.sh`, by real mouse clicks: a click on Brimline's element opens the panel; "Hide the icons" in the panel, with Claude in front and the bar at 1512 pt, hides the icons left of the bar except the two closest to it, which move left (a « sign appears in place of the others), the line of the bar stays in place and the panel shows the note on the icons closest to the bar; "Show the hidden icons" brings every icon back; the same with Finder in front and with Settings in front. In Settings, Accounts, the "+" of "Other color…" opens the system color panel without changing the saved colors, and the panel closes with Settings. Proof: screenshots of the menu bar before and after each step, kept with the maintainer. Not covered: opening at login, the system log.
- Result on 2026-10-28, at night, same Mac, build of the change "a click on the bar" (after 0.2.2) installed by `scripts/install.sh`, by real mouse clicks, with the bar at 1442 pt: a click on the bar hides every icon left of it and the bar becomes an arrow « beside the search icon (macOS also shows its own « right after the menus of Claude; earlier the same day, with version 0.2.2, a click on that « of macOS showed the hidden icons in place of the menus of the app in front); a click on the arrow shows them all again; a second cycle gives the same; with the Brimline window open, a click on the arrow closes it and shows the icons. Proof: screenshots of the menu bar, kept with the maintainer. Not covered: the "Hide the icons" button of the window in this build (the Mac was in use), opening at login.

## Debt

- No test starts the app itself: nothing checks that the menu bar item appears or that the panel opens.
- The demo renderer (J7) has no comparison step: a change in the drawn views is seen only by someone who reads the images. A tolerant comparison (ignoring the scroll bar and the corner square) would make J7 automatic.
- The flaky test of J4 is open.

## How to add a journey

1. Add a section `### J<n>: <title>` with: proves, how (the exact command or steps), expected, automated (CI, test, or manual), result with its date and proof.
2. Replay it for real before writing "green". Use fixtures, fake HTTP or temporary homes only: never a real account, a real token or the maintainer's session.
3. A journey that cannot be checked locally is written "not verifiable" with the reason.
4. If it is an automatic check, say where it runs (CI step or test name); if it is not in `.github/workflows/checks.yml`, say why.
5. Update the date and the commit at the top. Keep the file free of anything private; `python3 scripts/check_text.py` must pass.
