#!/bin/bash
# Builds the disk image of Brimline from an app already built by scripts/build_app.sh:
# a "Brimline" volume showing Brimline.app next to an Applications shortcut, on a background
# that says to drag one onto the other. Used by the release workflow, and usable on any Mac with
# Python 3.10 or later.
#
#   scripts/build_dmg.sh [APP] [OUT_DIR]
#     APP      the bundle to package (default: build/Brimline.app)
#     OUT_DIR  where to write the image (default: build)
#
# Writes OUT_DIR/Brimline.dmg and OUT_DIR/Brimline.dmg.sha256 ("<hash>  Brimline.dmg"). The name
# carries no version, so that https://github.com/ThanaelFontaine/Brimline/releases/latest/download/Brimline.dmg
# always gives the latest one; the version is inside (the app's Info.plist).
#
# Needs Python 3.10 or later (dmgbuild and Pillow require it): the python3 of the Command Line
# Tools is 3.9, so install a newer one (python.org or Homebrew), or point PYTHON at it. The Python
# tools (exact versions and hashes in packaging/requirements-dmg.txt) are installed in
# .build/dmg-venv with pip --require-hashes, never system wide. Installs nothing else: the image
# is written, checked, and never copied to /Applications.
set -euo pipefail

CALLER_DIR="$PWD"
APP="${1:-}"
OUT_DIR="${2:-}"
if [ -n "$APP" ] && [ "${APP#/}" = "$APP" ]; then APP="$CALLER_DIR/$APP"; fi
if [ -n "$OUT_DIR" ] && [ "${OUT_DIR#/}" = "$OUT_DIR" ]; then OUT_DIR="$CALLER_DIR/$OUT_DIR"; fi
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="${APP:-$ROOT/build/Brimline.app}"
OUT_DIR="${OUT_DIR:-$ROOT/build}"

if [ "$(uname -s)" != "Darwin" ]; then
  echo "build_dmg: runs on macOS only (hdiutil)" >&2
  exit 1
fi
if [ ! -x "$APP/Contents/MacOS/Brimline" ]; then
  echo "build_dmg: no app at $APP, run scripts/build_app.sh first" >&2
  exit 1
fi

VERSION="$(tr -d '[:space:]' < VERSION)"
PLIST_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
if [ "$PLIST_VERSION" != "$VERSION" ]; then
  echo "build_dmg: $APP is version $PLIST_VERSION, the sources are $VERSION: rebuild it" >&2
  exit 1
fi

PYTHON="${PYTHON:-python3}"
if ! "$PYTHON" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
  echo "build_dmg: needs Python 3.10 or later, found: $("$PYTHON" --version 2>&1 || echo none)." >&2
  echo "build_dmg: install one (python.org or Homebrew), or set PYTHON=/path/to/python3." >&2
  exit 1
fi

VENV="$ROOT/.build/dmg-venv"
if [ ! -x "$VENV/bin/dmgbuild" ] || ! cmp -s packaging/requirements-dmg.txt "$VENV/requirements-dmg.txt"; then
  echo "==> Python tools (dmgbuild, Pillow) in $VENV"
  rm -rf "$VENV"
  "$PYTHON" -m venv "$VENV"
  "$VENV/bin/python" -m pip install --quiet --disable-pip-version-check --require-hashes -r packaging/requirements-dmg.txt
  cp packaging/requirements-dmg.txt "$VENV/requirements-dmg.txt"
fi

DMG="Brimline.dmg"
mkdir -p "$OUT_DIR"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/brimline-dmg.XXXXXX")"
MNT="$WORK/mnt"
cleanup() {
  hdiutil detach "$MNT" -quiet >/dev/null 2>&1 || true
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "==> Background (1x and Retina 2x)"
"$VENV/bin/python" packaging/make_dmg_background.py "$WORK/bg" >/dev/null

echo "==> Disk image $DMG (Brimline $VERSION)"
rm -f "$OUT_DIR/$DMG" "$OUT_DIR/$DMG.sha256"
"$VENV/bin/dmgbuild" -s packaging/dmg_settings.py \
  -D "app=$APP" -D "background=$WORK/bg/background.png" \
  -D "icon=$APP/Contents/Resources/AppIcon.icns" \
  "Brimline" "$OUT_DIR/$DMG"

echo "==> Checking the image"
hdiutil verify "$OUT_DIR/$DMG" >/dev/null
mkdir -p "$MNT"
hdiutil attach "$OUT_DIR/$DMG" -readonly -nobrowse -noautoopen -mountpoint "$MNT" >/dev/null
STATUS=0
for f in "Brimline.app/Contents/MacOS/Brimline" "Brimline.app/Contents/Helpers/brimline" ".background.tiff" ".DS_Store"; do
  [ -e "$MNT/$f" ] || { echo "build_dmg: missing in the image: $f" >&2; STATUS=1; }
done
if [ "$(readlink "$MNT/Applications")" != "/Applications" ]; then
  echo "build_dmg: the Applications shortcut does not point to /Applications" >&2
  STATUS=1
fi
codesign --verify --deep --strict "$MNT/Brimline.app" || STATUS=1
hdiutil detach "$MNT" -quiet || hdiutil detach "$MNT" -force -quiet
[ "$STATUS" -eq 0 ] || exit 1

(cd "$OUT_DIR" && shasum -a 256 "$DMG" > "$DMG.sha256" && cat "$DMG.sha256")
echo "Built $OUT_DIR/$DMG (Brimline $VERSION)"
