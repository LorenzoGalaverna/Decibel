#!/bin/bash
set -e

# Decibel DMG Build Script
# Requires: Xcode, Node.js 18+, GraphicsMagick, ImageMagick
# Install dependencies: brew install graphicsmagick imagemagick

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"

echo "==> Cleaning build directory..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building release app (ad-hoc signed, no Developer ID needed)..."
xcodebuild build \
    -project "$PROJECT_DIR/Decibel.xcodeproj" \
    -scheme Decibel \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR/dd" \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGN_STYLE=Manual \
    DEVELOPMENT_TEAM="" \
    PROVISIONING_PROFILE_SPECIFIER=""

cp -R "$BUILD_DIR/dd/Build/Products/Release/Decibel.app" "$BUILD_DIR/Decibel.app"

echo "==> Creating DMG..."
# create-dmg auto-generates professional layout with:
# - App icon composited onto disk icon
# - "Drag to Applications" layout
npx --yes create-dmg "$BUILD_DIR/Decibel.app" "$BUILD_DIR" --overwrite

echo "==> Done!"
echo "DMG created at: $BUILD_DIR/"
ls -la "$BUILD_DIR"/*.dmg
