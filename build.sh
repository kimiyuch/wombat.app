#!/bin/bash
# Builds Wombat.app from source. Needs Xcode or the Command Line Tools.
set -euo pipefail
cd "$(dirname "$0")"

echo "Compiling…"
swift build -c release
BIN="$(swift build -c release --show-bin-path)/Wombat"

APP="build/Wombat.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wombat"
cp Info.plist "$APP/Contents/Info.plist"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"   # Figtree, SIL Open Font License (OFL.txt)

echo "Making the icon…"
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET"; mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "Signing (ad hoc, for this Mac)…"
codesign --force --deep --sign - "$APP"

echo
echo "Done: $(pwd)/$APP"
echo "Install it with:  rm -rf /Applications/Wombat.app && mv \"$APP\" /Applications/ && open /Applications/Wombat.app"
