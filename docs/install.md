# Installing Brimline

Brimline is a **Mac app only**: macOS 14 (Sonoma) or later, on Apple silicon or Intel. There is no Windows or Linux version.

There are three ways to install it. The first two download the app built by the release workflow; the third builds it on your Mac.

## 1. In one line (recommended)

In Terminal:

```bash
curl -fsSL https://brimline.thanaelfontaine.eu/install.sh | sh
```

The script ([readable here](https://brimline.thanaelfontaine.eu/install.sh)):

1. stops if the Mac is not on macOS 14 or later;
2. finds the latest release on GitHub and downloads `Brimline.dmg` and `Brimline.dmg.sha256`;
3. checks the image against its SHA-256 and installs nothing if they differ;
4. copies `Brimline.app` to `/Applications` (or where Brimline already is, or `~/Applications` when `/Applications` is not writable), quitting the running copy first (on macOS 27, Brimline hides the icons only from `/Applications`: a copy kept in `~/Applications` is refused until it is moved);
5. links the command at `~/.local/bin/brimline` (never over a file that is not a link);
6. opens the app.

It asks for no administrator password. Options: `BRIMLINE_VERSION=0.3.2` installs that version, `BRIMLINE_INSTALL_DIR=/path` installs the app somewhere else (for example `curl -fsSL https://brimline.thanaelfontaine.eu/install.sh | BRIMLINE_INSTALL_DIR=~/Applications sh`; on macOS 27, Brimline then refuses to hide icons until it is in `/Applications`).

## 2. The disk image

1. Download [Brimline.dmg](https://github.com/ThanaelFontaine/Brimline/releases/latest/download/Brimline.dmg). Its SHA-256 is in `Brimline.dmg.sha256`, on the [release page](https://github.com/ThanaelFontaine/Brimline/releases/latest): `shasum -a 256 ~/Downloads/Brimline.dmg` must print the same hash.
2. Open it: a window shows Brimline and a shortcut to Applications. Drag Brimline onto Applications.
3. Open Brimline from Applications. The first time, macOS blocks it, because Brimline is not notarized by Apple (that needs a paid Apple Developer account). Close the message, open **System Settings, Privacy & Security**, scroll down and click **Open Anyway**, then **Open** ([Apple's page](https://support.apple.com/en-us/102445)). macOS asks this once.

## 3. From the source

You need Apple's **Command Line Tools** with Swift 6 (Xcode is not needed). If `swift --version` does not answer, install them with:

```bash
xcode-select --install
```

Then:

```bash
git clone https://github.com/ThanaelFontaine/Brimline.git
cd Brimline
scripts/build_app.sh
scripts/install.sh
```

- `scripts/build_app.sh` compiles the app and the `brimline` command for Apple silicon and Intel (`swift build -c release --arch arm64 --arch x86_64`), assembles `build/Brimline.app` and signs it ad hoc (`codesign -s -`). The release is signed with Brimline's own self-signed certificate instead, which a build from the source does not have.
- `scripts/install.sh` copies the app to `/Applications` (or to `~/Applications` when `/Applications` is not writable), moves to the Trash a copy left in `~/Applications` by an earlier install, writes again the **Open at login** LaunchAgent for the new place, links the command to `~/.local/bin/brimline`, and opens the app. With `--login` it also turns on **Open at login** (otherwise turn it on in Settings, General). Nothing is written outside your home folder and `/Applications`, and no administrator password is asked. Brimline must be in `/Applications` to hide menu bar icons on macOS 27 (see [menu bar](menu-bar.md)).
- `scripts/build_dmg.sh` builds `build/Brimline.dmg` from that app, the same image as the release. It is optional and needs Python 3.10 or later (the Command Line Tools bring 3.9: install a newer one from python.org or Homebrew); it installs its Python tools in `.build/dmg-venv`, never system wide.

## After installing

If `brimline` is not found in a new terminal, add `~/.local/bin` to your `PATH` (for example `export PATH="$HOME/.local/bin:$PATH"` in `~/.zshrc`).

Then link your accounts: [accounts.md](accounts.md).

## What macOS shows

- **No Dock icon.** Brimline lives in the menu bar only: look for the gauge at the top right of the screen (the upright glyph while no account has a number yet). Opening the app again (from Finder or Spotlight) while it runs opens its settings.
- **Gatekeeper.** The release is signed with Brimline's own self-signed certificate (0.3.0 and before: ad hoc), not with an Apple Developer identity, and it is not notarized. macOS checks apps that carry the quarantine flag, which browsers set on what they download: so the disk image downloaded in a browser needs **Open Anyway** once (above). In our tests (macOS 27), the app installed by the one-line script, or built from the source, did not carry that flag (checked with `xattr`).
- **Keychain.** Brimline reads each Claude Code sign-in with the `/usr/bin/security` tool. In our tests no prompt appeared; if macOS asks, read the prompt before allowing. See [accounts.md](accounts.md) and [SECURITY.md](../SECURITY.md).
- **Open at login.** When you turn it on (Settings, General), Brimline writes `~/Library/LaunchAgents/eu.thanaelfontaine.brimline.plist`; macOS may then notify you that a background item was added. Turning the option off removes the file.
- **Tried on:** Apple silicon, macOS 27. Intel Macs get the same universal app, not tried on one yet; macOS 14 is the minimum it builds for, not yet tried on a real Sonoma Mac.

## Update

- Installed with the one-line script: run the same line again.
- Installed from the disk image: download the new one and drag Brimline onto Applications again (replace it), after quitting Brimline.
- Built from the source: `git pull`, then `scripts/build_app.sh` and `scripts/install.sh` (it stops the running copy before replacing it).
- On macOS 27, with "Hide without removing" on: up to 0.3.0, Brimline is signed ad hoc, so the Accessibility permission covers one build. After an update, the bar hides with the remembered list (all the other apps at once, no wave) and Brimline says that the permission is missing, until it covers the new build (remove Brimline from the Accessibility list and add it again, as the maintainer did on 29 October 2026, after which macOS listed Brimline as allowed); from 0.3.1, which is signed with Brimline's own certificate, the permission is kept from one build to the next (checked on 29 October 2026 with two signed builds in a row, macOS asking for nothing); see [menu bar](menu-bar.md#2-hide-icons-without-removing-them).

## Formerly Sightglass

Brimline is the new name of the old app (the reason is in the [changelog](../CHANGELOG.md)). If the old app is installed, `scripts/install.sh` takes care of the move:

- it quits the old app and leaves it on disk (in `~/Applications`);
- it removes the old command link in `~/.local/bin`, only when it points into the old app;
- it turns off the old **Open at login** LaunchAgent without deleting its file, and writes the Brimline one in its place (the old one carries the old name in its label);
- at its first launch, Brimline copies your settings and your last numbers from the old folder in `~/Library/Application Support` (the one named after the old app), two files only, never over a file Brimline already has, and leaves the old folder as it was;
- it prints the commands that move the old app, LaunchAgent and folder to the Trash. It does not run them: do it once Brimline shows your accounts.

Your agents need one change: the command and the MCP server are called `brimline` now. If you registered the server under the old name, replace it (`claude mcp list` shows it, `claude mcp remove` takes it out, then add the new one with the command of [agents.md](agents.md)).

## Uninstall

1. Quit Brimline (menu bar window, **Quit**), and turn off **Open at login** first if you turned it on.
2. Remove the files:

   ```bash
   rm -rf /Applications/Brimline.app ~/Applications/Brimline.app
   rm -f ~/.local/bin/brimline
   rm -f ~/Library/LaunchAgents/eu.thanaelfontaine.brimline.plist
   rm -rf ~/Library/Application\ Support/Brimline
   ```

Brimline never wrote to your Keychain or to your Claude Code folders, so there is nothing to clean there. If you gave it the Accessibility permission (macOS 27, to hide icons), remove Brimline from System Settings, Privacy & Security, Accessibility.

## For contributors

```bash
swift build                     # debug build
swift test                      # tests (Swift Testing)
swift run brimline status       # the command, from the sources
swift run brimline-snapshots    # renders docs/images/ from fictitious data
python3 scripts/check_text.py   # text rules
```

The package builds with the Command Line Tools alone; there is no Xcode project.
