#!/usr/bin/env bash
set -e

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DIR"

echo "========================================="
echo "       Building Native GRID.app          "
echo "========================================="

BUILD_DIR="$DIR/build"
APP_DIR="$BUILD_DIR/GRID.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

# 1. Clean
rm -rf "$BUILD_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

# 2. Copy Plist & Resources
cp "$DIR/Info.plist" "$CONTENTS_DIR/Info.plist"
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"
if [ -d "$DIR/assets" ]; then
    cp -R "$DIR/assets/"* "$RESOURCES_DIR/"
fi

# 3. Compile Swift package
#    GRID_UNIVERSAL=1 builds a universal binary (Apple Silicon + Intel) for distribution.
if [ "$GRID_UNIVERSAL" = "1" ]; then
    echo "🔨 Compiling Swift sources (universal: arm64 + x86_64)..."
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
else
    echo "🔨 Compiling Swift sources for Apple Silicon..."
    ARCH_FLAGS=(--arch arm64)
fi
swift build -c release "${ARCH_FLAGS[@]}"
BIN_DIR="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"
cp "$BIN_DIR/GRID" "$MACOS_DIR/GRID"

# 4. Codesign
#    Set GRID_SIGN_IDENTITY (e.g. "Apple Development: Name (TEAMID)") to sign with a real certificate.
#    Otherwise ad-hoc sign with a stable designated requirement so Accessibility trust survives rebuilds.
echo "🔐 Signing GRID.app bundle..."
if [ -n "$GRID_SIGN_IDENTITY" ]; then
    codesign --force --sign "$GRID_SIGN_IDENTITY" --identifier "com.amer.grid" "$APP_DIR"
else
    codesign --force --sign - --identifier "com.amer.grid" -r='designated => identifier "com.amer.grid"' "$APP_DIR"
fi

echo "========================================="
echo "✅ GRID.app built successfully at:"
echo "   $APP_DIR"
echo "========================================="
