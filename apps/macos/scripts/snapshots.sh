#!/usr/bin/env bash
# Builds the app incrementally with SwiftPM and renders the menu, Settings and motion snapshots in
# parallel, so a view change shows in seconds. APP=<an .app under build/> renders from that bundle instead.
set -euo pipefail

# Paths from the caller are relative to where they ran this, so fix them before changing directory.
absolute() { if [[ "$1" == /* ]]; then echo "$1"; else echo "$PWD/$1"; fi; }
OUT="${1:+$(absolute "$1")}"
# The real path, so the location check below can't be passed with `..` or failed by `./`.
[[ -z "${APP:-}" ]] || APP="$(CDPATH='' cd "$APP" && pwd -P)"
cd "$(dirname "$0")/.."
# Inside the checkout by default, so runs in other worktrees don't overwrite each other's renders.
OUT="${OUT:-$PWD/build/snapshots}"
# Only this checkout's builds: a bundle from elsewhere can pass the date check below and still not know
# a flag, and a build that doesn't know a snapshot flag launches for real.
[[ -z "${APP:-}" || "$APP" == "$(pwd -P)"/build/* ]] || { echo "APP must be a bundle under $PWD/build" >&2; exit 1; }

# One entry per render: "<file name> <flag> [words]". Add a snapshot word by adding a line here.
RENDERS=(
  "menu --snapshot"
  "menu-expanded --snapshot expanded"
  "menu-crowded --snapshot crowded"
  "menu-crowded-expanded --snapshot crowded expanded"
  "menu-tall --snapshot tall"
  "menu-tall-crowded --snapshot tall crowded"
  "settings-general --snapshot-settings general"
  "settings-power --snapshot-settings power"
  "settings-agents --snapshot-settings agents"
  "settings-limits --snapshot-settings limits"
  "settings-hub --snapshot-settings hub"
  "motion-limits --snapshot-motion limits"
  "motion-pool --snapshot-motion pool"
  "motion-pause --snapshot-motion pause"
)
# The app exits on a snapshot flag it doesn't know, and launches for real on anything else, so check
# the whole list before anything runs.
for entry in "${RENDERS[@]}"; do
  read -ra parts <<< "$entry"
  [[ "${parts[1]}" == --snapshot* ]] || { echo "Each RENDERS flag must start with --snapshot: $entry" >&2; exit 1; }
done

# The build runs here and not inside a command substitution, where bash ignores `set -e`, so a failed
# build stops the script instead of rendering from the last binary that compiled.
if [[ -z "${APP:-}" ]]; then
  swift build --package-path . >&2
  APP=build/Dev.app
  rm -rf "$APP"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp Resources/Info.plist "$APP/Contents/"
  # A different identifier and name, so nothing mistakes this bundle for the installed app.
  plutil -replace CFBundleIdentifier -string app.afterhours.dev "$APP/Contents/Info.plist"
  plutil -replace CFBundleName -string "Afterhours Dev" "$APP/Contents/Info.plist"
  plutil -replace CFBundleDisplayName -string "Afterhours Dev" "$APP/Contents/Info.plist"
  cp -R Resources/agents "$APP/Contents/Resources/"
  cp "$(swift build --package-path . --show-bin-path)/Afterhours" "$APP/Contents/MacOS/"
fi

BIN="$APP/Contents/MacOS/Afterhours"
[[ -x "$BIN" ]] || { echo "No Afterhours binary at $BIN" >&2; exit 1; }
# A binary older than what it is built from may not know one of the flags above, and would draw old
# pictures in any case.
if [[ -n "$(find Sources ../../packages/core/Sources Resources -type f -newer "$BIN" -print -quit)" ]]; then
  echo "$BIN is older than the sources. Rebuild it first." >&2
  exit 1
fi

mkdir -p "$OUT"
pids=()
names=()
for entry in "${RENDERS[@]}"; do
  read -ra parts <<< "$entry"
  name="${parts[0]}"
  rm -f "$OUT/$name.png"
  # Each render gets a flag and an output path, so the app exits after drawing instead of running.
  "$BIN" "${parts[1]}" "$OUT/$name.png" "${parts[@]:2}" > /dev/null 2>&1 &
  pids+=($!)
  names+=("$name")
done

# A render exits within seconds. One still running after a minute launched for real, so stop it.
deadline=$((SECONDS + 60))
while [[ -n "$(jobs -rp)" ]] && ((SECONDS < deadline)); do sleep 0.2; done
for pid in $(jobs -rp); do kill "$pid" 2> /dev/null || true; done

failed=0
for i in "${!pids[@]}"; do
  wait "${pids[$i]}" || true
  if [[ -s "$OUT/${names[$i]}.png" ]]; then
    echo "$OUT/${names[$i]}.png"
  else
    echo "Missing or empty: $OUT/${names[$i]}.png" >&2
    failed=1
  fi
done
exit "$failed"
