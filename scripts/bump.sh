#!/bin/bash
# Usage: scripts/bump.sh [patch|minor|major]
# Bumps VERSION, increments BUILD, commits and tags vX.Y.Z.
set -euo pipefail
cd "$(dirname "$0")/.."

part="${1:-patch}"
IFS=. read -r MA MI PA < VERSION
case "$part" in
  major) MA=$((MA + 1)); MI=0; PA=0 ;;
  minor) MI=$((MI + 1)); PA=0 ;;
  patch) PA=$((PA + 1)) ;;
  *) echo "usage: scripts/bump.sh [patch|minor|major]" >&2; exit 1 ;;
esac
NEW="$MA.$MI.$PA"
BUILD=$(( $(cat BUILD_NUMBER) + 1 ))
echo "$NEW" > VERSION
echo "$BUILD" > BUILD_NUMBER

if git rev-parse --git-dir >/dev/null 2>&1; then
  git add VERSION BUILD_NUMBER
  git commit -q -m "Release v$NEW"
  git tag "v$NEW"
fi
echo "Bumped to v$NEW (build $BUILD)"
