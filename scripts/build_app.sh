#!/bin/bash
# Builds build/Brimline.app from the sources, with the Command Line Tools only (no Xcode).
#
#   scripts/build_app.sh
#
# 1. swift build -c release, for Apple silicon and Intel (one universal binary each for the app and
#    the `brimline` command);
# 2. assembles the bundle: Info.plist (version read from VERSION, menu bar app without Dock icon),
#    icon, and the command in Contents/Helpers/;
# 3. signs it with Brimline's own identity when it is there, ad hoc (codesign -s -) otherwise: no
#    Apple Developer identity in either case, so macOS treats it as an app built on this Mac. See
#    docs/install.md.
#
# Brimline's identity, "Brimline Code Signing", is a self-signed certificate. Signed with it, every
# build has the same designated requirement (its identifier and that certificate), so the
# Accessibility permission given to one version still covers the next one. An ad hoc build is known
# by its hash only: the permission covers that build alone. The identity is found in:
#   BRIMLINE_SIGNING_IDENTITY and BRIMLINE_SIGNING_KEYCHAIN (the SHA-1 of the certificate and its
#   keychain), set by the release workflow from its secrets;
#   or, on the maintainer's Mac, ~/Library/Keychains/brimline-signing.keychain-db, unlocked with the
#   password kept in the login keychain under the service brimline-signing-keychain.
# Without either (a fork, a contributor), the build is ad hoc. A certificate other than the one
# below is refused: it would take the permission away from every user at the next update.
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

# The SHA-1 of Brimline's certificate (valid until 24 October 2046).
BRIMLINE_CERT_SHA1="28E5BDC0D2C3E5EEFD43C9C42FEAE493167F47B4"
IDENTITY="${BRIMLINE_SIGNING_IDENTITY:-}"
KEYCHAIN="${BRIMLINE_SIGNING_KEYCHAIN:-}"
LOCAL_KEYCHAIN="$HOME/Library/Keychains/brimline-signing.keychain-db"
if [ -z "$IDENTITY" ] && [ -f "$LOCAL_KEYCHAIN" ] \
   && KEYCHAIN_PASSWORD="$(security find-generic-password -s brimline-signing-keychain -w 2>/dev/null)"; then
  security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$LOCAL_KEYCHAIN"
  unset KEYCHAIN_PASSWORD
  KEYCHAIN="$LOCAL_KEYCHAIN"
  IDENTITY="$(security find-identity -p codesigning "$LOCAL_KEYCHAIN" | awk '/"Brimline Code Signing"/ { print $2; exit }')"
fi
SIGN=(-s -)
KIND="ad hoc signature"
if [ -n "$IDENTITY" ]; then
  if [ "$IDENTITY" != "$BRIMLINE_CERT_SHA1" ]; then
    echo "build_app: the signing identity $IDENTITY is not Brimline's certificate ($BRIMLINE_CERT_SHA1)" >&2
    exit 1
  fi
  SIGN=(-s "$IDENTITY")
  [ -n "$KEYCHAIN" ] && SIGN+=(--keychain "$KEYCHAIN")
  KIND="signed by Brimline Code Signing"
fi

# The helper first, then the bundle (which seals the helper).
codesign --force "${SIGN[@]}" "$APP/Contents/Helpers/brimline"
codesign --force --deep "${SIGN[@]}" "$APP"
codesign --verify --deep --strict "$APP"
if [ -n "$IDENTITY" ]; then
  LEAF="$(printf '%s' "$BRIMLINE_CERT_SHA1" | tr 'A-F' 'a-f')"
  REQUIREMENT="$(codesign -d -r- "$APP" 2>/dev/null)"
  case "$REQUIREMENT" in
    # A self-signed certificate is its own root: macOS writes "root" or "leaf", the same certificate.
    *'identifier "eu.thanaelfontaine.brimline" and certificate root = H"'"$LEAF"'"'* \
    | *'identifier "eu.thanaelfontaine.brimline" and certificate leaf = H"'"$LEAF"'"'*) ;;
    *) echo "build_app: unexpected designated requirement: $REQUIREMENT" >&2; exit 1 ;;
  esac
fi
for exe in "$APP/Contents/MacOS/Brimline" "$APP/Contents/Helpers/brimline"; do
  [ "$(lipo -archs "$exe")" = "x86_64 arm64" ] || { echo "build_app: $exe is not universal ($(lipo -archs "$exe"))" >&2; exit 1; }
done

echo "Built $APP (version $VERSION, Apple silicon and Intel, $KIND)"
