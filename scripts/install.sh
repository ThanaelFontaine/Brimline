#!/bin/bash
# Installs the app built by scripts/build_app.sh for the current user:
#   ~/Applications/Sightglass.app, the command linked at ~/.local/bin/sightglass, then opens the app.
#
#   scripts/build_app.sh && scripts/install.sh [--login]
#
# --login also opens the app at login: it writes the same LaunchAgent as Settings, General,
# Open at login (~/Library/LaunchAgents/eu.thanaelfontaine.sightglass.plist).
#
# Nothing is written outside your home folder and no administrator password is asked.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/Sightglass.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Sightglass.app"
BIN_DIR="$HOME/.local/bin"
AGENT="$HOME/Library/LaunchAgents/eu.thanaelfontaine.sightglass.plist"

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

# Stop the installed copy if it runs (only that one, found by its full path).
for pid in $(pgrep -f "^$DEST/Contents/MacOS/Sightglass" || true); do
  kill "$pid" 2>/dev/null || true
done
sleep 1

mkdir -p "$DEST_DIR" "$BIN_DIR"
rm -rf "$DEST"
cp -R "$SOURCE" "$DEST"
ln -sf "$DEST/Contents/Helpers/sightglass" "$BIN_DIR/sightglass"

if [ "$LOGIN" = 1 ]; then
  mkdir -p "$(dirname "$AGENT")"
  cat > "$AGENT" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>eu.thanaelfontaine.sightglass</string>
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
echo "Command: $BIN_DIR/sightglass (add $BIN_DIR to your PATH if \`sightglass\` is not found)"
