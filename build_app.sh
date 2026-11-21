#!/bin/bash
# Builds Marquee.app into ./build. Needs Xcode or the Command Line Tools (xcode-select --install).
set -euo pipefail
cd "$(dirname "$0")"

echo "→ Compiling (release)…"
swift build -c release

BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/Marquee.app"

echo "→ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Marquee" "$APP/Contents/MacOS/Marquee"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "→ Signing (ad-hoc, for this Mac only)"
codesign --force --deep --sign - "$APP"

echo
echo "Done: $(pwd)/$APP"
echo "Drag it into /Applications, or run:  open \"$APP\""
