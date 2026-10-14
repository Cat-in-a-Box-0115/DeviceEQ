#!/bin/bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
DEST=${1:-/Applications/DeviceEQ.app}
SOURCE="$ROOT/build.noindex/DeviceEQ.app"
# Validate the new bundle before archiving/replacing an installed copy.
codesign --verify --deep --strict "$SOURCE"
if pgrep -x DeviceEQ >/dev/null; then
  echo 'Quit DeviceEQ before installing.' >&2
  exit 1
fi
if [ -e "$DEST" ]; then
  IDENTIFIER=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DEST/Contents/Info.plist")
  if [ "$IDENTIFIER" != "org.deviceeq.app" ]; then
    echo 'Destination belongs to another app; refusing to replace it.' >&2
    exit 1
  fi
  BACKUP="$DEST.backup.$(date +%Y%m%d%H%M%S).zip"
  ditto -c -k --keepParent "$DEST" "$BACKUP"
  /usr/bin/unzip -tq "$BACKUP" >/dev/null
  rm -rf "$DEST"
  echo "Previous app preserved: $BACKUP"
fi
ditto "$SOURCE" "$DEST"
codesign --verify --deep --strict "$DEST"
open "$DEST"
echo "Installed $DEST"
