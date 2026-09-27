#!/usr/bin/env bash
# Packages build/DaVinci Cleaner.app into build/DaVinci-Cleaner.dmg with a drag-to-Applications layout.
set -euo pipefail

cd "$(dirname "$0")/.."
APP="build/DaVinci Cleaner.app"
DMG="build/DaVinci-Cleaner.dmg"
STAGING="build/dmg"

[ -d "$APP" ] || { echo "Run scripts/build-app.sh first"; exit 1; }

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create -volname "DaVinci Cleaner" -srcfolder "$STAGING" -ov -format UDZO "$DMG"
rm -rf "$STAGING"
echo "✓ Created $DMG"
