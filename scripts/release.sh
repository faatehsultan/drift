#!/bin/bash
# Usage: scripts/release.sh [patch|minor|major]
# Bumps the version, builds, packages a .zip (for auto-update) and Drift.dmg (for the website),
# publishes a GitHub release, then updates docs/appcast.xml so installed copies see the update.
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="faatehsultan/drift"
TOOLS=.tools/sparkle

[ -x "$TOOLS/bin/sign_update" ] || { echo "Run scripts/setup-sparkle.sh first" >&2; exit 1; }
command -v gh >/dev/null || { echo "Install the GitHub CLI first: brew install gh && gh auth login" >&2; exit 1; }
[ -z "$(git status --porcelain)" ] || { echo "Commit or stash your changes first" >&2; exit 1; }

scripts/bump.sh "${1:-patch}"
V="$(cat VERSION)"
B="$(cat BUILD_NUMBER)"

./build.sh

mkdir -p dist
ZIP="dist/Drift-$V.zip"
DMG="dist/Drift.dmg"
rm -f "$ZIP" "$DMG"
ditto -c -k --sequesterRsrc --keepParent build/Drift.app "$ZIP"
hdiutil create -volname "Drift" -srcfolder build/Drift.app -ov -format UDZO "$DMG" >/dev/null

# Release notes: commit subjects since the previous tag.
PREV="$(git describe --tags --abbrev=0 "v$V^" 2>/dev/null || true)"
if [ -n "$PREV" ]; then
  SUBJECTS="$(git log --pretty='%s' "$PREV..v$V^" | grep -v -E '^(Release v|Appcast for v)' || true)"
else
  SUBJECTS="First release"
fi
[ -n "$SUBJECTS" ] || SUBJECTS="Bug fixes and improvements"
NOTES_MD="$(echo "$SUBJECTS" | sed 's/^/- /')"
NOTES_HTML="$(echo "$SUBJECTS" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' | sed 's#^.*$#<li>&</li>#' | tr -d '\n')"

# 1. Push the tag and publish the files.
git push origin main --tags
gh release create "v$V" "$ZIP" "$DMG" --repo "$REPO" --title "Drift $V" --notes "$NOTES_MD"

# 2. Then tell installed apps about it.
SIG="$("$TOOLS/bin/sign_update" "$ZIP")"
URL="https://github.com/$REPO/releases/download/v$V/Drift-$V.zip"
DATE="$(LC_ALL=C date -u '+%a, %d %b %Y %H:%M:%S +0000')"
cat > /tmp/drift-item.xml <<ITEM
    <item>
      <title>Version $V</title>
      <pubDate>$DATE</pubDate>
      <sparkle:version>$B</sparkle:version>
      <sparkle:shortVersionString>$V</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
      <description><![CDATA[<ul>$NOTES_HTML</ul>]]></description>
      <enclosure url="$URL" type="application/octet-stream" $SIG />
    </item>
ITEM
awk -v f=/tmp/drift-item.xml '{ print } /<!-- ITEMS -->/ { while ((getline line < f) > 0) print line }' \
  docs/appcast.xml > /tmp/drift-appcast.xml
mv /tmp/drift-appcast.xml docs/appcast.xml

git add docs/appcast.xml
git commit -q -m "Appcast for v$V"
git push origin main

echo
echo "Released Drift $V. Installed copies will offer it within a day (or via Check for Updates…)."
