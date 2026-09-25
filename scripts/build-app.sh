#!/usr/bin/env bash
# Builds "DaVinci Cleaner.app" into ./build.
#   ./scripts/build-app.sh            # release build for this Mac
#   CONFIG=debug ./scripts/build-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/DaVinci Cleaner.app"

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG" --product DaVinciCleaner
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

echo "▸ Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/DaVinciCleaner" "$APP/Contents/MacOS/DaVinciCleaner"
cp Support/Info.plist "$APP/Contents/Info.plist"

if [ ! -f Support/AppIcon.icns ]; then
    echo "▸ Drawing app icon…"
    rm -rf Support/AppIcon.iconset
    swift scripts/make-icon.swift Support/AppIcon.iconset
    iconutil -c icns Support/AppIcon.iconset -o Support/AppIcon.icns
fi
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

echo "▸ Signing (ad hoc)…"
codesign --force --deep --sign - "$APP"

echo "✓ Built $APP"
echo "  Open it with: open \"$APP\""
