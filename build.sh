#!/bin/bash
# Build ZoomShot.app from the SwiftPM executable, signed with Developer ID.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="ZoomShot"
APP_BUNDLE="$APP_NAME.app"
BIN_NAME="$APP_NAME"
TEAM_ID="ZH7HN3N93K"
# Disambiguated by SHA-1 because two Developer ID certs share the same common name.
# Override with ZOOMSHOT_SIGN_IDENTITY env var if needed.
SIGN_IDENTITY="${ZOOMSHOT_SIGN_IDENTITY:-93F25A6EA578FC113F4C6FAA42289F9E31361DE6}"

echo "==> Building ($CONFIG)..."
swift build -c "$CONFIG"

BIN_PATH=".build/$CONFIG/$BIN_NAME"
if [ ! -x "$BIN_PATH" ]; then
    BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$BIN_NAME"
fi

echo "==> Assembling $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BIN_PATH" "$APP_BUNDLE/Contents/MacOS/$BIN_NAME"
cp Sources/ZoomShot/Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"

echo "==> Signing with: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" \
    --identifier com.zoomshot.app \
    --options runtime \
    --timestamp \
    --entitlements Sources/ZoomShot/Resources/ZoomShot.entitlements \
    "$APP_BUNDLE"

echo "==> Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "==> Done: $(pwd)/$APP_BUNDLE"
echo "Launch with: open $APP_BUNDLE"
echo "Notarize with: ./notarize.sh"
