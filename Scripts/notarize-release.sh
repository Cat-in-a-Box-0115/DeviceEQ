#!/bin/bash
# Build, sign, notarize, staple and package an official DeviceEQ release in one step.
# One-time setup is in RELEASING.md. Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./Scripts/notarize-release.sh
# Optional: NOTARY_PROFILE (default deviceeq-notary), ARCHS (default arm64).
# This script never uploads to GitHub; it prints the release command at the end.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build.noindex/DeviceEQ.app"
PROFILE=${NOTARY_PROFILE:-deviceeq-notary}
: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity (see RELEASING.md).}"
[ "$SIGN_IDENTITY" != "-" ] || { echo 'SIGN_IDENTITY must be a Developer ID, not ad-hoc.' >&2; exit 1; }
security find-identity -v -p codesigning | grep -Fq "$SIGN_IDENTITY" \
  || { echo "Signing identity not found in your keychain: $SIGN_IDENTITY" >&2; exit 1; }

echo '==> Building and testing'
SIGN_IDENTITY="$SIGN_IDENTITY" "$ROOT/build.sh"
"$ROOT/Tests/verify.sh"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Submitting to Apple notary service (profile: $PROFILE); this usually takes a few minutes"
SUBMIT=$(mktemp -d)/DeviceEQ-notarize.zip
ditto -c -k --keepParent "$APP" "$SUBMIT"
xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait
rm -f "$SUBMIT"

echo '==> Stapling and validating'
xcrun stapler staple "$APP"
"$ROOT/Scripts/package-release.sh" --notarized

VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
cat <<MSG

Done. Notarized artifacts are in dist/$VERSION. After testing the ZIP on a clean Mac, publish with:
  gh release create v$VERSION dist/$VERSION/DeviceEQ-$VERSION-macOS-arm64.zip dist/$VERSION/SHA256SUMS-macOS-arm64.txt --title "DeviceEQ $VERSION" --generate-notes
MSG
