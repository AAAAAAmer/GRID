#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "========================================="
echo "       Installing Native GRID.app        "
echo "========================================="

# 1. Build
./build.sh

# 2. Stop running instance
killall GRID 2>/dev/null || true
sleep 1

# 3. One-time migration of profiles from the project folder to Application Support
SUPPORT_DIR="$HOME/Library/Application Support/GRID"
if [ -f "$DIR/profiles.json" ] && [ ! -f "$SUPPORT_DIR/profiles.json" ]; then
    echo "🗂  Migrating profiles.json to $SUPPORT_DIR..."
    mkdir -p "$SUPPORT_DIR"
    cp "$DIR/profiles.json" "$SUPPORT_DIR/profiles.json"
fi

# 4. Copy to /Applications & clean temporary build
echo "📦 Installing to /Applications/GRID.app..."
rm -rf "/Applications/GRID.app"
cp -R "build/GRID.app" "/Applications/GRID.app"
rm -rf "$DIR/build"

# 5. Launch
echo "🚀 Launching GRID.app..."
open "/Applications/GRID.app"

echo "========================================="
echo "🎉 GRID.app is now running from /Applications!"
echo "   Look for '⊞ GRID' in your top Menu Bar."
echo "========================================="
