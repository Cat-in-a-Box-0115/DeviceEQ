#!/bin/bash
# Run build.sh and Tests/verify.sh first. Default output is a local, non-notarized build.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
APP="$ROOT/build.noindex/DeviceEQ.app"
MODE=${1:---local}
case "$MODE" in --local|--notarized) ;; *) echo 'Usage: package-release.sh [--local|--notarized]' >&2; exit 2 ;; esac
codesign --verify --deep --strict "$APP"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'Invalid release version' >&2; exit 1; }
LABEL=local
if [ "$MODE" = --notarized ]; then
  # Only mark the artifact notarized when macOS validates both signing and ticket.
  xcrun stapler validate "$APP"
  spctl --assess --type execute --verbose "$APP"
  LABEL=macOS-arm64
fi
DEST="$ROOT/dist/$VERSION"
mkdir -p "$DEST"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$STAGE/DeviceEQ"
# Explicit public source roots. Never archive the working tree, .git, build or dist.
COPYFILE_DISABLE=1 tar -C "$ROOT" --exclude='.DS_Store' --exclude='Tests/Audio/Evidence' \
  -cf - Sources Assets Scripts Tests .github .gitignore LICENSE README.md \
  CHANGELOG.md RELEASE_CHECKLIST.md ARCHITECTURE.md CONTRIBUTING.md PRIVACY.md RELEASING.md \
  SECURITY.md ROADMAP.md docs .clang-format \
  THIRD_PARTY_NOTICES.md VERIFICATION.md build.sh install.sh uninstall.sh \
  | tar -C "$STAGE/DeviceEQ" -xf -
ditto -c -k --keepParent "$STAGE/DeviceEQ" "$DEST/DeviceEQ-$VERSION-source.zip"
ditto -c -k --keepParent "$APP" "$DEST/DeviceEQ-$VERSION-$LABEL.zip"
/usr/bin/unzip -tq "$DEST/DeviceEQ-$VERSION-source.zip"
/usr/bin/unzip -tq "$DEST/DeviceEQ-$VERSION-$LABEL.zip"
(cd "$DEST" && shasum -a 256 "DeviceEQ-$VERSION-source.zip" "DeviceEQ-$VERSION-$LABEL.zip" > "SHA256SUMS-$LABEL.txt")
echo "Artifacts: $DEST"
if [ "$MODE" = --local ]; then
  echo 'Local test build: not notarized. Follow RELEASING.md before distributing an official download.'
fi
