#!/bin/bash
# Build ZoomShot.app from the SwiftPM executable.
set -euo pipefail

cd "$(dirname "$0")"

CONFIG="${1:-release}"
APP_NAME="ZoomShot"
APP_BUNDLE="$APP_NAME.app"
BIN_NAME="$APP_NAME"

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

echo "==> Ad-hoc signing (stable identifier)..."
codesign --force --sign - \
    --identifier com.zoomshot.app \
    --options runtime \
    --entitlements Sources/ZoomShot/Resources/ZoomShot.entitlements \
    --timestamp=none \
    "$APP_BUNDLE"

echo "==> Done: $(pwd)/$APP_BUNDLE"
echo "Launch with: open $APP_BUNDLE"
