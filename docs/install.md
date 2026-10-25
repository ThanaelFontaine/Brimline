# Installing Sightglass

There is no downloadable, Apple-notarized build of Sightglass yet. You build it on your Mac from the source: it takes a few minutes and needs no Apple account.

## What you need

- macOS 14 (Sonoma) or later. Sightglass is developed and tested on recent macOS; macOS 14 is the minimum it builds for, not yet tested on a real Sonoma Mac.
- Apple's **Command Line Tools** with Swift 6 (Xcode is not needed). If `swift --version` does not answer, install them with:

  ```bash
  xcode-select --install
  ```

## Build and install

```bash
git clone https://github.com/ThanaelFontaine/Sightglass.git
cd Sightglass
scripts/build_app.sh
scripts/install.sh
```

- `scripts/build_app.sh` compiles the app and the `sightglass` command (`swift build -c release`), assembles `build/Sightglass.app` and signs it ad hoc (`codesign -s -`).
- `scripts/install.sh` copies the app to `~/Applications`, links the command to `~/.local/bin/sightglass`, and opens the app. With `--login` it also turns on **Open at login** (otherwise turn it on in Settings, General). Nothing is written outside your home folder, and no administrator password is asked.

If `sightglass` is not found in a new terminal, add `~/.local/bin` to your `PATH` (for example `export PATH="$HOME/.local/bin:$PATH"` in `~/.zshrc`).

## What macOS shows

- **No Dock icon.** Sightglass lives in the menu bar only: look for the level glyph at the top right of the screen. Opening the app again (from Finder or Spotlight) while it runs opens its settings.
- **No "unidentified developer" warning, in our tests.** The app is signed ad hoc, not with an Apple Developer identity. macOS mainly checks apps that carry the quarantine flag, which is set on downloaded files; an app you build yourself does not carry it. If you copy a built app to another Mac through a download, macOS will block it: build it on each Mac instead.
- **Keychain.** Sightglass reads each Claude Code sign-in with the `/usr/bin/security` tool. In our tests no prompt appeared; if macOS asks, read the prompt before allowing. See [accounts.md](accounts.md) and [SECURITY.md](../SECURITY.md).
- **Open at login.** When you turn it on (Settings, General), Sightglass writes `~/Library/LaunchAgents/eu.thanaelfontaine.sightglass.plist`; macOS may then notify you that a background item was added. Turning the option off removes the file.

## Update

```bash
cd Sightglass
git pull
scripts/build_app.sh
scripts/install.sh
```

`install.sh` stops the running copy before replacing it.

## Uninstall

1. Quit Sightglass (menu bar window, **Quit**), and turn off **Open at login** first if you turned it on.
2. Remove the files:

   ```bash
   rm -rf ~/Applications/Sightglass.app
   rm -f ~/.local/bin/sightglass
   rm -f ~/Library/LaunchAgents/eu.thanaelfontaine.sightglass.plist
   rm -rf ~/Library/Application\ Support/Sightglass
   ```

Sightglass never wrote to your Keychain or to your Claude Code folders, so there is nothing to clean there.

## For contributors

```bash
swift build                     # debug build
swift test                      # tests (Swift Testing)
swift run sightglass status     # the command, from the sources
swift run sightglass-snapshots  # renders docs/images/ from fictitious data
python3 scripts/check_text.py   # text rules
```

The package builds with the Command Line Tools alone; there is no Xcode project.
