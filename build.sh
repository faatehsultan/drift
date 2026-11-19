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

# Media from other apps (Chrome, Safari, Spotify…): build the MediaRemote adapter
# (BSD-3, vendored in Vendor/mediaremote-adapter). It's loaded by /usr/bin/perl, not linked.
MRA=Vendor/mediaremote-adapter
FWK="$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
mkdir -p "$FWK/Versions/A/Resources"
clang -dynamiclib -fobjc-arc -fvisibility=default -O2 -mmacosx-version-min=13.0 \
  -I "$MRA/include" -I "$MRA/src" \
  $(find "$MRA/src/adapter" "$MRA/src/private" "$MRA/src/utility" -name '*.m' ! -name test.m) \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$FWK/Versions/A/MediaRemoteAdapter"
cat > "$FWK/Versions/A/Resources/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.drift.MediaRemoteAdapter</string>
  <key>CFBundleExecutable</key><string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key><string>FMWK</string>
  <key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
ln -sfn A "$FWK/Versions/Current"
ln -sfn Versions/Current/MediaRemoteAdapter "$FWK/MediaRemoteAdapter"
ln -sfn Versions/Current/Resources "$FWK/Resources"
cp "$MRA/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || codesign --force --deep --sign - "$APP"
echo "Built $APP (v$VERSION, build $BUILD)"

if [ "${1:-}" = "run" ]; then
  pkill -x Drift 2>/dev/null || true
  open "$APP"
fi
