#!/usr/bin/env bash
# Builds "DaVinci Cleaner.app" into ./build.
#   ./scripts/build-app.sh            # release build for this Mac
#   CONFIG=debug ./scripts/build-app.sh
#   UNIVERSAL=1 ./scripts/build-app.sh   # Apple Silicon + Intel
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${CONFIG:-release}"
APP="build/DaVinci Cleaner.app"

# UNIVERSAL=1 builds one app that runs natively on Apple Silicon and Intel Macs.
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

echo "▸ Building ($CONFIG)…"
swift build -c "$CONFIG" --product DaVinciCleaner ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"})"

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
