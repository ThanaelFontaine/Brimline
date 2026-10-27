# Installing Brimline

There is no downloadable, Apple-notarized build of Brimline yet. You build it on your Mac from the source: it takes a few minutes and needs no Apple account.

## What you need

- macOS 14 (Sonoma) or later. Brimline is developed and tested on recent macOS; macOS 14 is the minimum it builds for, not yet tested on a real Sonoma Mac.
- Apple's **Command Line Tools** with Swift 6 (Xcode is not needed). If `swift --version` does not answer, install them with:

  ```bash
  xcode-select --install
  ```

## Build and install

```bash
git clone https://github.com/ThanaelFontaine/Brimline.git
cd Brimline
scripts/build_app.sh
scripts/install.sh
```

- `scripts/build_app.sh` compiles the app and the `brimline` command (`swift build -c release`), assembles `build/Brimline.app` and signs it ad hoc (`codesign -s -`).
- `scripts/install.sh` copies the app to `~/Applications`, links the command to `~/.local/bin/brimline`, and opens the app. With `--login` it also turns on **Open at login** (otherwise turn it on in Settings, General). Nothing is written outside your home folder, and no administrator password is asked.

If `brimline` is not found in a new terminal, add `~/.local/bin` to your `PATH` (for example `export PATH="$HOME/.local/bin:$PATH"` in `~/.zshrc`).

## What macOS shows

- **No Dock icon.** Brimline lives in the menu bar only: look for the level glyph at the top right of the screen. Opening the app again (from Finder or Spotlight) while it runs opens its settings.
- **No "unidentified developer" warning, in our tests.** The app is signed ad hoc, not with an Apple Developer identity. macOS mainly checks apps that carry the quarantine flag, which is set on downloaded files; an app you build yourself does not carry it. If you copy a built app to another Mac through a download, macOS will block it: build it on each Mac instead.
- **Keychain.** Brimline reads each Claude Code sign-in with the `/usr/bin/security` tool. In our tests no prompt appeared; if macOS asks, read the prompt before allowing. See [accounts.md](accounts.md) and [SECURITY.md](../SECURITY.md).
- **Open at login.** When you turn it on (Settings, General), Brimline writes `~/Library/LaunchAgents/eu.thanaelfontaine.brimline.plist`; macOS may then notify you that a background item was added. Turning the option off removes the file.

## Update

```bash
cd Brimline
git pull
scripts/build_app.sh
scripts/install.sh
```

`install.sh` stops the running copy before replacing it.

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
   rm -rf ~/Applications/Brimline.app
   rm -f ~/.local/bin/brimline
   rm -f ~/Library/LaunchAgents/eu.thanaelfontaine.brimline.plist
   rm -rf ~/Library/Application\ Support/Brimline
   ```

Brimline never wrote to your Keychain or to your Claude Code folders, so there is nothing to clean there.

## For contributors

```bash
swift build                     # debug build
swift test                      # tests (Swift Testing)
swift run brimline status       # the command, from the sources
swift run brimline-snapshots    # renders docs/images/ from fictitious data
python3 scripts/check_text.py   # text rules
```

The package builds with the Command Line Tools alone; there is no Xcode project.
