#!/bin/bash
# Checks the signature of a Brimline.app built by scripts/build_app.sh with Brimline's identity.
#
#   scripts/check_signature.sh build/Brimline.app
#
# Needs BRIMLINE_SIGNING_IDENTITY and BRIMLINE_SIGNING_KEYCHAIN (the SHA-1 of the certificate and its
# keychain), as scripts/build_app.sh does. It checks that:
# 1. the signature is valid, deep and strict (codesign -v);
# 2. the identifier is eu.thanaelfontaine.brimline and the authority is "Brimline Code Signing";
# 3. the designated requirement names that identifier and that certificate, not the hash of the build;
# 4. a second build, which has another code hash, satisfies the requirement of the first
#    (codesign -v -R): this is what lets the Accessibility permission outlive an update.
# Nothing is created outside a temporary folder, removed at the end. It prints no secret.
set -euo pipefail

APP="${1:?usage: check_signature.sh path/to/Brimline.app}"
IDENTITY="${BRIMLINE_SIGNING_IDENTITY:?BRIMLINE_SIGNING_IDENTITY is not set}"
KEYCHAIN="${BRIMLINE_SIGNING_KEYCHAIN:?BRIMLINE_SIGNING_KEYCHAIN is not set}"
LEAF="$(printf '%s' "$IDENTITY" | tr 'A-F' 'a-f')"

fail() { echo "check_signature: $*" >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$APP"

DETAILS="$(codesign -dvv "$APP" 2>&1)"
printf '%s\n' "$DETAILS" | grep -qx 'Identifier=eu.thanaelfontaine.brimline' || fail "the identifier is not eu.thanaelfontaine.brimline"
printf '%s\n' "$DETAILS" | grep -qx 'Authority=Brimline Code Signing' || fail "the authority is not Brimline Code Signing"

REQUIREMENT="$(codesign -d -r- "$APP" 2>/dev/null | sed -n 's/^designated => //p')"
case "$REQUIREMENT" in
  # A self-signed certificate is its own root: macOS writes "root" or "leaf", the same certificate.
  'identifier "eu.thanaelfontaine.brimline" and certificate root = H"'"$LEAF"'"' \
  | 'identifier "eu.thanaelfontaine.brimline" and certificate leaf = H"'"$LEAF"'"') ;;
  *) fail "unexpected designated requirement: $REQUIREMENT" ;;
esac
echo "Designated requirement: $REQUIREMENT"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
SECOND="$WORK/Brimline.app"
ditto "$APP" "$SECOND"
printf 'second build\n' > "$SECOND/Contents/Resources/second-build.txt"
codesign --force --deep -s "$IDENTITY" --keychain "$KEYCHAIN" "$SECOND/Contents/Helpers/brimline"
codesign --force --deep -s "$IDENTITY" --keychain "$KEYCHAIN" "$SECOND"
HASH_FIRST="$(codesign -dvvv "$APP" 2>&1 | sed -n 's/^CDHash=//p')"
HASH_SECOND="$(codesign -dvvv "$SECOND" 2>&1 | sed -n 's/^CDHash=//p')"
[ -n "$HASH_FIRST" ] && [ "$HASH_FIRST" != "$HASH_SECOND" ] || fail "the second build does not have another code hash"
codesign -v -R "=$REQUIREMENT" "$SECOND" || fail "a second build does not satisfy the requirement of the first"
echo "Signature of $APP checked: valid, Brimline Code Signing, one requirement for two builds (code hashes differ)."
