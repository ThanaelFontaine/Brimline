#!/bin/bash
# Builds build/Brimline.app from the sources, with the Command Line Tools only (no Xcode).
#
#   scripts/build_app.sh
#
# 1. swift build -c release, for Apple silicon and Intel (one universal binary each for the app and
#    the `brimline` command);
# 2. assembles the bundle: Info.plist (version read from VERSION, menu bar app without Dock icon),
#    icon, and the command in Contents/Helpers/;
# 3. signs it ad hoc (codesign -s -): no Apple Developer identity, so macOS treats it as an app
#    built on this Mac. See docs/install.md.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(tr -d '[:space:]' < VERSION)"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "build_app: VERSION must look like 1.2.3, found '$VERSION'" >&2
  exit 1
fi

ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}" --product BrimlineApp
swift build -c release "${ARCHS[@]}" --product brimline
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)"

APP="$ROOT/build/Brimline.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Helpers" "$APP/Contents/Resources"
cp "$BIN/BrimlineApp" "$APP/Contents/MacOS/Brimline"
cp "$BIN/brimline" "$APP/Contents/Helpers/brimline"
cp "$ROOT/design/icons/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Declared languages, so macOS shows its own texts (menus, dialogs) in the user's language.
for lang in en fr; do
  mkdir -p "$APP/Contents/Resources/$lang.lproj"
  printf '"CFBundleName" = "Brimline";\n' > "$APP/Contents/Resources/$lang.lproj/InfoPlist.strings"
done

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Brimline</string>
  <key>CFBundleDisplayName</key><string>Brimline</string>
  <key>CFBundleIdentifier</key><string>eu.thanaelfontaine.brimline</string>
  <key>CFBundleExecutable</key><string>Brimline</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array><string>en</string><string>fr</string></array>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSHumanReadableCopyright</key><string>© 2026 Thanaël Fontaine. PolyForm Shield 1.0.0.</string>
</dict>
</plist>
PLIST
plutil -lint "$APP/Contents/Info.plist" >/dev/null

# Ad hoc signature: the helper first, then the bundle (which seals the helper).
codesign --force -s - "$APP/Contents/Helpers/brimline"
codesign --force --deep -s - "$APP"
codesign --verify --deep --strict "$APP"
for exe in "$APP/Contents/MacOS/Brimline" "$APP/Contents/Helpers/brimline"; do
  [ "$(lipo -archs "$exe")" = "x86_64 arm64" ] || { echo "build_app: $exe is not universal ($(lipo -archs "$exe"))" >&2; exit 1; }
done

echo "Built $APP (version $VERSION, Apple silicon and Intel, ad hoc signature)"
