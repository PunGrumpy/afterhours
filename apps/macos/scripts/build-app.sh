#!/usr/bin/env bash
# Builds "build/Afterhours.app" (universal arm64 + x86_64) with plain swiftc, so it works with
# Command Line Tools alone. Pass --install to copy it to /Applications and launch it.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=build
APP="$OUT/Afterhours.app"
MIN_OS=14.0

# Command Line Tools can ship an SDK newer than its compiler; use the newest SDK this swiftc accepts.
pick_sdk() {
  local sdks_dir probe
  sdks_dir="$(dirname "$(xcrun --show-sdk-path)")"
  probe="$(mktemp -d)/probe.swift"
  echo 'import Foundation' > "$probe"
  for sdk in $(ls -d "$sdks_dir"/MacOSX[0-9]*.sdk | sort -rV); do
    if swiftc -sdk "$sdk" -typecheck "$probe" 2>/dev/null; then echo "$sdk"; return; fi
  done
  xcrun --show-sdk-path
}
SDK="${SDKROOT:-$(pick_sdk)}"
CORE=../../packages/core/Sources/AfterhoursCore
echo "SDK: $SDK"

compile_arch() {
  local arch=$1 dir="$OUT/$1"
  # Swift 6 language mode with Approachable Concurrency.
  local swiftc=(swiftc -sdk "$SDK" -target "$arch-apple-macos$MIN_OS" -O -swift-version 6
    -enable-upcoming-feature NonisolatedNonsendingByDefault
    -enable-upcoming-feature InferIsolatedConformances)
  mkdir -p "$dir"
  # AfterhoursCore is a library, so it stays nonisolated; the executables default to the main actor.
  "${swiftc[@]}" -parse-as-library -emit-library -static -module-name AfterhoursCore \
    -emit-module -emit-module-path "$dir/AfterhoursCore.swiftmodule" \
    -o "$dir/libAfterhoursCore.a" "$CORE"/*.swift
  "${swiftc[@]}" -default-isolation MainActor -I "$dir" -L "$dir" -lAfterhoursCore \
    -o "$dir/afterhours-hook" Sources/afterhours-hook/*.swift
  "${swiftc[@]}" -default-isolation MainActor -parse-as-library -I "$dir" -L "$dir" -lAfterhoursCore \
    -framework IOKit -framework Carbon -o "$dir/Afterhours" Sources/Afterhours/*.swift
}

ARCHS=(${ARCHS:-arm64 x86_64})
for arch in "${ARCHS[@]}"; do
  echo "Compiling ${arch}..."
  compile_arch "$arch"
done

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/"
# Changesets owns the version in package.json; the build number is the commit count.
VERSION="$(sed -n 's/^  "version": "\(.*\)",$/\1/p' package.json)"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$(git rev-list --count HEAD 2>/dev/null || echo 1)" "$APP/Contents/Info.plist"
cp -R Resources/agents "$APP/Contents/Resources/"
for bin in Afterhours afterhours-hook; do
  lipo -create $(printf "$OUT/%s/$bin " "${ARCHS[@]}") -output "$APP/Contents/MacOS/$bin"
done
codesign --force --sign - "$APP/Contents/MacOS/afterhours-hook"
codesign --force --sign - "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--install" ]]; then
  pkill -x Afterhours 2>/dev/null || true
  rm -rf "/Applications/Afterhours.app"
  cp -R "$APP" /Applications/
  open "/Applications/Afterhours.app"
  echo "Installed to /Applications"
fi
