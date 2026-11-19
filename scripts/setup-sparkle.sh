#!/bin/bash
# One-time: downloads Sparkle's CLI tools, creates your update-signing key
# (stored in your login Keychain) and puts the public key in Info.plist.
set -euo pipefail
cd "$(dirname "$0")/.."

SPARKLE_VERSION=2.10.1
TOOLS=.tools/sparkle
if [ ! -x "$TOOLS/bin/sign_update" ]; then
  mkdir -p "$TOOLS"
  curl -fL -o /tmp/sparkle.tar.xz \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz"
  tar -xf /tmp/sparkle.tar.xz -C "$TOOLS"
fi

"$TOOLS/bin/generate_keys" >/dev/null
KEY="$("$TOOLS/bin/generate_keys" -p)"
/usr/libexec/PlistBuddy -c "Delete :SUPublicEDKey" Resources/Info.plist 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $KEY" Resources/Info.plist

echo "Public key added to Resources/Info.plist: $KEY"
echo
echo "IMPORTANT: back up the private key somewhere safe (NOT in git). Lose it and you can't ship updates:"
echo "  $TOOLS/bin/generate_keys -x ~/drift-sparkle-private-key.txt"
