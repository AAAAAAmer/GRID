#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIR/Info.plist")"
DIST_DIR="$DIR/dist"
DMG_PATH="$DIST_DIR/GRID-$VERSION.dmg"

echo "========================================="
echo "     Packaging GRID $VERSION for release "
echo "========================================="

# 1. Universal build (Apple Silicon + Intel)
GRID_UNIVERSAL=1 ./build.sh

# 2. Stage the DMG contents: the app plus a shortcut to /Applications for drag-to-install
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
cp -R "$DIR/build/GRID.app" "$STAGE_DIR/GRID.app"
ln -s /Applications "$STAGE_DIR/Applications"

# 3. Create the compressed disk image
echo "💿 Creating $DMG_PATH..."
mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH"
hdiutil create -volname "GRID $VERSION" -srcfolder "$STAGE_DIR" -ov -format UDZO "$DMG_PATH" >/dev/null

# 4. Checksum so users can verify the download
( cd "$DIST_DIR" && shasum -a 256 "GRID-$VERSION.dmg" > "GRID-$VERSION.dmg.sha256" )

rm -rf "$DIR/build"

echo "========================================="
echo "✅ Release artifacts:"
echo "   $DMG_PATH"
echo "   $DMG_PATH.sha256"
echo "========================================="
