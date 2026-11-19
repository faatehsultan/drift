#!/bin/bash
# Builds build/Drift.app. Pass "run" to launch it afterwards.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(cat VERSION)"
BUILD="$(cat BUILD_NUMBER)"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"

APP="build/Drift.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/Drift" "$APP/Contents/MacOS/Drift"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

PB=/usr/libexec/PlistBuddy
$PB -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
$PB -c "Set :CFBundleVersion $BUILD" "$APP/Contents/Info.plist"

# Embed Sparkle (auto-updates).
FW="$(find "$BIN_DIR" .build -type d -name Sparkle.framework -not -path '*/Sparkle.framework/*' 2>/dev/null \
      | grep -v -E 'ios|tvos|watchos|xros|maccatalyst' | head -1 || true)"
if [ -z "$FW" ]; then
  echo "error: Sparkle.framework not found after build" >&2
  exit 1
fi
ditto "$FW" "$APP/Contents/Frameworks/Sparkle.framework"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP"
echo "Built $APP (v$VERSION, build $BUILD)"

if [ "${1:-}" = "run" ]; then
  pkill -x Drift 2>/dev/null || true
  open "$APP"
fi
