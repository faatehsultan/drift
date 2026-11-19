#!/bin/bash
# Drift installer: downloads the latest release and puts it in /Applications.
#   curl -fsSL https://faatehsultan.github.io/drift/install.sh | bash
# Files downloaded with curl aren't quarantined, so macOS won't block the first launch.
# Read before you run: https://github.com/faatehsultan/drift/blob/main/docs/install.sh
set -euo pipefail

URL="https://github.com/faatehsultan/drift/releases/latest/download/Drift.dmg"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ "$(uname)" = "Darwin" ] || { echo "Drift only runs on macOS." >&2; exit 1; }

echo "→ Downloading Drift…"
curl -fL --progress-bar "$URL" -o "$TMP/Drift.dmg"

echo "→ Installing to /Applications…"
MNT="$(hdiutil attach -nobrowse -readonly -noautoopen "$TMP/Drift.dmg" | awk -F'\t' '/\/Volumes\//{print $NF}' | tail -1)"
osascript -e 'tell application "Drift" to quit' >/dev/null 2>&1 || true
rm -rf /Applications/Drift.app
ditto "$MNT/Drift.app" /Applications/Drift.app
hdiutil detach "$MNT" -quiet || true
xattr -dr com.apple.quarantine /Applications/Drift.app 2>/dev/null || true

echo "✓ Drift is installed. Opening it…"
open /Applications/Drift.app
echo "  Hover the notch to start. Drift updates itself from now on."
