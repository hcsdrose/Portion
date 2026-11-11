#!/bin/bash
# Builds Portion.app.
#
#   ./build.sh            → dist/Portion-<version>.dmg, signed with your local certificate
#                           (for your own Mac, or to hand to friends)
#   ./build.sh appstore   → dist/Portion-<version>.pkg, signed for Mac App Store upload
#                           (see AppStore/README.md for the one-time setup)
#
# Settings (environment variables):
#   VERSION=1.2.0         marketing version shown in the App Store (default 1.0.0)
#   BUILD=7               build number; must go up with every App Store upload (default 1)
#   BUNDLE_ID=…           default com.christopherrose.Portion
#   App Store mode also needs TEAM_ID and APP_STORE_PROFILE (see AppStore/README.md).
set -euo pipefail
cd "$(dirname "$0")"

MODE="${1:-direct}"
case "$MODE" in direct|appstore) ;; *) echo "Usage: ./build.sh [appstore]" >&2; exit 1 ;; esac

APP_NAME="Portion"
VERSION="${VERSION:-1.0.0}"
BUILD="${BUILD:-1}"
BUNDLE_ID="${BUNDLE_ID:-com.christopherrose.Portion}"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
DIST_DIR="dist"
ENTITLEMENTS="Resources/Portion.entitlements"

fail() { echo "!! $*" >&2; exit 1; }

# --- App Store prerequisites (checked up front, before the slow part) ---------
if [ "$MODE" = appstore ]; then
  [ -n "${TEAM_ID:-}" ] || fail "Set TEAM_ID to your 10-character Apple Developer Team ID. See AppStore/README.md."
  [ -f "${APP_STORE_PROFILE:-}" ] || fail "Set APP_STORE_PROFILE to the path of your Mac App Store .provisionprofile. See AppStore/README.md."
  APP_SIGN_IDENTITY="${APP_SIGN_IDENTITY:-Apple Distribution}"
  INSTALLER_SIGN_IDENTITY="${INSTALLER_SIGN_IDENTITY:-3rd Party Mac Developer Installer}"
  security find-identity -v -p codesigning | grep -q "$APP_SIGN_IDENTITY" ||
    fail "No \"$APP_SIGN_IDENTITY\" certificate in your keychain. See AppStore/README.md, step 3."
  security find-identity -v | grep -q "$INSTALLER_SIGN_IDENTITY" ||
    fail "No \"$INSTALLER_SIGN_IDENTITY\" certificate in your keychain. See AppStore/README.md, step 3."
  # Apple rejects uploads that don't say which Xcode and SDK built them.
  XCODE_VERSION_OUTPUT="$(xcodebuild -version 2>/dev/null)" ||
    fail "App Store uploads must be built with Xcode installed. Install Xcode from the App Store, then run: sudo xcode-select -s /Applications/Xcode.app"
  # The profile must belong to this app and team.
  PROFILE_APP_ID="$(security cms -D -i "$APP_STORE_PROFILE" 2>/dev/null |
    plutil -extract Entitlements.com\\.apple\\.application-identifier raw - 2>/dev/null || true)"
  [ "$PROFILE_APP_ID" = "$TEAM_ID.$BUNDLE_ID" ] ||
    fail "The provisioning profile is for \"$PROFILE_APP_ID\", but this build is \"$TEAM_ID.$BUNDLE_ID\"."
fi

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
    [ "$MODE" = appstore ] && fail "$arch build failed; App Store builds must include both Apple Silicon and Intel."
    echo "!! $arch build failed; continuing without it" >&2
  fi
done
[ ${#binaries[@]} -gt 0 ] || fail "Build failed"

# --- Assemble the .app bundle ------------------------------------------------
echo "==> Assembling $APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${binaries[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUILD__/$BUILD/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
  Resources/Info.plist > "$APP/Contents/Info.plist"

if [ ! -f Resources/AppIcon.icns ]; then
  echo "==> Generating icon"
  ICONSET="$BUILD_DIR/AppIcon.iconset"
  swift Scripts/make-icon.swift "$ICONSET"
  iconutil -c icns "$ICONSET" -o Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/Fonts "$APP/Contents/Resources/Fonts"   # Rubik (SIL Open Font License)
cp Resources/PrivacyInfo.xcprivacy "$APP/Contents/Resources/PrivacyInfo.xcprivacy"

# =============================================================================
if [ "$MODE" = appstore ]; then
  # --- Record the Xcode / SDK that built it (App Store Connect checks these) ---
  echo "==> Adding build environment details"
  PLIST="$APP/Contents/Info.plist"
  XCODE_VER="$(echo "$XCODE_VERSION_OUTPUT" | awk '/^Xcode/ {print $2}')"
  XCODE_BUILD="$(echo "$XCODE_VERSION_OUTPUT" | awk '/Build version/ {print $3}')"
  IFS=. read -r xmaj xmin xpatch <<< "$XCODE_VER"
  DTXCODE="$(printf '%d%d%d' "$xmaj" "${xmin:-0}" "${xpatch:-0}")"
  SDK_VER="$(xcrun --sdk macosx --show-sdk-version)"
  SDK_BUILD="$(xcrun --sdk macosx --show-sdk-build-version)"
  pb() { /usr/libexec/PlistBuddy -c "Add :$1 string $2" "$PLIST"; }
  pb DTCompiler com.apple.compilers.llvm.clang.1_0
  pb DTPlatformName macosx
  pb DTPlatformVersion "$SDK_VER"
  pb DTPlatformBuild "$SDK_BUILD"
  pb DTSDKName "macosx$SDK_VER"
  pb DTSDKBuild "$SDK_BUILD"
  pb DTXcode "$DTXCODE"
  pb DTXcodeBuild "$XCODE_BUILD"
  pb BuildMachineOSBuild "$(sw_vers -buildVersion)"

  # --- Provisioning profile + entitlements that name the app and team --------
  cp "$APP_STORE_PROFILE" "$APP/Contents/embedded.provisionprofile"
  STORE_ENTITLEMENTS="$BUILD_DIR/Portion-appstore.entitlements"
  cp "$ENTITLEMENTS" "$STORE_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.application-identifier string $TEAM_ID.$BUNDLE_ID" "$STORE_ENTITLEMENTS"
  /usr/libexec/PlistBuddy -c "Add :com.apple.developer.team-identifier string $TEAM_ID" "$STORE_ENTITLEMENTS"

  echo "==> Signing ($APP_SIGN_IDENTITY)"
  codesign --force --options runtime --entitlements "$STORE_ENTITLEMENTS" --sign "$APP_SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose "$APP"

  PKG="$DIST_DIR/$APP_NAME-$VERSION.pkg"
  echo "==> Creating $PKG ($INSTALLER_SIGN_IDENTITY)"
  rm -f "$PKG"
  productbuild --component "$APP" /Applications --sign "$INSTALLER_SIGN_IDENTITY" "$PKG"
  pkgutil --check-signature "$PKG" | head -3

  echo
  echo "Done: $PKG  (version $VERSION, build $BUILD)"
  echo "Upload it with the Transporter app. See AppStore/README.md, step 6."
  exit 0
fi

# =============================================================================
# Direct build. Sign with a stable identity so macOS keeps the Screen Recording
# permission across rebuilds. Order: $SIGN_IDENTITY if set, then the dedicated
# keychain made by Scripts/make-signing-cert.sh, then ad-hoc as a last resort.
SIGN_KEYCHAIN="$HOME/Library/Keychains/portion-signing.keychain-db"
SIGN_PASS_FILE="$HOME/Library/Application Support/Portion/signing-keychain-password"
keychain_args=()
if [ -z "${SIGN_IDENTITY:-}" ]; then
  if [ -f "$SIGN_KEYCHAIN" ] && [ -f "$SIGN_PASS_FILE" ]; then
    security unlock-keychain -p "$(cat "$SIGN_PASS_FILE")" "$SIGN_KEYCHAIN"
    SIGN_IDENTITY="Portion Signing"
    keychain_args=(--keychain "$SIGN_KEYCHAIN")
  else
    SIGN_IDENTITY="-"
    echo "!! No signing certificate found; signing ad-hoc." >&2
    echo "!! macOS will forget the Screen Recording permission after each rebuild." >&2
    echo "!! Run Scripts/make-signing-cert.sh once to fix that." >&2
  fi
fi
echo "==> Signing ($SIGN_IDENTITY)"
# Sandboxed like the App Store build, so local testing matches what reviewers get.
codesign --force --options runtime --timestamp=none --entitlements "$ENTITLEMENTS" \
  ${keychain_args[@]+"${keychain_args[@]}"} --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --verbose "$APP"

# --- Package the DMG ---------------------------------------------------------
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
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
