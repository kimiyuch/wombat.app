#!/bin/zsh
# Builds a release and publishes it to GitHub Releases.
#
#   ./release.sh 0.2
#
# The release notes are the version's section in CHANGELOG.md ("## 0.2 (date)"), which has to exist.
# CHANGELOG.md is attached to the release too: wombat.kimiyu.ch builds its changelog page from it.
#
# Environment:
#   PUBLISH=0    build into build/release without bumping git or uploading (for testing)
set -euo pipefail
cd "$(dirname "$0")"
source ./release.env

VERSION=${1:?usage: ./release.sh <version>}
PUBLISH=${PUBLISH:-1}
TAG="v$VERSION"
PLIST=Info.plist
OUT=build/release

# Everything between this version's heading and the next one, without surrounding blank lines.
NOTES=$(awk -v v="$VERSION" '/^## / { found = ($2 == v); next } found' CHANGELOG.md \
  | sed -e '/./,$!d' | sed -e ':a' -e '/^\n*$/{$d;N;ba' -e '}')

if [[ $PUBLISH == 1 ]]; then
  [[ -n $NOTES ]] || { echo "Add a '## $VERSION (date)' section to CHANGELOG.md first."; exit 1; }
  [[ -z $(git status --porcelain) ]] || { echo "Commit or stash your changes first."; exit 1; }
  gh auth status >/dev/null 2>&1 || { echo "GitHub CLI isn't logged in: run 'gh auth login'."; exit 1; }
fi

BUILD=$(( $(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" $PLIST) + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" -c "Set :CFBundleVersion $BUILD" $PLIST
echo "Building Wombat $VERSION ($BUILD)"

./make-dmg.sh

rm -rf "$OUT" && mkdir -p "$OUT"
cp build/Wombat.dmg "$OUT/Wombat.dmg"

if [[ $PUBLISH != 1 ]]; then
  echo "Built $OUT (not published)"
  exit 0
fi

git commit -q -am "Release $VERSION"
git tag "$TAG"
git push -q && git push -q origin "$TAG"
gh release create "$TAG" --repo "$REPO" --title "Wombat $VERSION" --notes "$NOTES" \
  "$OUT/Wombat.dmg" CHANGELOG.md
echo "Published Wombat $VERSION"
