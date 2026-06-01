#!/bin/bash
# Notarize ZoomShot.app with Apple and staple the ticket.
# Requires a notarytool keychain profile named "ZoomShot" — create it with:
#   xcrun notarytool store-credentials "ZoomShot" \
#     --apple-id "you@example.com" --team-id ZH7HN3N93K --password "xxxx-xxxx-xxxx-xxxx"
set -euo pipefail

cd "$(dirname "$0")"

APP_BUNDLE="ZoomShot.app"
ZIP_PATH="ZoomShot.zip"
PROFILE="${ZOOMSHOT_NOTARY_PROFILE:-ZoomShot}"

if [ ! -d "$APP_BUNDLE" ]; then
    echo "ZoomShot.app not found — run ./build.sh first." >&2
    exit 1
fi

echo "==> Zipping app for submission..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Submitting to Apple notary service (this can take a few minutes)..."
xcrun notarytool submit "$ZIP_PATH" \
    --keychain-profile "$PROFILE" \
    --wait

echo "==> Stapling the ticket..."
xcrun stapler staple "$APP_BUNDLE"

echo "==> Verifying Gatekeeper acceptance..."
spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

echo "==> Repacking notarized zip..."
rm -f "$ZIP_PATH"
ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

echo "==> Done."
echo "Notarized bundle: $(pwd)/$APP_BUNDLE"
echo "Distributable zip: $(pwd)/$ZIP_PATH"
