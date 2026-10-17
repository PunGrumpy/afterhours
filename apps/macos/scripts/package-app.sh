#!/usr/bin/env bash
# Packages build/Afterhours.app into dist/ as a .dmg for people, a .zip for updaters, and SHA256SUMS.
# Run scripts/build-app.sh first. With CODESIGN_IDENTITY and an App Store Connect API key in
# NOTARY_KEY_PATH, NOTARY_KEY_ID, and NOTARY_ISSUER_ID, it also notarizes and staples the app and the .dmg.
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/Afterhours.app
OUT=dist
VERSION="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' package.json)"
NAME="Afterhours-$VERSION"

if [[ ! -d "$APP" ]]; then
  echo "No $APP. Run scripts/build-app.sh first." >&2
  exit 1
fi
rm -rf "$OUT"
mkdir -p "$OUT"

notarize() {
  local result id status
  # notarytool can exit non-zero on a rejection, and the log is what explains it.
  result="$(xcrun notarytool submit "$1" --wait --timeout 30m --output-format json \
    --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID")" || true
  id="$(jq -r '.id // empty' <<<"$result" 2>/dev/null || true)"
  status="$(jq -r '.status // empty' <<<"$result" 2>/dev/null || true)"
  if [[ "$status" != "Accepted" ]]; then
    echo "Notarization of $1 failed: $result" >&2
    if [[ -n "$id" ]]; then
      xcrun notarytool log "$id" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" >&2 || true
    fi
    exit 1
  fi
  echo "Notarized $1 ($id)"
}

NOTARIZE=false
if [[ -n "${NOTARY_KEY_ID:-}" ]]; then
  if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
    echo "Notarization needs an app signed with CODESIGN_IDENTITY." >&2
    exit 1
  fi
  if [[ -z "${NOTARY_KEY_PATH:-}" || -z "${NOTARY_ISSUER_ID:-}" ]]; then
    echo "Notarization needs NOTARY_KEY_PATH and NOTARY_ISSUER_ID too." >&2
    exit 1
  fi
  NOTARIZE=true
  # Staple the app before packaging, so both downloads open offline on the first launch.
  ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
  notarize "$OUT/notarize.zip"
  rm "$OUT/notarize.zip"
  xcrun stapler staple "$APP"
fi

ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"

# The Applications link lets people drag the app across in the mounted window.
staging="$(mktemp -d)"
ditto "$APP" "$staging/Afterhours.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Afterhours -srcfolder "$staging" -format UDZO "$OUT/$NAME.dmg"
rm -rf "$staging"
if [[ "$NOTARIZE" == true ]]; then
  codesign --sign "$CODESIGN_IDENTITY" --timestamp "$OUT/$NAME.dmg"
  notarize "$OUT/$NAME.dmg"
  xcrun stapler staple "$OUT/$NAME.dmg"
  codesign --verify --strict --deep "$APP"
  xcrun stapler validate "$APP"
  xcrun stapler validate "$OUT/$NAME.dmg"
  # Some CI images turn Gatekeeper's assessments off, and spctl then rejects everything.
  if spctl --status 2>/dev/null | grep -q "assessments enabled"; then
    spctl --assess --type execute -vv "$APP"
    spctl --assess --type open --context context:primary-signature -vv "$OUT/$NAME.dmg"
  else
    echo "Gatekeeper assessments are off here, so spctl was skipped."
  fi
fi

(cd "$OUT" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS)
echo "Packaged $OUT/$NAME.dmg and $OUT/$NAME.zip"
