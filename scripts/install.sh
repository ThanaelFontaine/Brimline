#!/bin/bash
# Installs the app built by scripts/build_app.sh for the current user:
#   ~/Applications/Brimline.app, the command linked at ~/.local/bin/brimline, then opens the app.
#
#   scripts/build_app.sh && scripts/install.sh [--login]
#
# --login also opens the app at login: it writes the same LaunchAgent as Settings, General,
# Open at login (~/Library/LaunchAgents/eu.thanaelfontaine.brimline.plist).
#
# Brimline was called Sightglass. If the old app is installed, this script also:
# - quits it (found by its full path), and keeps it on disk;
# - removes the old command link ~/.local/bin/sightglass, only if it points into Sightglass.app;
# - disables the old LaunchAgent (`launchctl disable`, undone by `enable`; the file stays) and
#   writes the Brimline one in its place;
# - prints the command that moves the old files to the Trash, without running it.
# The settings and the usage cache of the old folder come over at the first launch of Brimline.
#
# Nothing is written outside your home folder and no administrator password is asked.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/Brimline.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Brimline.app"
BIN_DIR="$HOME/.local/bin"
AGENT_DIR="$HOME/Library/LaunchAgents"
AGENT="$AGENT_DIR/eu.thanaelfontaine.brimline.plist"

OLD_APP="$DEST_DIR/Sightglass.app"
OLD_LINK="$BIN_DIR/sightglass"
OLD_LABEL="eu.thanaelfontaine.sightglass"
OLD_AGENT="$AGENT_DIR/$OLD_LABEL.plist"
OLD_SUPPORT="$HOME/Library/Application Support/Sightglass"

LOGIN=0
for arg in "$@"; do
  case "$arg" in
    --login) LOGIN=1 ;;
    *) echo "install: unknown option $arg (only --login)" >&2; exit 64 ;;
  esac
done

if [ ! -d "$SOURCE" ]; then
  echo "install: $SOURCE not found, run scripts/build_app.sh first" >&2
  exit 1
fi

# Stop the old app and the installed copy if they run (only those, found by their full path).
for pid in $(pgrep -f "^$OLD_APP/Contents/MacOS/Sightglass" || true) \
           $(pgrep -f "^$DEST/Contents/MacOS/Brimline" || true); do
  kill "$pid" 2>/dev/null || true
done
sleep 1

mkdir -p "$DEST_DIR" "$BIN_DIR"
rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"
ln -sf "$DEST/Contents/Helpers/brimline" "$BIN_DIR/brimline"

# The old command link goes, but only a link that points into the old app: never another file.
if [ -L "$OLD_LINK" ]; then
  case "$(readlink "$OLD_LINK")" in
    */Sightglass.app/*) rm -f "$OLD_LINK" ;;
  esac
fi

# The old app opened at login: turn that off (reversible, the file stays) and carry the wish over.
# Only the first time: once the old agent is disabled, a later run must not switch the wish back on.
if [ -f "$OLD_AGENT" ]; then
  if ! launchctl print-disabled "gui/$(id -u)" 2>/dev/null | grep -q "\"$OLD_LABEL\" => \(disabled\|true\)"; then
    LOGIN=1
  fi
  launchctl disable "gui/$(id -u)/$OLD_LABEL" 2>/dev/null || true
fi

if [ "$LOGIN" = 1 ]; then
  mkdir -p "$AGENT_DIR"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>eu.thanaelfontaine.brimline</string>
	<key>ProcessType</key>
	<string>Interactive</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-g</string>
		<string>-a</string>
		<string>$DEST</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
</dict>
</plist>
PLIST
  plutil -lint -s "$AGENT"
fi

open "$DEST"

echo "Installed $DEST"
if [ "$LOGIN" = 1 ]; then echo "Opens at login: $AGENT"; fi
echo "Command: $BIN_DIR/brimline (add $BIN_DIR to your PATH if \`brimline\` is not found)"

# What is left of Sightglass: told, never removed here.
if [ -e "$OLD_APP" ] || [ -e "$OLD_AGENT" ] || [ -e "$OLD_SUPPORT" ]; then
  cat <<'NOTE'

Sightglass is now Brimline. The old app, its LaunchAgent and its folder are still on disk
(the settings and the cache are copied at the first launch of Brimline, nothing is deleted). Once Brimline shows your accounts,
this moves them to the Trash (nothing is lost until you empty it):

  launchctl bootout gui/$(id -u)/eu.thanaelfontaine.sightglass 2>/dev/null; mv ~/Library/LaunchAgents/eu.thanaelfontaine.sightglass.plist ~/.Trash/
  mv ~/Applications/Sightglass.app ~/.Trash/
  mv "$HOME/Library/Application Support/Sightglass" ~/.Trash/Sightglass-support
NOTE
fi
