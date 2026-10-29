#!/bin/bash
# Imports Brimline's signing identity into a keychain of this CI run (the release and its dry run).
#
#   P12=<base64 of the .p12> P12_PASSWORD=<its password> scripts/import_signing_identity.sh
#
# Needs RUNNER_TEMP and GITHUB_ENV (set by GitHub Actions). Creates the keychain
# $RUNNER_TEMP/brimline-signing.keychain-db, imports the certificate and its key, and writes
# BRIMLINE_SIGNING_IDENTITY (the SHA-1 of the "Brimline Code Signing" identity) and
# BRIMLINE_SIGNING_KEYCHAIN to GITHUB_ENV for scripts/build_app.sh. The workflow deletes the keychain
# at the end of the run. Without the two secrets it fails: no build is signed with another identity.
#
# The certificate is self-signed, so macOS lists it as "not trusted" (CSSMERR_TP_NOT_TRUSTED). On the
# runner, codesign then finds the identity only if its keychain is in the search list of the user
# (--keychain does not replace that): without it, "<sha1>: no identity found". So the keychain is put
# first in the list, with the existing ones after it. No trust setting is changed (checked on the
# runner, macOS 26: the identity then signs, with or without --keychain, nothing needs sudo). The
# deletion of the keychain at the end of the run takes it out of the list.
set -euo pipefail

if [ -z "${P12:-}" ] || [ -z "${P12_PASSWORD:-}" ]; then
  echo "::error::The secrets BRIMLINE_SIGNING_P12 and BRIMLINE_SIGNING_P12_PASSWORD are missing: no signed build without Brimline's signature."
  exit 1
fi
: "${RUNNER_TEMP:?}" "${GITHUB_ENV:?}"

KEYCHAIN="$RUNNER_TEMP/brimline-signing.keychain-db"
KEYCHAIN_PASSWORD="$(openssl rand -hex 24)"
security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
SEARCH_LIST=()
while IFS= read -r line; do
  line="${line#*\"}"
  SEARCH_LIST+=("${line%\"*}")
done < <(security list-keychains -d user)
security list-keychains -d user -s "$KEYCHAIN" ${SEARCH_LIST[@]+"${SEARCH_LIST[@]}"}
printf '%s' "$P12" | base64 -D > "$RUNNER_TEMP/brimline-signing.p12"
security import "$RUNNER_TEMP/brimline-signing.p12" -k "$KEYCHAIN" -P "$P12_PASSWORD" -T /usr/bin/codesign >/dev/null
rm -f "$RUNNER_TEMP/brimline-signing.p12"
security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null
IDENTITY="$(security find-identity -p codesigning "$KEYCHAIN" | awk '/"Brimline Code Signing"/ { print $2; exit }')"
if [ -z "$IDENTITY" ]; then
  echo "::error::No \"Brimline Code Signing\" identity in BRIMLINE_SIGNING_P12."
  exit 1
fi
echo "BRIMLINE_SIGNING_IDENTITY=$IDENTITY" >> "$GITHUB_ENV"
echo "BRIMLINE_SIGNING_KEYCHAIN=$KEYCHAIN" >> "$GITHUB_ENV"
