#!/bin/bash
# Installs the app built by scripts/build_app.sh for the current user:
#   ~/Applications/Sightglass.app, the command linked at ~/.local/bin/sightglass, then opens the app.
#
#   scripts/build_app.sh && scripts/install.sh
#
# Nothing is written outside your home folder and no administrator password is asked.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SOURCE="$ROOT/build/Sightglass.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/Sightglass.app"
BIN_DIR="$HOME/.local/bin"

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

open "$DEST"

echo "Installed $DEST"
echo "Command: $BIN_DIR/sightglass (add $BIN_DIR to your PATH if \`sightglass\` is not found)"
