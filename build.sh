#!/bin/bash
# Builds Portion.app and packages it into dist/Portion-<version>.dmg
# Usage: ./build.sh            (VERSION=1.2.0 ./build.sh to set the version)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Portion"
VERSION="${VERSION:-1.0.0}"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="dist"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"

rm -rf "$BUILD_DIR" && mkdir -p "$BUILD_DIR" "$DIST_DIR"

# --- Compile (universal when possible) -------------------------------------
binaries=()
for arch in arm64 x86_64; do
  echo "==> Building $arch"
  if swift build -c release --triple "$arch-apple-macosx13.0"; then
    bin_path="$(swift build -c release --triple "$arch-apple-macosx13.0" --show-bin-path)/$APP_NAME"
    cp "$bin_path" "$BUILD_DIR/$APP_NAME-$arch"
    binaries+=("$BUILD_DIR/$APP_NAME-$arch")
  else
    echo "!! $arch build failed; continuing without it" >&2
  fi
done
[ ${#binaries[@]} -gt 0 ] || { echo "Build failed" >&2; exit 1; }

# --- Assemble the .app bundle ------------------------------------------------
echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
sed "s/__VERSION__/$VERSION/g" Resources/Info.plist > "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "==> Generating icon"
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  swift Scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Ad-hoc signature (no Apple Developer account needed). Set SIGN_IDENTITY to use a real one.
echo "==> Signing"
codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP"
codesign --verify --verbose "$APP"

# --- Package the DMG ---------------------------------------------------------
echo "==> Creating $DMG"
STAGING="$BUILD_DIR/dmg"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo
echo "Done: $DMG"
echo "  Architectures: $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
