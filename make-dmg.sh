#!/bin/zsh
# Builds Wombat.app and packages it as build/Wombat.dmg (drag-to-Applications installer).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

STAGING=build/dmg
DMG=build/Wombat.dmg
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R build/Wombat.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname Wombat -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
echo "Built $DMG"
