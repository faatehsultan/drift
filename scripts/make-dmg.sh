#!/bin/bash
# Usage: scripts/make-dmg.sh path/to/Drift.app path/to/Drift.dmg
# Builds a disk image with a background that shows "drag to Applications"
# and the one-time "Open Anyway" steps.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="$1"
OUT="$2"
VOL="Drift"
TMP="$(mktemp -d)"
RW="$TMP/rw.dmg"

mkdir -p "$TMP/stage/.background"
ditto "$APP" "$TMP/stage/Drift.app"
ln -s /Applications "$TMP/stage/Applications"
# Retina-aware background (1x + 2x in one TIFF).
tiffutil -cathidpicheck Resources/dmg/background.png Resources/dmg/background@2x.png \
  -out "$TMP/stage/.background/background.tiff" >/dev/null

hdiutil detach "/Volumes/$VOL" -quiet 2>/dev/null || true
hdiutil create -srcfolder "$TMP/stage" -volname "$VOL" -fs HFS+ -format UDRW -ov "$RW" >/dev/null
MNT="$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"

# Lay out the window (asks once for permission to control Finder).
osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 588}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 112
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "Drift.app" of container window to {170, 190}
    set position of item "Applications" of container window to {490, 190}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA

chmod -Rf go-w "$MNT" 2>/dev/null || true
sync
hdiutil detach "$MNT" -quiet || { sleep 2; hdiutil detach "$MNT" -force -quiet; }
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
rm -rf "$TMP"
echo "Made $OUT"
