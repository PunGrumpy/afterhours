#!/usr/bin/env bash
# Packages build/Afterhours.app into dist/ as a .dmg for people, a .zip for updaters, and SHA256SUMS.
# Run scripts/build-app.sh first.
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

ditto -c -k --keepParent "$APP" "$OUT/$NAME.zip"

# The Applications link lets people drag the app across in the mounted window.
staging="$(mktemp -d)"
ditto "$APP" "$staging/Afterhours.app"
ln -s /Applications "$staging/Applications"
hdiutil create -quiet -volname Afterhours -srcfolder "$staging" -format UDZO "$OUT/$NAME.dmg"
rm -rf "$staging"

(cd "$OUT" && shasum -a 256 "$NAME.dmg" "$NAME.zip" > SHA256SUMS)
echo "Packaged $OUT/$NAME.dmg and $OUT/$NAME.zip"
