# Brimline: critical journeys

The journeys to replay before each release to prove that Brimline (the macOS menu bar app, its `brimline` command and its MCP server) still builds, reads usage from every provider and shows it, without leaking a secret. Everything runs locally, on test doubles and invented data, except J10 and J11, which the maintainer's Mac runs read only on his own accounts: never in production.

- Verified on: 2026-11-06
- origin/main commit verified: `9d0f9d153938365dd846546825d0ac136ccdce8e` (version 0.3.3 plus the suspended launch of `agy`, the content of 0.3.4)
- Environment: macOS 27.0.1 on Apple silicon, Swift with the Command Line Tools only (no Xcode).
- J1 to J5 are the steps of `.github/workflows/checks.yml`; they were replayed by hand on this commit. J6 to J9 were run on this commit too, and J11 on the maintainer's Mac. The results of earlier runs stay below as history, one line per run.

## Journeys

### J1: text rules

- Proves: no em or en dash, no personal data (home paths, personal addresses) and no old product name in tracked text files.
- How: `python3 scripts/check_text.py`
- Expected: exit code 0.
- Automated: CI (step "Text rules").
- Result on 2026-10-28: green.
- Result on 2026-11-04: green (360 tracked files, 0 problem).
- Result on 2026-11-06: green (361 tracked files, 0 problem).

### J2: tests of the repository scripts

- Proves: the text checker, the design tokens and the menu bar design contract (`tests/test_*.py`).
- How: `python3 -m unittest discover -s tests -v`
- Expected: all tests pass.
- Automated: CI (step "Script tests").
- Result on 2026-10-28: green.
- Result on 2026-11-04: green (76 tests).
- Result on 2026-11-06: green (76 tests).

### J3: the Swift package builds

- Proves: the five targets (core, CLI, UI, app, snapshots) compile under Swift 6 language mode.
- How: `swift build`
- Expected: "Build complete!".
- Automated: CI (step "Build").
- Result on 2026-10-28: green.
- Result on 2026-11-04: green ("Build complete!", 32.8 s).
- Result on 2026-11-06: green ("Build complete!", 27.5 s).

### J4: the whole Swift test suite

- Proves: the 561 tests (480 in `tests/BrimlineCoreTests`, 81 in `tests/BrimlineUITests`) (Swift Testing).
- How: `swift test`
- Expected: the two lines "Test run with 81 tests in 12 suites passed" and "Test run with 480 tests in 44 suites passed".
- Automated: CI (step "Swift tests").
- Result on 2026-10-28: RED once, then green. In the full local run (the CI run of the same commit was green), `launchedAsPlanned` (`tests/BrimlineCoreTests/Providers/AntigravityEndToEndTests.swift`) failed once on `#expect(text.contains("--print /usage --sandbox\n"))`; it passed on the two following full runs and six times under CPU load. This journey re-ran the suite that holds it (`swift test --filter AntigravityEndToEndTests`, 9 tests) five times in a row: five greens. Flaky, not reproduced; root cause not established. What the test does: it launches a stand-in `agy` script that appends its arguments and environment to a log file, then reads that log back; the failing assertion is the one that looks for the arguments of the second launch in that file. To investigate, run the suite in a loop under CPU load and keep the log content of the first failure.
- Result on 2026-11-04: green, 81 and 460 tests passed (541 against 528 on 0.3.2: the Gemini signature lot adds its tests and replaces the tests of the list of builds). The flaky test did not fail in this full run; it stays open, not reproduced.
- Result on 2026-11-06: green, 81 and 480 tests passed (561 against 541 on the previous run: the suspended launch of `agy` adds its tests to `AntigravityRunnerTests`, `AntigravityEndToEndTests` and `AntigravityTests`). The flaky test did not fail in this full run either; it stays open, not reproduced.

### J5: the app bundle builds

- Proves: `Brimline.app` is assembled (release build of the app and of the command, Info.plist, icon, helper, ad hoc signature, or Brimline's own certificate when it is there) without being installed anywhere.
- How: `scripts/build_app.sh`
- Expected: ends with "Built .../build/Brimline.app (version 0.1.0, Apple silicon and Intel, ad hoc signature)" ("signed by Brimline Code Signing" on the maintainer's Mac), exit code 0; then `codesign --verify --deep --strict build/Brimline.app` passes.
- Signed build: with `BRIMLINE_SIGNING_IDENTITY` and `BRIMLINE_SIGNING_KEYCHAIN` set (the release workflow sets them), `scripts/check_signature.sh build/Brimline.app` checks the signature, the identifier, the authority, the designated requirement, and that a second build, with another code hash, satisfies the requirement of the first. Run on 2026-10-29 on the maintainer's Mac: passes on a build signed by Brimline Code Signing, refuses an ad hoc build.
- Automated: CI (step "App bundle"); the signed build, by the dry run of the release workflow ("Release", run by hand on main, no tag and no release).
- Result on 2026-10-28: green. Exit code 0, release build 24.7 s (warm cache), `codesign --verify --deep --strict` passes, `plutil` lint passes, version 0.1.0, `LSUIElement` true (no Dock icon), bundle identifier `eu.thanaelfontaine.brimline`, `Contents/MacOS/Brimline` is an arm64 Mach-O, `Contents/Helpers/brimline --version` prints `0.1.0`. The bundle stays in `build/` (ignored by git): not installed, not opened.
- Result on 2026-11-04: green. `scripts/build_app.sh` ends with "Built .../build/Brimline.app (version 0.3.2, Apple silicon and Intel, signed by Brimline Code Signing)", `codesign --verify --deep --strict` passes, `plutil -lint` passes, bundle identifier `eu.thanaelfontaine.brimline`, `LSUIElement` true, `Contents/Helpers/brimline --version` prints `0.3.2`. The bundle stays in `build/`: not installed, not opened.
- Result on 2026-11-06: green. `scripts/build_app.sh` ends with "Built .../build/Brimline.app (version 0.3.3, Apple silicon and Intel, signed by Brimline Code Signing)" (release build 100.8 s; 2 min 28 s in all), `codesign --verify --deep --strict` passes, `plutil -lint` passes, bundle identifier `eu.thanaelfontaine.brimline`, `LSUIElement` true, `Contents/MacOS/Brimline` a universal Mach-O (x86_64 and arm64), `Contents/Helpers/brimline --version` prints `0.3.3`, the content of `VERSION`. The bundle stays in `build/`: not installed, not opened (the installed copy, running since 4 November, was not touched).

### J6: reading the usage of each provider, on test doubles

- Proves: for Claude, ChatGPT (Codex), Gemini (Antigravity), Grok and Cursor, the reader turns a sign-in file or a command output into limits (or into an honest "expired", "unavailable", "format changed", "no limit returned"), refuses unreadable or oversized files, and calls only its own closed list of URLs. Nothing here touches a real account: the sign-ins are fixtures, HTTP is a fake, and Gemini runs against a stand-in script.
- How: `swift test --filter "ChatGPTTests|CursorTests|CursorUsageTests|CursorHardeningTests|GrokTests|GeminiTests|AntigravityTests|AntigravityRunnerTests|AntigravityEndToEndTests|AntigravitySignatureTests|AntigravityControlCharacterTests|UsageTests|ReaderServiceTests|ClaudeReportTests|ClaudeReportCommandTests"`
- Expected: all pass.
- Automated: yes (part of J4).
- Result on 2026-10-28: green, 218 tests in 14 suites. Not covered: a read of a real provider (needs a real account and a real request, see J10).
- Result on 2026-11-04: green, 232 tests in 15 suites (the Gemini suites now include the real signature checker, `AntigravitySignatureTests`, and the stand-in launch tests without a list of builds). `BRIMLINE_REAL_AGY=1 swift test --filter AntigravitySignatureTests` passes on a Mac that has the real `agy` (see J11).
- Result on 2026-11-06: green, 252 tests in 15 suites (the Gemini suites now cover the suspended launch, the check on the process and the group stop; the real-`agy` test of the signature suite passes with `BRIMLINE_REAL_AGY=1`, see J11).

### J7: menu bar element and panel

- Proves: the gauge in the menu bar (parts per account, average, alert "!", dimmed last value, upright glyph without data), its tooltip and accessibility text, the panel layout (grouping by provider, states in words), the settings models (colors and warnings, hiding icons).
- How: `swift test --filter BrimlineUITests`, then `swift test --filter "MenuBarGaugeTests|MenuBarAccessibilityTests|PanelLayoutTests|StatusTextTests|MenuBarHidingTests|MenuBarTidyTests|FormattingTests|RankingNoFigureTests|CacheAndRankingTests"`, then the demo renderer: `swift run brimline-snapshots <empty folder>` (it draws the views off screen, at invented data, with a fake menu bar environment, and writes 68 PNG files).
- Expected: tests pass; the renderer ends with exit code 0 and writes the same 68 files as `docs/images/`.
- Automated: tests yes (part of J4); the renderer is manual (it is not in CI and nothing compares its output).
- Result on 2026-10-28: green for the tests (74 and 78 tests). Renderer: exit code 0, 68 files written, 50 byte-identical to `docs/images/`; 18 differ (the long panel sheets (2), the full accounts settings sheets (2) and 14 settings tab images). Looked at: `qa-panel-many-light.png` differs only by the scroll bar, drawn in the committed image and absent in the new one (a system setting of the machine, not a change of the app). The settings images differ only in a 30 by 30 px square at the bottom right corner (largest channel difference 52); the content is unchanged. Treat a diff outside such a square as a real change. Not verified: the real app drawing itself in a real menu bar (see J10).
- Result on 2026-11-04: green for the tests (81 UI tests in the full run). Renderer: exit code 0, 68 files written, all 68 byte-identical to `docs/images/`.
- Result on 2026-11-06: green for the tests (82 tests in 11 suites; 81 UI tests in the full run). Renderer: exit code 0, 68 files written; 46 byte-identical to `docs/images/`, 2 identical in pixels (the two long panel sheets), 20 differ (the settings tab images and the full accounts sheets). On the 20, the only pixels that differ are in one square of 26 to 30 px near the bottom right corner of the window, 24 px from its edges (largest channel difference 73 in dark, 52 in light); the crop of `settings-accounts-light.png` shows the rounded corner of the window with a vertical line (scroll bar or separator) in the committed image and not in the new one: the same drawn-by-the-system square as on 2026-10-28, not a change of the app. The previous run (2026-11-04) had all 68 identical: it depends on a system setting of the machine, and no view changed since.

### J8: no secret in logs, cache, settings or answers

- Proves: seeded tokens are found nowhere in the cache, the settings, the JSON of the command and the MCP answers; the cached types have no field able to hold a token; a token printed by Claude Code never reaches a report; sign-in files are read safely; provider response shapes are keys, not data; a provider that is off is not touched.
- How: `swift test --filter "LeakTests|SecretFileTests|HardeningTests|ResponseShapeTests|ConsentTests|MCPServerTests|AgentsDocExampleTests|AgentProviderTests|RegistryTests|HTTPAllowListTests"`, and `grep -rnE "NSLog|os_log|Logger\(" Sources` (the code writes no system log).
- Expected: tests pass; the grep finds nothing.
- Automated: tests yes (part of J4); the grep is manual.
- Result on 2026-10-28: green (70 tests in 11 suites; grep empty). Not verified: the system log of a real session (see J10).
- Result on 2026-11-04: green (70 tests in 11 suites; grep empty).
- Result on 2026-11-06: green (70 tests in 11 suites; grep of `NSLog|os_log|Logger(` in `Sources` empty).

### J9: the `brimline` command and the MCP server

- Proves: `status`, `accounts`, `providers`, `report` and `mcp` (tools `list_accounts`, `get_usage`, `best_account`) answer in the documented format, and the examples of `docs/agents.md` hold.
- How: the suites `MCPServerTests`, `AgentsDocExampleTests`, `AgentProviderTests`, `ClaudeReportCommandTests` (J6 and J8 commands), plus `build/Brimline.app/Contents/Helpers/brimline --version` on the bundle of J5.
- Expected: tests pass; the version printed is the content of `VERSION`.
- Automated: tests yes; the `--version` check is manual.
- Result on 2026-10-28: green. Not verified: running the built command on data. The command takes the home folder from the system account, not from `$HOME`, so it cannot be pointed at an empty fake home: any run reads the real caches and sign-ins of the person who runs it. It is therefore not replayed here; the same code paths run in the suites above on temporary homes.
- Result on 2026-11-04: green. Same suites as J6 and J8 pass. `Contents/Helpers/brimline --version` of the bundle of J5 prints `0.3.2`, the content of `VERSION`. The built command answers `initialize` over `brimline mcp` with `serverInfo.name` = `brimline`, title `Brimline`, version 0.3.2 (the request carries no account data).
- Result on 2026-11-06: green. Same suites as J6 and J8 pass. `Contents/Helpers/brimline --version` of the bundle of J5 prints `0.3.3`. The built command answers `initialize` over `brimline mcp` with `serverInfo.name` = `brimline`, title `Brimline`, version 0.3.3. `brimline status --json`, read on the maintainer's Mac like J11, answers from the cache (exit code 0; keys `accounts`, `age_seconds`, `generated_at`, `schema_version`, `source`; `source` is `cache`, 17 s old; 5 Claude accounts: 4 `ok`, 1 `signed_out`).

### J10: the real app, in a real session, on a real account

- Proves: the app starts, lives in the menu bar, reads a real account, refreshes, shows the panel and the settings, opens at login, and writes nothing in a system log.
- How: manual, on a Mac the maintainer chooses, after `scripts/install.sh`, with an account that can be shown.
- Expected: as described in the README ("Use").
- Automated: no.
- Result on 2026-10-28: not verifiable in this run. It needs the graphical session of the maintainer and real accounts, which a non-regression run must not use; the bundle was built (J5) and its views drawn on invented data (J7), nothing more. Reading real providers also stays manual (the 27 October 2026 trials listed in the README and in `docs/providers.md`).
- Result on 2026-10-28, later, with the maintainer's agreement, on the maintainer's Mac (macOS 27.0.1, a 1920 pt screen, real accounts), build of version 0.2.2 installed by `scripts/install.sh`, by real mouse clicks: a click on Brimline's element opens the panel; "Hide the icons" in the panel, with Claude in front and the bar at 1512 pt, hides the icons left of the bar except the two closest to it, which move left (a « sign appears in place of the others), the line of the bar stays in place and the panel shows the note on the icons closest to the bar; "Show the hidden icons" brings every icon back; the same with Finder in front and with Settings in front. In Settings, Accounts, the "+" of "Other color…" opens the system color panel without changing the saved colors, and the panel closes with Settings. Proof: screenshots of the menu bar before and after each step, kept with the maintainer. Not covered: opening at login, the system log.
- Result on 2026-10-28, at night, same Mac, build of the change "a click on the bar" (after 0.2.2) installed by `scripts/install.sh`, by real mouse clicks, with the bar at 1442 pt: a click on the bar hides every icon left of it and the bar becomes an arrow « beside the search icon (macOS also shows its own « right after the menus of Claude; earlier the same day, with version 0.2.2, a click on that « of macOS showed the hidden icons in place of the menus of the app in front); a click on the arrow shows them all again; a second cycle gives the same; with the Brimline window open, a click on the arrow closes it and shows the icons. Proof: screenshots of the menu bar, kept with the maintainer. Not covered: the "Hide the icons" button of the window in this build (the Mac was in use), opening at login.
- Result on 2026-10-29, hiding with macOS 27's allow-list inside Brimline (macOS 27.0.1, a 1920 pt screen with no notch, Brimline in `/Applications` with the Accessibility permission, its bar placed by the maintainer left of Notion Calendar's item): OK by real clicks. A click on the bar hid the apps left of it one after the other, from the farthest to the bar (Flux first, Search last), while the bar turned into «; a click on the « showed them again from the nearest, and the « turned back into the bar. The "Hide the icons" button of the Brimline window and the one of Settings gave the same, both ways, and their label followed ("Show the hidden icons" / "Hide the icons"). Only one « in the menu bar: macOS drew none of its own. The Brimline window opened right under the menu bar (top at 32 pt), as high as its content (867 pt), with no band under "Quit". Two synthetic clicks sent while the menu bar was hidden were lost; the same action sent through Accessibility (AXPress) worked, then the real clicks with the menu bar shown. Then `scripts/install.sh` was run again from the branch while the icons were hidden: they all came back at once when the old copy was ended, before the new one started. That install copied the build already made in that folder, before the fixes of the review, so it was the same build (same cdhash) and it kept the permission; with it, the first hide after the launch took about 2 s before the icons went (the first read of the menu bar), the next ones started at once, and both waves went one app after the other. The build of `main` after the merge (ef276a2) has another cdhash: the grant macOS keeps (`cdhash H"…"` of the approved build, read in the system's permission database) did not cover it, so the bar hid every other app at once with the remembered list. The fixes of the review (a number for each wave, the way back from what is really hidden) are still to be tried by real clicks, once the permission is given again. Not covered: a notch, several screens, sleep and lock, an app whose Accessibility read times out (it is then hidden, as it is not on the list).
- Result on 2026-11-04: not replayed. The real app in the maintainer's graphical session was not driven in this run (the installed app was left running and untouched); the bundle was built (J5), its views drawn on invented data (J7) and the real providers read by the command (J11).
- Result on 2026-11-06: not replayed. The real app in the maintainer's graphical session was not driven in this run (the installed copy was left running and untouched); the bundle was built (J5), its views drawn on invented data (J7) and the real providers read by the command (J11).

### J11: a provider read for real by the built command (Gemini after an update of Antigravity)

- Proves: with the real `agy` of the Mac, whatever its build, the Gemini card shows real numbers (no `format_changed` for a build Brimline has never seen), Claude and ChatGPT are read, and turning a provider off puts the settings back.
- How: on the maintainer's Mac only (never in CI), with the provider turned on for the time of the run: `brimline providers enable gemini` (and `chatgpt`), `build/Brimline.app/Contents/Helpers/brimline status --live --json --provider <name>` (three reads for Gemini, two seconds apart), `brimline status --json` (the cache), then `brimline providers disable <name>`; and `BRIMLINE_REAL_AGY=1 swift test --filter AntigravitySignatureTests`.
- Expected: status `ok` with the limits of the provider (for Gemini, the five lines of `agy --print /usage`), no `format_changed`, no `agy` process left, the sign-in file of Codex unchanged (checksum before and after), the providers as found at the end (Claude on, the others off).
- Automated: no (it reads the maintainer's real accounts, read only, and needs the maintainer's Mac).
- Result on 2026-11-04: green. `agy` was at 1.4.12, a build Brimline had never seen (not on the old list; signature `Identifier=cli`, authority Developer ID Application: Google LLC, team `EQHXZ8M8AV`). Gemini: status `ok` on the three reads, the five limits (Gemini Models 5 h and week, Claude and GPT models 5 h and week, Gemini 4 Argon week) at 0 % used, reset times of the text; no `agy` process left behind. ChatGPT (Codex): status `ok`, the monthly period at 0 %. Claude: `ok`, session, week and model limits. The checksum of `~/.codex/auth.json` was the same before and after. Providers put back as found (Claude on, the other four off). The real-`agy` test of the signature suite passed. Not covered: the Gemini card drawn by the real app (J10), and the second line of defence (the launch of the suspended process), which is the next lot.
- Result on 2026-11-06: green, on the build of the content of 0.3.4 (suspended launch of `agy`). `agy` is still 1.4.12. Gemini: status `ok` on three reads two seconds apart with the live read of the built command, the five limits (Gemini Models 5 h and week, Claude and GPT models 5 h and week, Gemini 4 Argon week) at 0 % used, reset times of the text, no `format_changed`, no `signature_not_recognized`; no `agy` process left behind after the reads. So the second line of defence (start `agy` suspended, check Google's signature on the process by its audit token, then let it run) works on the real `agy`, which the 4 November run listed as not covered. ChatGPT (Codex): status `ok`, one `period` limit at 0 %. Claude: `--live` gave 5 accounts, 4 `ok` (session and week limits, one with a model limit) and 1 `signed_out` (an account that is signed out on this Mac, as in the cache read just before; the app's cache read before the run held the same 4 `ok` and 1 `signed_out`: not a change of this version). The checksum of `~/.codex/auth.json` was the same before and after. Providers put back as found (Claude on, the other four off). `BRIMLINE_REAL_AGY=1 swift test --filter AntigravitySignatureTests` passed (8 tests). Not covered: the Gemini card drawn by the real app (J10).

## Debt

- No test starts the app itself: nothing checks that the menu bar item appears or that the panel opens.
- The demo renderer (J7) has no comparison step: a change in the drawn views is seen only by someone who reads the images. A tolerant comparison (ignoring the scroll bar and the corner square) would make J7 automatic.
- The flaky test of J4 is open.

## How to add a journey

1. Add a section `### J<n>: <title>` with: proves, how (the exact command or steps), expected, automated (CI, test, or manual), result with its date and proof.
2. Replay it for real before writing "green". Use fixtures, fake HTTP or temporary homes only: never a real account, a real token or the maintainer's session (the one exception is a manual journey run read only on the maintainer's own Mac, as J10 and J11).
3. A journey that cannot be checked locally is written "not verifiable" with the reason.
4. If it is an automatic check, say where it runs (CI step or test name); if it is not in `.github/workflows/checks.yml`, say why.
5. Update the date and the commit at the top. Keep the file free of anything private; `python3 scripts/check_text.py` must pass.
